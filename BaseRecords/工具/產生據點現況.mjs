import fs from "node:fs";
import path from "node:path";

const [sourcePath, palIndexPath, outputPath, snapshotTime, workerLimitText] =
  process.argv.slice(2);

if (
  !sourcePath ||
  !palIndexPath ||
  !outputPath ||
  !snapshotTime ||
  !workerLimitText
) {
  throw new Error(
    "Usage: node 產生據點現況.mjs <Level.json> <帕魯索引.csv> <output.md> <snapshot-time> <worker-limit>",
  );
}

const workerLimit = Number(workerLimitText);
if (!Number.isInteger(workerLimit) || workerLimit < 1) {
  throw new Error("worker-limit must be a positive integer");
}

const ZERO_GUID = "00000000-0000-0000-0000-000000000000";

const facilityDefinitions = [
  ["PalBoxV2", "帕魯終端", "據點"],
  ["BaseCampWorkerExtraStation", "帕魯箱控制裝置", "據點"],
  ["BaseCampWorkHard02", "高品質監控台", "據點"],
  ["BaseCampWorkHard03", "古代監控台", "據點"],
  ["ElectricGenerator_Large", "大型發電機", "供電與增益"],
  ["EnergyStorage_Electric", "蓄電器", "供電與增益"],
  ["TransmissionTower", "輸電塔", "供電與增益"],
  ["SanityDecrease1", "α波發生器", "供電與增益"],
  ["WorkSpeedIncrease1", "β波發生器", "供電與增益"],
  ["OilPump", "原油提煉機", "採集與加工"],
  ["OilPump02", "高壓原油提煉機", "採集與加工"],
  ["CrystalPit", "六稜晶礦場", "採集與加工"],
  ["StonePit", "採石場", "採集與加工"],
  ["QuartzPit", "純水晶礦場", "採集與加工"],
  ["SkyIslandOrePit", "烈陽金屬採礦場", "採集與加工"],
  ["CoalPit", "煤礦場", "採集與加工"],
  ["SulfurPit", "硫磺礦場", "採集與加工"],
  ["CopperPit_2", "金屬礦場 II", "採集與加工"],
  ["StationDeforest2", "伐木場 II", "採集與加工"],
  ["StationDeforest3", "伐木場 III", "採集與加工"],
  ["Stump", "樹樁與斧頭", "採集與加工"],
  ["MiningTool", "礦車", "採集與加工"],
  ["Crusher", "破碎機", "採集與加工"],
  ["AncientBlastFurnace", "古代熔爐", "採集與加工"],
  ["BlastFurnace4", "巨大熔爐", "採集與加工"],
  ["AncientMultiProduct", "古代素材合成器", "採集與加工"],
  ["HugeKitchen", "大型廚房", "料理與農牧"],
  ["AncientCookingStove", "古代廚房", "料理與農牧"],
  ["FlourMill", "磨粉機", "料理與農牧"],
  ["MonsterFarm", "家畜牧場", "料理與農牧"],
  ["BreedFarm", "配種牧場", "料理與農牧"],
  ["FarmBlockV2_wheet", "小麥園", "料理與農牧"],
  ["FarmBlockV2_tomato", "蕃茄園", "料理與農牧"],
  ["FarmBlockV2_Berries", "紅色莓果園", "料理與農牧"],
  ["FarmBlockV2_Lettuce", "萵苣園", "料理與農牧"],
  ["FarmBlockV2_Potato", "馬鈴薯園", "料理與農牧"],
  ["FarmBlockV2_Carrot", "胡蘿蔔園", "料理與農牧"],
  ["FarmBlockV2_Onion", "洋蔥園", "料理與農牧"],
  ["MultiElectricHatchingPalEgg", "大型電能帕魯蛋孵化器", "孵化"],
  ["Refrigerator", "冰箱", "冷藏與飼料"],
  ["CoolerBox", "保冷箱", "冷藏與飼料"],
  ["CoolerPalFoodBox", "低溫保鮮飼料箱", "冷藏與飼料"],
  ["PalFoodBox", "飼料箱", "冷藏與飼料"],
  ["Clinic", "診療所", "醫療"],
  ["Ancient_Clinic", "古代診療所", "醫療"],
  ["MedicineFacility_03", "高級製藥台", "醫療"],
  ["OperatingTable", "帕魯手術台", "醫療"],
  ["PalMedicineBox", "藥品架", "醫療"],
  ["MedicalPalBed_04", "大型帕魯床", "休養"],
  ["MedicalPalBed_05", "帕魯治療艙", "休養"],
  ["Spa2", "高品質溫泉", "休養"],
  ["Spa3", "日式溫泉", "休養"],
  ["DimensionPalStorage", "次元帕魯倉庫", "生產與管理"],
  ["Lab", "帕魯勞動研究所", "生產與管理"],
  ["AncientWorkBench", "古代工作台", "生產與管理"],
  ["SphereFactory_Black_04", "高級帕魯球流水線", "生產與管理"],
  ["Factory_Hard_04", "高等文明作業工廠", "生產與管理"],
  ["WeaponFactory_Dirty_04", "高級武器流水線", "生產與管理"],
  ["RepairBench", "修理台", "生產與管理"],
  ["Expedition", "帕魯遠征站", "生產與管理"],
  ["CharacterRankUp", "帕魯濃縮機", "生產與管理"],
  ["BaseCampItemDispenser", "道具取出機", "生產與管理"],
  ["ItemBooth", "道具跳蚤市場", "生產與管理"],
  ["PalBooth", "帕魯跳蚤市場", "生產與管理"],
  ["ToolBoxV1", "大型工具箱", "生產與管理"],
  ["GuildChest", "公會箱", "生產與管理"],
  ["BuildableGoddessStatue", "力量石像", "增益與特殊"],
  ["OlympicCauldron", "火焰大鍋", "增益與特殊"],
  ["Cauldron", "魔女大鍋", "增益與特殊"],
  ["FishingPond2", "大型釣魚池", "增益與特殊"],
  ["AncientRelicRecycler", "古代遺物回收機", "增益與特殊"],
  ["DefenseMachinegun", "固定式機槍", "防禦"],
  ["ItemChest", "木製箱子", "儲存"],
  ["ItemChest_02", "金屬箱", "儲存"],
  ["ItemChest_03", "精煉金屬箱", "儲存"],
  ["ItemChest_04", "高級箱子", "儲存"],
];

const facilityById = new Map(
  facilityDefinitions.map(([id, name, category], order) => [
    id,
    { id, name, category, order },
  ]),
);

const passiveNames = new Map([
  ["WorldTree_CraftSpeed", "惡魔之手"],
  ["CraftSpeed_up3", "卓越技藝"],
  ["CraftSpeed_up2", "工匠精神"],
  ["Vampire", "吸血鬼"],
]);

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

function guid(value) {
  const result = scalar(value);
  return typeof result === "string" ? result.toLowerCase() : "";
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
  const lines = fs.readFileSync(csvPath, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/);
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

function genderName(value) {
  const gender = String(scalar(value) ?? "");
  if (gender.includes("Female")) return "雌性";
  if (gender.includes("Male")) return "雄性";
  return "性別未辨識";
}

function passiveList(parameter) {
  return arrayValue(parameter?.PassiveSkillList)
    .map((entry) => String(scalar(entry) ?? ""))
    .filter(Boolean)
    .map((id) => passiveNames.get(id) ?? id);
}

function palRecord(entry, palNames) {
  const parameter =
    entry.value?.RawData?.value?.object?.SaveParameter?.value;
  if (!parameter?.CharacterID || scalar(parameter.IsPlayer) === true) return null;
  const internalId = scalar(parameter.CharacterID);
  const rank = Number(scalar(parameter.Rank) ?? 1);
  return {
    instanceId: guid(entry.key?.InstanceId),
    name: palName(internalId, palNames),
    gender: genderName(parameter.Gender),
    stars: Math.max(0, Number.isFinite(rank) ? rank - 1 : 0),
    passives: passiveList(parameter),
  };
}

function workerInstanceIds(container) {
  return arrayValue(container?.value?.Slots)
    .map((slot) => guid(slot.RawData?.value?.instance_id))
    .filter((id) => id && id !== ZERO_GUID);
}

function groupPals(pals) {
  const grouped = new Map();
  for (const pal of pals) {
    if (!pal) continue;
    const current = grouped.get(pal.name) ?? { count: 0, stars: new Map() };
    current.count += 1;
    current.stars.set(pal.stars, (current.stars.get(pal.stars) ?? 0) + 1);
    grouped.set(pal.name, current);
  }
  return [...grouped]
    .map(([name, value]) => ({ name, ...value }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, "zh-Hant"));
}

function starSummary(stars) {
  return [...stars]
    .sort(([a], [b]) => b - a)
    .map(([star, count]) => `${star === 0 ? "未濃縮" : `${star} 星`} × ${count}`)
    .join("、");
}

function groupedAssignmentText(pals) {
  if (!pals.length) return "空置";
  return groupPals(pals)
    .map(({ name, count }) => `${name} ${count} 隻`)
    .join("、");
}

function breedingPalText(pal) {
  const star = pal.stars > 0 ? `、${pal.stars} 星` : "";
  const passives = pal.passives.length
    ? `、${pal.passives.join("＋")}`
    : "、無已記錄詞條";
  return `${pal.name}（${pal.gender}${star}${passives}）`;
}

function escapeCell(value) {
  return String(value).replaceAll("|", "\\|").replaceAll(/\r?\n/g, " ");
}

function chineseOrdinal(index) {
  return ["第一", "第二", "第三", "第四", "第五", "第六", "第七", "第八"][
    index
  ] ?? `第 ${index + 1}`;
}

function likelyFunctionalId(id) {
  if (/^PalEgg_|^Palegg$/i.test(id)) return false;
  return /(Farm|Kitchen|Generator|EnergyStorage|Clinic|Box|Pit|Pump|Crusher|Furnace|Mill|Factory|Workbench|Bench|Station|Lab|Medicine|Spa|Cauldron|Pond|Tower|Dispenser|Booth|Expedition|Operating|Refrigerator|CharacterRank|MedicalPalBed|DefenseMachinegun|ToolBox|WorkSpeed|SanityDecrease|AncientRelic)/i.test(
    id,
  );
}

const palNames = loadPalNames(palIndexPath);
const parsed = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
const world = parsed?.properties?.worldSaveData?.value;
if (!world) throw new Error("worldSaveData was not found");

const bases = arrayValue(world.BaseCampSaveData);
const mapObjects = arrayValue(world.MapObjectSaveData);
const works = arrayValue(world.WorkSaveData);
const containers = arrayValue(world.CharacterContainerSaveData);
const characterEntries = arrayValue(world.CharacterSaveParameterMap);

if (!bases.length) throw new Error("no base camp data was found");

const palsByInstance = new Map();
for (const entry of characterEntries) {
  const pal = palRecord(entry, palNames);
  if (pal?.instanceId) palsByInstance.set(pal.instanceId, pal);
}

const containersById = new Map(
  containers.map((entry) => [guid(entry.key?.ID), entry]),
);

const mapObjectByModelId = new Map();
const facilitiesByBase = new Map();
const unmappedByBase = new Map();

for (const object of mapObjects) {
  const raw = object.Model?.value?.RawData?.value;
  const baseId = guid(raw?.base_camp_id_belong_to);
  const objectId = String(scalar(object.MapObjectId) ?? "");
  const modelId = guid(raw?.instance_id);
  if (modelId) {
    mapObjectByModelId.set(modelId, {
      baseId,
      objectId,
      modelId,
    });
  }
  if (!baseId || baseId === ZERO_GUID || !objectId) continue;
  if (Number(raw?.hp?.current ?? 1) <= 0) continue;
  if (facilityById.has(objectId)) {
    const records = facilitiesByBase.get(baseId) ?? [];
    records.push({
      ...facilityById.get(objectId),
      modelId,
    });
    facilitiesByBase.set(baseId, records);
  } else if (likelyFunctionalId(objectId)) {
    const ids = unmappedByBase.get(baseId) ?? new Set();
    ids.add(objectId);
    unmappedByBase.set(baseId, ids);
  }
}

const assignedByModel = new Map();
for (const work of works) {
  const raw = work.RawData?.value;
  const modelId = guid(raw?.owner_map_object_model_id);
  if (!modelId || !mapObjectByModelId.has(modelId)) continue;
  const assignments = arrayValue(work.WorkAssignMap);
  const ids = assignedByModel.get(modelId) ?? new Set();
  for (const assignment of assignments) {
    const assignmentRaw = assignment.value?.RawData?.value;
    const instanceId = guid(
      assignmentRaw?.assigned_individual_id?.instance_id,
    );
    if (instanceId && instanceId !== ZERO_GUID) ids.add(instanceId);
  }
  assignedByModel.set(modelId, ids);
}

const baseSnapshots = bases.map((entry, index) => {
  const raw = entry.value?.RawData?.value;
  const baseId = guid(raw?.id || entry.key);
  const containerId = guid(
    entry.value?.WorkerDirector?.value?.RawData?.value?.container_id,
  );
  const workerIds = workerInstanceIds(containersById.get(containerId));
  const workers = workerIds.map((id) => palsByInstance.get(id)).filter(Boolean);
  const facilities = facilitiesByBase.get(baseId) ?? [];
  const facilityCounts = new Map();
  for (const facility of facilities) {
    const current = facilityCounts.get(facility.id) ?? {
      ...facility,
      count: 0,
    };
    current.count += 1;
    facilityCounts.set(facility.id, current);
  }
  const facilitiesWithAssignments = facilities.map((facility) => ({
    ...facility,
    pals: [...(assignedByModel.get(facility.modelId) ?? [])]
      .map((id) => palsByInstance.get(id))
      .filter(Boolean),
  }));
  return {
    index,
    baseId,
    workers,
    workerIds,
    facilityCounts: [...facilityCounts.values()].sort(
      (a, b) => a.order - b.order,
    ),
    ranches: facilitiesWithAssignments.filter(
      (facility) => facility.id === "MonsterFarm",
    ),
    breedingFarms: facilitiesWithAssignments.filter(
      (facility) => facility.id === "BreedFarm",
    ),
    otherAssignments: facilitiesWithAssignments.filter(
      (facility) =>
        facility.id !== "MonsterFarm" &&
        facility.id !== "BreedFarm" &&
        facility.pals.length,
    ),
    unmapped: [...(unmappedByBase.get(baseId) ?? [])].sort(),
  };
});

const lines = [
  "# 01～05 據點存檔現況（自動產生）",
  "",
  `- 存檔快照時間：${snapshotTime}（Asia/Taipei）`,
  "- 更新方式：執行儲存庫根目錄的 `update-base-records.cmd`；本檔請勿手動編輯。",
  "- 隱私保護：本檔不包含玩家名稱、玩家 UID、公會資料、據點 GUID、座標、帕魯暱稱、權杖或原始存檔內容。",
  "",
  "## 據點摘要",
  "",
  "| 據點 | 工作帕魯 | 剩餘名額 | 配種親代 | 牧場指派 |",
  "|---|---:|---:|---:|---:|",
];

for (const base of baseSnapshots) {
  const breedingCount = base.breedingFarms.reduce(
    (sum, farm) => sum + farm.pals.length,
    0,
  );
  const ranchCount = base.ranches.reduce(
    (sum, ranch) => sum + ranch.pals.length,
    0,
  );
  lines.push(
    `| ${chineseOrdinal(base.index)}據點 | ${base.workers.length}／${workerLimit} | ${Math.max(0, workerLimit - base.workers.length)} | ${breedingCount} | ${ranchCount} |`,
  );
}

for (const base of baseSnapshots) {
  const title = `${chineseOrdinal(base.index)}據點`;
  lines.push("", `## ${title}`, "", "### 功能設施", "");
  lines.push("| 分類 | 設施 | 數量 |", "|---|---|---:|");
  for (const facility of base.facilityCounts) {
    lines.push(
      `| ${escapeCell(facility.category)} | ${escapeCell(facility.name)} | ${facility.count} |`,
    );
  }
  if (!base.facilityCounts.length) lines.push("| — | 未辨識到功能設施 | 0 |");
  if (base.unmapped.length) {
    lines.push(
      "",
      `> 警告：${base.unmapped.length} 種可能的功能設施尚未建立中文對照：${base.unmapped.map((id) => `\`${id}\``).join("、")}`,
    );
  }

  lines.push("", "### 工作帕魯", "");
  lines.push("| 帕魯 | 數量 | 濃縮星級 |", "|---|---:|---|");
  for (const group of groupPals(base.workers)) {
    lines.push(
      `| ${escapeCell(group.name)} | ${group.count} | ${escapeCell(starSummary(group.stars))} |`,
    );
  }
  lines.push(
    `| **合計** | **${base.workers.length}／${workerLimit}** | **剩餘 ${Math.max(0, workerLimit - base.workers.length)} 個名額** |`,
  );

  if (base.ranches.length) {
    lines.push("", "### 家畜牧場指派", "");
    lines.push("| 牧場 | 指派帕魯 | 工作位 |", "|---|---|---:|");
    base.ranches.forEach((ranch, index) => {
      lines.push(
        `| ${index + 1} | ${escapeCell(groupedAssignmentText(ranch.pals))} | ${ranch.pals.length}／4 |`,
      );
    });
  }

  if (base.breedingFarms.length) {
    lines.push("", "### 配種牧場指派", "");
    lines.push("| 牧場 | 親代 | 狀態 |", "|---|---|---|");
    base.breedingFarms.forEach((farm, index) => {
      const parents = farm.pals.length
        ? farm.pals.map(breedingPalText).join(" × ")
        : "未配置";
      lines.push(
        `| ${index + 1} | ${escapeCell(parents)} | ${farm.pals.length === 2 ? "已配置 2 隻" : farm.pals.length ? `目前 ${farm.pals.length} 隻` : "空置"} |`,
      );
    });
  }

  if (base.otherAssignments.length) {
    lines.push("", "### 其他固定工作指派", "");
    lines.push("| 設施 | 指派帕魯 |", "|---|---|");
    for (const facility of base.otherAssignments) {
      lines.push(
        `| ${escapeCell(facility.name)} | ${escapeCell(groupedAssignmentText(facility.pals))} |`,
      );
    }
  }
}

lines.push(
  "",
  "## 解析限制",
  "",
  "- 功能設施數量以存檔中的有效建築物件為準；地基、牆面、屋頂、裝飾、地面掉落物與帕魯蛋不列入。",
  "- 「固定工作指派」只反映存檔已綁定的工作位；自動找工作的帕魯不一定會出現在該表。",
  "- 0 星顯示為「未濃縮」；存檔內部 `Rank` 會換算成玩家介面使用的星數。",
  "",
);

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, lines.join("\n"), "utf8");
