import fs from "node:fs";

const [sourcePath, palIndexPath, playerConfigPath, outputPath, snapshotTime] =
  process.argv.slice(2);

if (
  !sourcePath ||
  !palIndexPath ||
  !playerConfigPath ||
  !outputPath ||
  !snapshotTime
) {
  throw new Error(
    "Usage: node 產生遠征隊伍.mjs <Level.json> <帕魯索引.csv> <player-config.json> <output.md> <snapshot-time>",
  );
}

function scalar(value) {
  if (value === null || value === undefined) return value;
  if (typeof value !== "object") return value;
  if (Object.hasOwn(value, "value")) return scalar(value.value);
  return value;
}

function arrayValue(property) {
  const value = property?.value ?? property;
  if (Array.isArray(value)) return value;
  if (Array.isArray(value?.values)) return value.values;
  return [];
}

function csvFields(line) {
  const fields = [];
  let current = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        current += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      fields.push(current);
      current = "";
    } else {
      current += character;
    }
  }
  fields.push(current);
  return fields;
}

function loadPalNames(csvPath) {
  const names = new Map();
  const lines = fs
    .readFileSync(csvPath, "utf8")
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/);
  for (const line of lines.slice(1)) {
    if (!line.trim()) continue;
    const fields = csvFields(line);
    if (fields.length >= 5 && fields[4]) names.set(fields[4], fields[2]);
  }
  return names;
}

function normalizePalId(rawId) {
  const candidates = [];
  let value = String(rawId ?? "");
  candidates.push(value);
  if (value.startsWith("BOSS_")) {
    value = value.slice(5);
    candidates.push(value);
  }
  if (value.endsWith("_otomo")) {
    value = value.slice(0, -6);
    candidates.push(value);
  }
  if (value.endsWith("_Ground")) candidates.push(value.slice(0, -7));
  return [...new Set(candidates)];
}

function palName(rawId, palNames) {
  for (const candidate of normalizePalId(rawId)) {
    if (palNames.has(candidate)) return palNames.get(candidate);
  }
  return "未建立名稱對照";
}

function markdownCell(value) {
  return String(value).replaceAll("|", "\\|").replaceAll("\n", " ");
}

function parseExpeditionName(nickname) {
  const match = nickname.match(
    /^遠征\s*-\s*(.*?)\s*(\d+)\s*-\s*(.+?)\s*$/u,
  );
  if (!match) {
    return {
      element: "格式未辨識",
      number: "—",
      numberValue: Number.MAX_SAFE_INTEGER,
    };
  }
  return {
    element: match[1].trim(),
    number: match[2].padStart(2, "0"),
    numberValue: Number(match[2]),
  };
}

const playerConfig = JSON.parse(fs.readFileSync(playerConfigPath, "utf8"));
const playerName = String(playerConfig.PlayerName ?? "").trim();
const playerUid = String(playerConfig.PlayerUId ?? "").trim().toLowerCase();
if (!playerName || !playerUid) {
  throw new Error("player config must contain PlayerName and PlayerUId");
}

const parsed = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
const world = parsed?.properties?.worldSaveData?.value;
if (!world) throw new Error("worldSaveData was not found");

const entries = arrayValue(world.CharacterSaveParameterMap);
const matchingPlayers = entries.filter((entry) => {
  const parameter =
    entry.value?.RawData?.value?.object?.SaveParameter?.value;
  return (
    scalar(parameter?.IsPlayer) === true &&
    String(scalar(parameter?.NickName) ?? "") === playerName &&
    String(scalar(entry.key?.PlayerUId) ?? "").toLowerCase() === playerUid
  );
});
if (matchingPlayers.length !== 1) {
  throw new Error(
    `expected exactly one configured player, found ${matchingPlayers.length}`,
  );
}

const palNames = loadPalNames(palIndexPath);
const expeditions = [];
for (const entry of entries) {
  const parameter =
    entry.value?.RawData?.value?.object?.SaveParameter?.value;
  if (!parameter || scalar(parameter.IsPlayer) === true) continue;

  const ownerUid = String(
    scalar(parameter.OwnerPlayerUId) ?? "",
  ).toLowerCase();
  const nickname = String(scalar(parameter.NickName) ?? "").trim();
  if (ownerUid !== playerUid || !nickname.startsWith("遠征")) continue;

  const internalId = String(scalar(parameter.CharacterID) ?? "");
  const rank = Number(scalar(parameter.Rank) ?? 1);
  const rankUpExp = Number(scalar(parameter.RankUpExp) ?? 0);
  const parsedName = parseExpeditionName(nickname);
  expeditions.push({
    ...parsedName,
    pal: palName(internalId, palNames),
    stars: Number.isFinite(rank) ? Math.max(0, rank - 1) : null,
    rankUpExp:
      Number.isFinite(rankUpExp) && rankUpExp > 0 ? rankUpExp : null,
    nickname,
  });
}

if (!expeditions.length) {
  throw new Error("the configured player has no pals whose nickname starts with 遠征");
}

const preferredElementOrder = [
  "暗無",
  "暗地",
  "暗",
  "龍火",
  "龍土",
  "火",
  "龍暗",
  "無",
  "水無",
  "水冰",
  "土",
  "土暗",
  "地草",
  "地",
  "雷",
  "草",
  "格式未辨識",
];
const elementOrder = new Map(
  preferredElementOrder.map((element, index) => [element, index]),
);
const compareElements = (left, right) => {
  const leftOrder = elementOrder.get(left);
  const rightOrder = elementOrder.get(right);
  if (leftOrder !== undefined || rightOrder !== undefined) {
    return (
      (leftOrder ?? Number.MAX_SAFE_INTEGER) -
      (rightOrder ?? Number.MAX_SAFE_INTEGER)
    );
  }
  return left.localeCompare(right, "zh-Hant");
};

expeditions.sort(
  (left, right) =>
    compareElements(left.element, right.element) ||
    left.numberValue - right.numberValue ||
    left.pal.localeCompare(right.pal, "zh-Hant") ||
    left.nickname.localeCompare(right.nickname, "zh-Hant"),
);

const byElement = new Map();
for (const expedition of expeditions) {
  const summary =
    byElement.get(expedition.element) ?? {
      stars: [0, 0, 0, 0, 0],
      unknown: 0,
      total: 0,
    };
  if (
    Number.isInteger(expedition.stars) &&
    expedition.stars >= 0 &&
    expedition.stars <= 4
  ) {
    summary.stars[expedition.stars] += 1;
  } else {
    summary.unknown += 1;
  }
  summary.total += 1;
  byElement.set(expedition.element, summary);
}

const sortedElements = [...byElement.keys()].sort(compareElements);
const totals = { stars: [0, 0, 0, 0, 0], unknown: 0, total: 0 };
for (const summary of byElement.values()) {
  for (let star = 0; star <= 4; star += 1) {
    totals.stars[star] += summary.stars[star];
  }
  totals.unknown += summary.unknown;
  totals.total += summary.total;
}

const lines = [
  "# 遠征隊伍配置",
  "",
  "僅統計本機玩家設定所指定之玩家名下、暱稱以「遠征」開頭的帕魯；玩家名稱與 ID 不會寫入本文件。",
  "",
  `存檔快照：${snapshotTime}（Asia/Taipei）`,
  "",
  "## 屬性與星級統計",
  "",
  "| 屬性 | 未濃縮 | 1 星 | 2 星 | 3 星 | 4 星 | 星級未辨識 | 合計 |",
  "|---|---:|---:|---:|---:|---:|---:|---:|",
];

for (const element of sortedElements) {
  const summary = byElement.get(element);
  lines.push(
    `| ${markdownCell(element)} | ${summary.stars.join(" | ")} | ${summary.unknown} | ${summary.total} |`,
  );
}
lines.push(
  `| **總計** | **${totals.stars.join("** | **")}** | **${totals.unknown}** | **${totals.total}** |`,
  "",
  `目前共記錄 ${totals.total} 隻；完成星級取自存檔內部 \`Rank - 1\`。`,
  "",
  "## 隊員明細",
  "",
  "| 屬性 | 編號 | 帕魯 | 星級 | 濃縮進度 | 完整名稱 |",
  "|---|---|---|---:|---:|---|",
);

for (const expedition of expeditions) {
  lines.push(
    `| ${markdownCell(expedition.element)} | ${markdownCell(expedition.number)} | ${markdownCell(expedition.pal)} | ${expedition.stars ?? "未辨識"} | ${expedition.rankUpExp ?? "—"} | ${markdownCell(expedition.nickname)} |`,
  );
}

lines.push(
  "",
  "## 備註",
  "",
  "- 「濃縮進度」為存檔中的 `RankUpExp`；`—` 表示目前星級沒有額外進度。",
  "- 表格不含玩家名稱、玩家 ID、帕魯個體 ID 或其他 GUID。",
  "",
);

fs.writeFileSync(outputPath, lines.join("\n"), "utf8");
