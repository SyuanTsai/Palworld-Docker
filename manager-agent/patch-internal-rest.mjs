import fs from "node:fs";

const dockerFile = "/app/packages/agent/dist/docker.js";
const restFile = "/app/packages/agent/dist/restapi.js";

let dockerSource = fs.readFileSync(dockerFile, "utf8");
const dockerMarker = "/** Resolve the ephemeral host port Docker assigned for the REST API (8212/tcp). */";

if (!dockerSource.includes("export async function restContainerAddress")) {
  const insertionMarker = dockerSource.includes(dockerMarker)
    ? dockerMarker
    : "export async function getStatus(rec) {";
  if (!dockerSource.includes(insertionMarker)) {
    throw new Error("Unable to locate the Docker REST helper insertion point");
  }

  const helper = `/** Resolve an internal container IP reachable from the agent. */
export async function restContainerAddress(rec) {
    const container = await findContainer(rec);
    if (!container)
        return null;
    const info = await container.inspect();
    const networks = Object.values(info.NetworkSettings.Networks ?? {});
    return networks.find((network) => network.IPAddress)?.IPAddress ?? null;
}
`;

  dockerSource = dockerSource.replace(insertionMarker, helper + insertionMarker);
  fs.writeFileSync(dockerFile, dockerSource);
}

let restSource = fs.readFileSync(restFile, "utf8");
const dockerImport = 'import * as dockerOps from "./docker.js";';
if (!restSource.includes(dockerImport)) {
  restSource = `${dockerImport}\n${restSource}`;
}

const oldDockerBlock = `    if (rec.backend === "docker") {
        const hostPort = await dockerOps.restHostPort(rec);
        if (hostPort)
            return \`http://127.0.0.1:\${hostPort}/v1/api\`;
        return \`http://127.0.0.1:\${rec.settings.RESTAPIPort}/v1/api\`;
    }`;
const newDockerBlock = `    if (rec.backend === "docker") {
        const address = await dockerOps.restContainerAddress(rec);
        if (address)
            return \`http://\${address}:\${rec.settings.RESTAPIPort}/v1/api\`;
        const hostPort = await dockerOps.restHostPort(rec);
        if (hostPort)
            return \`http://127.0.0.1:\${hostPort}/v1/api\`;
        return \`http://127.0.0.1:\${rec.settings.RESTAPIPort}/v1/api\`;
    }`;
const directRestBlock = `    return \`http://127.0.0.1:\${rec.settings.RESTAPIPort}/v1/api\`;
}`;
const newDirectRestBlock = `    if (rec.backend === "docker") {
        const address = await dockerOps.restContainerAddress(rec);
        if (address)
            return \`http://\${address}:\${rec.settings.RESTAPIPort}/v1/api\`;
    }
    return \`http://127.0.0.1:\${rec.settings.RESTAPIPort}/v1/api\`;
}`;

if (!restSource.includes("restContainerAddress(rec)")) {
  if (restSource.includes(oldDockerBlock)) {
    restSource = restSource.replace(oldDockerBlock, newDockerBlock);
  } else if (restSource.includes(directRestBlock)) {
    restSource = restSource.replace(directRestBlock, newDirectRestBlock);
  } else {
    throw new Error("Unable to locate the Docker REST URL block");
  }
}
fs.writeFileSync(restFile, restSource);

const routesFile = "/app/packages/agent/dist/routes.js";
let routesSource = fs.readFileSync(routesFile, "utf8");
const settingsImport = 'import { parsePalWorldSettingsIni } from "./settings-ini.js";';

if (!routesSource.includes(settingsImport)) {
  const importMarker = 'import { getLiveStatus, rest } from "./restapi.js";';
  if (!routesSource.includes(importMarker)) {
    throw new Error("Unable to locate the settings parser import point");
  }
  routesSource = routesSource.replace(importMarker, `${importMarker}\n${settingsImport}`);
}

const oldRawWrite = `        files.writeFile(files.fileRoot(rec, ctxOf(rec)), body.path, body.content);
        return { saved: body.path, applied: "on-next-restart" };`;
const newRawWrite = `        files.writeFile(files.fileRoot(rec, ctxOf(rec)), body.path, body.content);
        if (rec.backend === "docker" && configName === "PalWorldSettings.ini") {
            const parsed = parsePalWorldSettingsIni(body.content);
            const settings = WorldSettingsSchema.parse({ ...rec.settings, ...parsed });
            const updated = store.update(rec.id, { settings });
            dockerOps.writeConfig(store.instanceDir(rec.id), updated.settings);
        }
        return { saved: body.path, applied: "on-next-restart" };`;

if (!routesSource.includes("parsePalWorldSettingsIni(body.content)")) {
  if (!routesSource.includes(oldRawWrite)) {
    throw new Error("Unable to locate the raw settings write block");
  }
  routesSource = routesSource.replace(oldRawWrite, newRawWrite);
}
fs.writeFileSync(routesFile, routesSource);

const assetsDir = "/app/packages/web/dist/assets";
const webAsset = fs.readdirSync(assetsDir)
  .find((name) => /^index-.*\.js$/.test(name));
if (!webAsset) {
  throw new Error("Unable to locate the built web asset");
}

const webFile = `${assetsDir}/${webAsset}`;
let webSource = fs.readFileSync(webFile, "utf8");
const rawPathsPattern = /const ([A-Za-z_$][\w$]*)=\["Pal\/Saved\/Config\/WindowsServer\/PalWorldSettings\.ini","Pal\/Saved\/Config\/LinuxServer\/PalWorldSettings\.ini"\];/;

if (!webSource.includes('["Config/LinuxServer/PalWorldSettings.ini","Pal/Saved/Config/WindowsServer/PalWorldSettings.ini","Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"]')) {
  const match = webSource.match(rawPathsPattern);
  if (!match) {
    throw new Error("Unable to locate the raw settings paths in the web asset");
  }
  const rawPathsConst = match[1];
  webSource = webSource.replace(rawPathsPattern, `const ${rawPathsConst}=["Config/LinuxServer/PalWorldSettings.ini","Pal/Saved/Config/WindowsServer/PalWorldSettings.ini","Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"];`);
  fs.writeFileSync(webFile, webSource);
}

const patchedAsset = webAsset.replace(/\.js$/, "-local.js");
const patchedWebFile = `${assetsDir}/${patchedAsset}`;
fs.renameSync(webFile, patchedWebFile);

const indexFile = "/app/packages/web/dist/index.html";
let indexSource = fs.readFileSync(indexFile, "utf8");
if (!indexSource.includes(webAsset)) {
  throw new Error("Unable to locate the web asset reference in index.html");
}
indexSource = indexSource.replaceAll(webAsset, patchedAsset);
fs.writeFileSync(indexFile, indexSource);
