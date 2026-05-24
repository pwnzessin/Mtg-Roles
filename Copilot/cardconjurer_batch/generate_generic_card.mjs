import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// ── M15Regular frame constants ─────────────────────────────────────────────────

const M15_MASKS = [
  { src: "/img/frames/m15/regular/m15MaskPinline.png", name: "Pinline" },
  { src: "/img/frames/m15/regular/m15MaskTitle.png", name: "Title" },
  { src: "/img/frames/m15/regular/m15MaskType.png", name: "Type" },
  { src: "/img/frames/m15/regular/m15MaskRules.png", name: "Rules" },
  { src: "/img/frames/m15/regular/m15MaskFrame.png", name: "Frame" },
  { src: "/img/frames/m15/regular/m15MaskBorder.png", name: "Border" },
];

const M15_PT_BOUNDS = { x: 0.7573, y: 0.8848, width: 0.188, height: 0.0733 };

const COLOR_FRAMES = {
  W: { name: "White Frame",       src: "/img/frames/m15/regular/m15FrameW.png" },
  U: { name: "Blue Frame",        src: "/img/frames/m15/regular/m15FrameU.png" },
  B: { name: "Black Frame",       src: "/img/frames/m15/regular/m15FrameB.png" },
  R: { name: "Red Frame",         src: "/img/frames/m15/regular/m15FrameR.png" },
  G: { name: "Green Frame",       src: "/img/frames/m15/regular/m15FrameG.png" },
  M: { name: "Multicolored Frame",src: "/img/frames/m15/regular/m15FrameM.png" },
  A: { name: "Artifact Frame",    src: "/img/frames/m15/regular/m15FrameA.png" },
  L: { name: "Land Frame",        src: "/img/frames/m15/regular/m15FrameL.png" },
  C: { name: "Eldrazi Frame",     src: "/img/frames/m15/regular/eldrazi.png"   },
  V: { name: "Vehicle Frame",     src: "/img/frames/m15/regular/m15FrameV.png" },
};

const COLOR_PT = {
  W: { name: "White Power/Toughness",       src: "/img/frames/m15/regular/m15PTW.png" },
  U: { name: "Blue Power/Toughness",        src: "/img/frames/m15/regular/m15PTU.png" },
  B: { name: "Black Power/Toughness",       src: "/img/frames/m15/regular/m15PTB.png" },
  R: { name: "Red Power/Toughness",         src: "/img/frames/m15/regular/m15PTR.png" },
  G: { name: "Green Power/Toughness",       src: "/img/frames/m15/regular/m15PTG.png" },
  M: { name: "Multicolored Power/Toughness",src: "/img/frames/m15/regular/m15PTM.png" },
  A: { name: "Artifact Power/Toughness",    src: "/img/frames/m15/regular/m15PTA.png" },
  C: { name: "Colorless Power/Toughness",   src: "/img/frames/m15/regular/m15PTC.png" },
  V: { name: "Vehicle Power/Toughness",     src: "/img/frames/m15/regular/m15PTV.png" },
};

// ── Planeswalker frame constants ───────────────────────────────────────────────

const PW_COLOR_FRAMES = {
  W: { name: "White Frame",        src: "/img/frames/planeswalker/regular/planeswalkerFrameW.png" },
  U: { name: "Blue Frame",         src: "/img/frames/planeswalker/regular/planeswalkerFrameU.png" },
  B: { name: "Black Frame",        src: "/img/frames/planeswalker/regular/planeswalkerFrameB.png" },
  R: { name: "Red Frame",          src: "/img/frames/planeswalker/regular/planeswalkerFrameR.png" },
  G: { name: "Green Frame",        src: "/img/frames/planeswalker/regular/planeswalkerFrameG.png" },
  M: { name: "Multicolored Frame", src: "/img/frames/planeswalker/regular/planeswalkerFrameM.png" },
  A: { name: "Artifact Frame",     src: "/img/frames/planeswalker/regular/planeswalkerFrameA.png" },
};

// ── Argument parsing ───────────────────────────────────────────────────────────

function parseArgs(argv) {
  const opts = {
    input: null,
    output: null,
    artDir: null,
    artScanDir: null,
    baseUrl: null,
    headless: false,
    startLauncher: true,
    dryRun: false,
    overwrite: false,
    limit: 0,
    newerThan: null,
    basicLandLayout: "standard",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === "--input" && next)         { opts.input = next; i += 1; }
    else if (arg === "--output" && next)   { opts.output = next; i += 1; }
    else if (arg === "--art-dir" && next)      { opts.artDir = next; i += 1; }
    else if (arg === "--art-scan-dir" && next) { opts.artScanDir = next; i += 1; }
    else if (arg === "--base-url" && next) { opts.baseUrl = next; i += 1; }
    else if (arg === "--headless")  { opts.headless  = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--start-launcher") { opts.startLauncher = !next || next.startsWith("--") ? true : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--dry-run")   { opts.dryRun    = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--overwrite") { opts.overwrite = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--limit" && next)    { opts.limit = Number.parseInt(next, 10) || 0; i += 1; }
    else if (arg === "--newer-than" && next) { opts.newerThan = next; i += 1; }
    else if (arg === "--basic-land-layout" && next) { opts.basicLandLayout = next; i += 1; }
  }

  return opts;
}

// ── File parsing ───────────────────────────────────────────────────────────────

function getTag(raw, tag) {
  const m = raw.match(new RegExp(`<${tag}>[\\r\\n]*([\\s\\S]*?)[\\r\\n]*<\\/${tag}>`, "i"));
  return m ? m[1].trim() : null;
}

function parseGenericCardFile(raw, filePath) {
  const title    = getTag(raw, "TITLE");
  const typeLine = getTag(raw, "TYPE");

  if (!title || !typeLine) {
    throw new Error(`Missing TITLE/TYPE tags in ${filePath}`);
  }

  const isPlaneswalker = /planeswalker/i.test(typeLine);
  const artYPosRaw     = getTag(raw, "ART_YPOS");
  const color          = (getTag(raw, "COLOR") || "W").toUpperCase();
  const mana           = getTag(raw, "MANA") || "";
  const setCode        = getTag(raw, "SETCODE") || "";
  const artYPos        = artYPosRaw !== null ? parseFloat(artYPosRaw) : null;
  const artist         = getTag(raw, "ARTIST") || "Unknown";

  if (isPlaneswalker) {
    const abilities = [0, 1, 2, 3].map((i) => {
      const val     = getTag(raw, `ABILITY${i}`) || "";
      const pipeIdx = val.indexOf(" | ");
      if (pipeIdx === -1) return { cost: val.trim(), text: "" };
      return { cost: val.slice(0, pipeIdx).trim(), text: val.slice(pipeIdx + 3).trim() };
    });
    return { title, isPlaneswalker: true, color, mana, typeLine, setCode, artYPos,
             loyalty: getTag(raw, "LOYALTY") || "", abilities, artist };
  }

  const rules = getTag(raw, "RULES");
  if (!rules) throw new Error(`Missing RULES tag in ${filePath}`);

  return { title, isPlaneswalker: false, color, mana, typeLine, setCode, artYPos,
           pt: getTag(raw, "PT") || "", rules, flavor: getTag(raw, "FLAVOR") || "", artist };
}

function parseSetCodeInfo(setCodeRaw) {
  const tokens = String(setCodeRaw || "").trim().split(/\s+/).filter(Boolean);
  const zoomToken = tokens[2] && /^\d*\.?\d+$/.test(tokens[2]) ? parseFloat(tokens[2]) : null;
  return {
    setCode: tokens[0] ? tokens[0].toUpperCase() : "",
    rarity:  tokens[1] ? tokens[1].charAt(0).toUpperCase() : "",
    zoom:    zoomToken,
    number:  "",
  };
}

// ── Card object builder ────────────────────────────────────────────────────────

function buildCardObject(baseUrl, c, layouts = {}) {
  const setInfo = parseSetCodeInfo(c.setCode);

  const setSymbolSource = setInfo.setCode && setInfo.rarity
    ? `${baseUrl}/img/setSymbols/official/${setInfo.setCode.toLowerCase()}-${setInfo.rarity.toLowerCase()}.svg`
    : "";
  const setSymbolZoom = setInfo.zoom !== null ? setInfo.zoom : 1;

  const commonInfo = {
    width:    745,
    height:   1040,
    marginX:  0,
    marginY:  0,
    manaSymbols: [],
    artSource: "/img/blank.png",
    artX:      0,
    artY:      0,
    artZoom:   1,
    artRotate: 0,
    setSymbolSource,
    setSymbolX:    0,
    setSymbolY:    0,
    setSymbolZoom,
    watermarkSource:  "",
    watermarkX:       0,
    watermarkY:       0,
    watermarkZoom:    1,
    watermarkLeft:    false,
    watermarkRight:   false,
    watermarkOpacity: 0.4,
    watermarkBounds:  { x: 0.5, y: 0.7762, width: 0.75, height: 0.2305 },
    infoArtist:   c.artist || "Unknown",
    infoYear:     new Date().getFullYear().toString(),
    infoNumber:   setInfo.number || "",
    infoRarity:   setInfo.rarity || "",
    infoSet:      setInfo.setCode || "",
    infoLanguage: "EN",
    infoNote:     "",
    margins:             false,
    bottomInfoTranslate: 0,
    bottomInfoRotate:    0,
    bottomInfoZoom:      1,
    bottomInfoColor:     "#000000",
    hideBottomInfoBorder: false,
    serialNumber: "",
    serialTotal:  "",
    serialX:      "",
    serialY:      "",
    serialScale:  "",
  };

  // ── Planeswalker ────────────────────────────────────────────────────────────
  if (c.isPlaneswalker) {
    const colorKey  = c.color in PW_COLOR_FRAMES ? c.color : "W";
    const pwFrame   = PW_COLOR_FRAMES[colorKey];
    const abilities = c.abilities || [];
    const count     = Math.max(1, abilities.filter((a) => a.cost !== "" || a.text !== "").length);

    return {
      ...commonInfo,
      version:  "planeswalkerRegular",
      onload:   "/js/frames/versionPlaneswalker.js",
      showsFlavorBar: false,
      frames: [{ ...pwFrame, masks: [] }],
      artBounds:       { x: 0.068,   y: 0.101,  width: 0.864,  height: 0.8143 },
      setSymbolBounds: { x: 0.9227,  y: 0.5891, width: 0.12,   height: 0.0381, vertical: "center", horizontal: "right" },
      planeswalker: {
        abilities:     abilities.map((a) => a.cost),
        abilityAdjust: [0, 0, 0, 0],
        count,
        x:     0.1167,
        width: 0.8094,
      },
      text: {
        mana: {
          name: "Mana Cost", text: c.mana || "",
          y: 0.0481, width: 0.9292, height: 71 / 2100, oneLine: true,
          size: 71 / 1638, align: "right", shadowX: -0.001, shadowY: 0.0029,
          manaCost: true, manaSpacing: 0,
        },
        title: {
          name: "Title", text: `{bold}${c.title || ""}{/bold}`,
          x: 0.0867, y: 0.0372, width: 0.8267, height: 0.0548,
          oneLine: true, font: "belerenb", size: 0.0381,
        },
        type: {
          name: "Type", text: `{bold}${c.typeLine || ""}{/bold}`,
          x: 0.0867, y: 0.5625, width: 0.8267, height: 0.0548,
          oneLine: true, font: "belerenb", size: 0.0324,
        },
        ability0: { name: "Ability 1", text: abilities[0]?.text || "", x: 0.18, y: 0.6239, width: 0.7467, height: 0.0972, size: 0.0353 },
        ability1: { name: "Ability 2", text: abilities[1]?.text || "", x: 0.18, y: 0,      width: 0.7467, height: 0.0972, size: 0.0353 },
        ability2: { name: "Ability 3", text: abilities[2]?.text || "", x: 0.18, y: 0,      width: 0.7467, height: 0.0972, size: 0.0353 },
        ability3: { name: "Ability 4", text: abilities[3]?.text || "", x: 0.18, y: 0,      width: 0.7467, height: 0,      size: 0.0353 },
        loyalty: {
          name: "Loyalty", text: c.loyalty || "",
          x: 0.806, y: 0.902, width: 0.14, height: 0.0372,
          size: 0.0372, font: "belerenbsc", oneLine: true, align: "center", color: "white",
        },
      },
    };
  }

  // ── Full-art Land ──────────────────────────────────────────────────────────
  // Activated when layouts.basicLand === "fullArt" and the card's type line includes "Basic".
  if (layouts.basicLand === "fullArt" && /\bbasic\b/i.test(c.typeLine || "")) {
    const FA_LETTER = { W: "lw", U: "lu", B: "lb", R: "lr", G: "lg", M: "lm", L: "l", C: "l", A: "a", V: "v" };
    const ck = c.color in FA_LETTER ? c.color : "L";
    return {
      ...commonInfo,
      version:        "m15Regular",
      onload:         null,
      showsFlavorBar: false,
      frames: [
        { name: "Land Frame", src: `/img/frames/m15/new/fullart/${FA_LETTER[ck]}.png`, masks: [] },
      ],
      artBounds:       { x: 0, y: 0, width: 1, height: 1 },
      setSymbolBounds: { x: 0.9213, y: 0.872, width: 0.12, height: 0.041, vertical: "center", horizontal: "right" },
      text: {
        title: {
          name:    "Title",
          text:    `{bold}${c.title || ""}{/bold}`,
          x:       0.0854, y: 0.0522, width: 0.8292, height: 0.0543,
          oneLine: true, font: "belerenb", size: 0.0381, color: "white",
        },
        type: {
          name:    "Type",
          text:    `{bold}${c.typeLine || ""}{/bold}`,
          x:       0.0854, y: 0.872, width: 0.8292, height: 0.0543,
          oneLine: true, font: "belerenb", size: 0.0324, color: "white",
        },
      },
    };
  }

  // ── M15Regular ──────────────────────────────────────────────────────────────
  const colorKey  = c.color in COLOR_FRAMES ? c.color : "W";
  const mainFrame = COLOR_FRAMES[colorKey];

  // drawFrames() reverses the array before drawing, so frames[0] is drawn last (on top).
  // PT box at [0] draws on top of the card frame.
  const frames = [];
  if (c.pt && colorKey in COLOR_PT) {
    frames.push({ ...COLOR_PT[colorKey], bounds: M15_PT_BOUNDS, masks: [] });
  }
  frames.push({ ...mainFrame, masks: [] });

  let rulesText = c.rules || "";
  if (c.flavor) {
    rulesText = `${rulesText}\n{flavor}\n${c.flavor}`;
  }

  return {
    ...commonInfo,
    version:  "m15Regular",
    onload:   null,
    showsFlavorBar: !!c.flavor,
    frames,
    artBounds:       { x: 0.0767, y: 0.1129, width: 0.8476, height: 0.4429 },
    setSymbolBounds: { x: 0.9213, y: 0.591,  width: 0.12,   height: 0.041, vertical: "center", horizontal: "right" },
    text: {
      mana: {
        name:        "Mana Cost",
        text:        c.mana || "",
        y:           0.0613,
        width:       0.9292,
        height:      71 / 2100,
        oneLine:     true,
        size:        71 / 1638,
        align:       "right",
        shadowX:     -0.001,
        shadowY:     0.0029,
        manaCost:    true,
        manaSpacing: 0,
      },
      title: {
        name:    "Title",
        text:    `{bold}${c.title || ""}{/bold}`,
        x:       0.0854,
        y:       0.0522,
        width:   0.8292,
        height:  0.0543,
        oneLine: true,
        font:    "belerenb",
        size:    0.0381,
      },
      type: {
        name:    "Type",
        text:    `{bold}${c.typeLine || ""}{/bold}`,
        x:       0.0854,
        y:       0.5664,
        width:   0.8292,
        height:  0.0543,
        oneLine: true,
        font:    "belerenb",
        size:    0.0324,
      },
      rules: {
        name:   "Rules Text",
        text:   rulesText,
        x:      0.086,
        y:      0.6303,
        width:  0.828,
        height: 0.2875,
        size:   0.0362,
      },
      pt: {
        name:    "Power/Toughness",
        text:    `{bold}${c.pt || ""}{/bold}`,
        x:       0.7928,
        y:       0.902,
        width:   0.1367,
        height:  0.0372,
        size:    0.0372,
        font:    "belerenbsc",
        oneLine: true,
        align:   "center",
      },
    },
  };
}

// ── Utilities ──────────────────────────────────────────────────────────────────

function slugifyForUrl(p) {
  return p.split(path.sep).join("/");
}

function findArtworkByStem(artDir, stem) {
  if (!fs.existsSync(artDir)) return null;
  const entries = fs.readdirSync(artDir, { withFileTypes: true });
  const target  = stem.toLowerCase();
  // Prefer cropped JPG/JPEG artifacts when both PNG and JPG exist.
  const byExtPreference = [".jpg", ".jpeg", ".png"];
  for (const ext of byExtPreference) {
    const match = entries.find((entry) =>
      entry.isFile() &&
      path.extname(entry.name).toLowerCase() === ext &&
      path.parse(entry.name).name.toLowerCase() === target
    );
    if (match) {
      return path.join(artDir, match.name);
    }
  }
  return null;
}

async function waitForServer(baseUrl, timeoutMs = 45000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(baseUrl, { method: "GET" });
      if (res.ok) return true;
    } catch { /* keep retrying */ }
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

async function fetchWithTimeout(url, timeoutMs = 7000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { method: "GET", signal: controller.signal, redirect: "follow" });
  } finally {
    clearTimeout(timer);
  }
}

async function waitForCreatorReady(baseUrl, timeoutMs = 120000) {
  const candidatePaths = ["/creator/", "/creator"];
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    for (const relPath of candidatePaths) {
      try {
        const res = await fetchWithTimeout(`${baseUrl}${relPath}`, 7000);
        if (!res.ok) continue;
        const html = await res.text();
        if (html.includes("loadCard(") || html.includes("creator-23.js") || html.includes("Card Conjurer")) {
          return relPath;
        }
      } catch { /* keep retrying */ }
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  return null;
}

async function gotoWithRetries(page, url, timeoutMs = 90000, attempts = 3) {
  let lastErr;
  for (let i = 0; i < attempts; i += 1) {
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: timeoutMs });
      return;
    } catch (err) {
      lastErr = err;
      if (i < attempts - 1) await new Promise((r) => setTimeout(r, 1500));
    }
  }
  throw lastErr;
}

function maybeStartLauncher(cardConjurerRoot) {
  const launcherPath = path.join(cardConjurerRoot, "launcher.exe");
  if (!fs.existsSync(launcherPath)) {
    throw new Error(`launcher.exe not found at ${launcherPath}`);
  }
  const child = spawn(launcherPath, [], {
    cwd: cardConjurerRoot, detached: true, stdio: "ignore", windowsHide: false,
  });
  child.unref();
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!opts.input) {
    console.error(
      "Usage: node generate_generic_card.mjs --input <dir|file> [--output <dir>] [--art-dir <dir>]\n" +
      "       [--base-url <url>] [--headless true] [--start-launcher false]\n" +
      "       [--overwrite true] [--dry-run true] [--limit <n>]"
    );
    process.exit(1);
  }

  if (!opts.baseUrl) {
    opts.baseUrl = opts.startLauncher ? "http://localhost:8080" : "http://localhost:4242";
  }

  const scriptDir       = path.dirname(fileURLToPath(import.meta.url));
  const workspaceRoot   = path.resolve(scriptDir, "..", "..");
  const cardConjurerRoot= path.join(workspaceRoot, "cardconjurer-master", "cardconjurer-master");
  const localArtOutDir  = path.join(cardConjurerRoot, "local_art", "auto", "Generic");

  // Resolve input
  const inputResolved = path.resolve(opts.input);
  let txtFiles = [];
  if (fs.statSync(inputResolved).isDirectory()) {
    txtFiles = fs
      .readdirSync(inputResolved, { withFileTypes: true })
      .filter((e) => e.isFile() && path.extname(e.name).toLowerCase() === ".txt")
      .map((e) => path.join(inputResolved, e.name))
      .sort();
  } else {
    txtFiles = [inputResolved];
  }

  // --newer-than: only render files written/modified after the given ISO timestamp
  if (opts.newerThan) {
    const cutoff = new Date(opts.newerThan).getTime();
    txtFiles = txtFiles.filter((f) => fs.statSync(f).mtimeMs >= cutoff);
    console.log(`[newer-than] ${txtFiles.length} file(s) match after ${opts.newerThan}`);
  }

  const outputDir  = opts.output  ? path.resolve(opts.output)  : path.join(workspaceRoot, "Cards", "Generic");
  const reportPath = path.join(workspaceRoot, "Copilot", "cardconjurer_batch_generic_report.txt");

  fs.mkdirSync(localArtOutDir, { recursive: true });
  fs.mkdirSync(outputDir, { recursive: true });

  // Parse card files and resolve artwork
  let hadRoomCards = false;
  const cards = [];
  for (const filePath of txtFiles) {
    const raw    = fs.readFileSync(filePath, "utf8");

    // Room cards have a different structure — delegate to generate_room_card.mjs
    if (/room/i.test(getTag(raw, "LAYOUT") || "")) {
      console.log(`[ROOM] ${path.basename(filePath)} — Room card, will delegate to generate_room_card.mjs`);
      hadRoomCards = true;
      continue;
    }

    const parsed = parseGenericCardFile(raw, filePath);
    const stem   = path.parse(filePath).name;

    // Art lookup: --art-dir first, then --art-scan-dir fallback, then same dir as txt
    const artSearchDir = opts.artDir ? path.resolve(opts.artDir) : path.dirname(filePath);
    let artSrcPath = findArtworkByStem(artSearchDir, stem);
    if (!artSrcPath && opts.artScanDir) {
      artSrcPath = findArtworkByStem(path.resolve(opts.artScanDir), stem);
    }

    let artUrl = "";
    if (artSrcPath) {
      const destPath = path.join(localArtOutDir, `${stem}.png`);
      fs.copyFileSync(artSrcPath, destPath);
      artUrl = "/" + slugifyForUrl(path.relative(cardConjurerRoot, destPath));
    }

    cards.push({
      stem,
      filePath,
      ...parsed,
      artUrl,
      outputPath: path.join(outputDir, `${stem}.png`),
    });
  }

  const queue = opts.limit > 0 ? cards.slice(0, opts.limit) : cards;

  const lines = [];
  lines.push(`Generic card batch report`);
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Input: ${inputResolved}`);
  lines.push(`Output: ${outputDir}`);
  lines.push("");
  lines.push(`Total parsed cards: ${cards.length}`);
  lines.push(`Cards in run queue: ${queue.length}`);
  lines.push(`Dry run: ${opts.dryRun}`);
  lines.push("");

  if (opts.dryRun) {
    lines.push("Dry run card list:");
    for (const c of queue) {
      const cardType = c.isPlaneswalker ? "planeswalker" : "regular";
      lines.push(`- ${path.basename(c.filePath)} | title=${c.title} | type=${cardType} | color=${c.color} | art=${c.artUrl || "(none)"}`);
    }
    fs.writeFileSync(reportPath, lines.join("\n") + "\n", "utf8");
    console.log(`Dry run complete. Report: ${reportPath}`);
    return;
  }

  // ── Server readiness ──────────────────────────────────────────────────────

  let creatorPath = await waitForCreatorReady(opts.baseUrl, 8000);
  if (opts.startLauncher && !creatorPath) {
    maybeStartLauncher(cardConjurerRoot);
  }
  const isUp = await waitForServer(opts.baseUrl, opts.startLauncher ? 120000 : 45000);
  if (!isUp) {
    throw new Error(`CardConjurer not reachable at ${opts.baseUrl}. Start the launcher manually and retry.`);
  }
  if (!creatorPath) {
    creatorPath = await waitForCreatorReady(opts.baseUrl, opts.startLauncher ? 120000 : 45000);
  }
  if (!creatorPath) {
    throw new Error(`CardConjurer responded at ${opts.baseUrl}, but creator page did not become ready.`);
  }

  // ── Playwright rendering ──────────────────────────────────────────────────

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: opts.headless });
  const context = await browser.newContext({ acceptDownloads: true });
  const page    = await context.newPage();

  const PACK_SCRIPT_M15 = "/js/frames/packM15Regular-1.js";
  const CARD_KEY        = "__copilot_generic_card__";

  let generated      = 0;
  let skippedExisting = 0;
  let failed         = 0;

  try {
    await gotoWithRetries(page, `${opts.baseUrl}${creatorPath}`, 90000, 3);
    await page.waitForFunction(
      () => typeof window.downloadCard === "function" && typeof window.loadCard === "function",
      null,
      { timeout: 60000 }
    );

    // Preload M15Regular frame pack once
    await page.evaluate(async (packScript) => {
      await new Promise((resolve, reject) => {
        const existing = Array.from(document.querySelectorAll("script")).find(
          (s) => s.getAttribute("src") === packScript
        );
        if (existing) { resolve(); return; }
        const s = document.createElement("script");
        s.type  = "text/javascript";
        s.src   = packScript;
        s.onload  = () => resolve();
        s.onerror = () => reject(new Error(`Failed to load ${packScript}`));
        document.head.appendChild(s);
      });
      if (typeof window.loadFramePack === "function") window.loadFramePack();
    }, PACK_SCRIPT_M15);

    for (const c of queue) {
      if (!opts.overwrite && fs.existsSync(c.outputPath)) {
        skippedExisting += 1;
        lines.push(`SKIP_EXISTS | ${path.basename(c.filePath)} | ${c.outputPath}`);
        continue;
      }

      try {
        const cardObj = buildCardObject(opts.baseUrl, c, { basicLand: opts.basicLandLayout });

        // Load card from localStorage and immediately re-trigger set symbol with
        // the 'resetSetSymbol' flag so it auto-positions from setSymbolBounds.
        await page.evaluate(async ({ key, cardData }) => {
          localStorage.setItem(key, JSON.stringify(cardData));
          await window.loadCard(key);
          if (cardData.setSymbolSource) {
            window.uploadSetSymbol(cardData.setSymbolSource, "resetSetSymbol");
          }
        }, { key: CARD_KEY, cardData: cardObj });

        await page.waitForFunction(
          () => typeof card !== "undefined" && Array.isArray(card.frames) && card.frames.length > 0,
          null,
          { timeout: 30000 }
        );
        await page.waitForFunction(
          () => card.frames.every((f) => {
            if (!f.image) return true;
            if (!f.image.complete || f.image.naturalWidth === 0) return false;
            if (!Array.isArray(f.masks)) return true;
            return f.masks.every((m) => !m.image || (m.image.complete && m.image.naturalWidth > 0));
          }),
          null,
          { timeout: 30000 }
        );

        // For planeswalker cards: ensure the version script has run and ability layout is applied
        if (c.isPlaneswalker) {
          await page.evaluate(() => window.loadScript("/js/frames/versionPlaneswalker.js"));
          await page.waitForFunction(
            () => typeof window.planeswalkerEdited === "function",
            null,
            { timeout: 30000 }
          );
          // Wait for the planeswalker text mask image (fires resetPlaneswalkerImages on first load)
          await page.waitForFunction(
            () => !window.planeswalkerTextMask || window.planeswalkerTextMask.complete,
            null,
            { timeout: 15000 }
          );
          // Apply ability positions using the injected card.planeswalker data
          await page.evaluate(() => {
            if (typeof window.fixPlaneswalkerInputs === "function") {
              window.fixPlaneswalkerInputs(window.planeswalkerEdited);
            } else {
              window.planeswalkerEdited();
            }
          });
          await page.waitForTimeout(400);
        }

        // Wait for set symbol to load (resetSetSymbol fires on load)
        if (cardObj.setSymbolSource) {
          await page.waitForFunction(
            () => window.setSymbol && window.setSymbol.complete && window.setSymbol.naturalWidth > 0,
            null,
            { timeout: 15000 }
          );
          await page.waitForTimeout(200);
        }

        // Upload artwork
        if (c.artUrl) {
          await page.evaluate((artUrl) => window.uploadArt(artUrl, "autoFit"), c.artUrl);
          await page.waitForFunction(
            () => window.art && window.art.complete && window.art.naturalWidth > 0,
            null,
            { timeout: 15000 }
          );
        }

        // Apply art vertical offset if specified
        if (c.artYPos !== null && !Number.isNaN(c.artYPos)) {
          await page.evaluate((artYPos) => {
            card.artY = artYPos;
            const input = document.querySelector("#art-y");
            if (input) input.value = Math.round(artYPos * card.height);
          }, c.artYPos);
        }

        await page.waitForTimeout(300);

        // Render card at its native size, then copy onto an extended black canvas for
        // symmetric print-bleed border (4.4% width left/right, 1/35 height top/bottom).
        const dataUrl = await page.evaluate(() => {
          if (typeof window.drawFrames === "function") window.drawFrames();
          if (typeof window.drawCard   === "function") window.drawCard();
          if (typeof cardCanvas === "undefined") return null;
          const mx = Math.round(0.044 * 1.15 * card.width);
          const my = Math.round((1.15 / 35) * card.height);
          const ext = document.createElement("canvas");
          ext.width  = cardCanvas.width  + 2 * mx;
          ext.height = cardCanvas.height + 2 * my;
          const ctx = ext.getContext("2d");
          ctx.fillStyle = "#000000";
          ctx.fillRect(0, 0, ext.width, ext.height);
          ctx.drawImage(cardCanvas, mx, my);
          return ext.toDataURL("image/png");
        });
        if (!dataUrl) throw new Error("cardCanvas not available in page context");
        const pngBuffer = Buffer.from(dataUrl.replace(/^data:image\/png;base64,/, ""), "base64");
        fs.writeFileSync(c.outputPath, pngBuffer);

        generated += 1;
        lines.push(`OK | ${path.basename(c.filePath)} | ${c.outputPath}`);
        console.log(`[${generated}] OK: ${c.title} → ${c.outputPath}`);
      } catch (err) {
        failed += 1;
        const msg = err && err.message ? err.message : String(err);
        lines.push(`FAIL | ${path.basename(c.filePath)} | ${msg}`);
        console.error(`[FAIL] ${c.title}: ${msg}`);
      }
    }
  } finally {
    await context.close();
    await browser.close();
  }

  lines.push("");
  lines.push(`Generated:        ${generated}`);
  lines.push(`Skipped (exists): ${skippedExisting}`);
  lines.push(`Failed:           ${failed}`);

  fs.writeFileSync(reportPath, lines.join("\n") + "\n", "utf8");
  console.log(`Done. Report: ${reportPath}`);

  // ── Delegate Room cards ───────────────────────────────────────────────────
  if (hadRoomCards) {
    console.log("\n[ROOM] Starting generate_room_card.mjs for Room cards...");
    const roomScript = path.join(scriptDir, "generate_room_card.mjs");
    const roomArgs   = [roomScript];
    if (opts.input)        roomArgs.push("--input",          opts.input);
    if (opts.output)       roomArgs.push("--output",         opts.output);
    if (opts.artDir)       roomArgs.push("--art-dir",        opts.artDir);
    if (opts.baseUrl)      roomArgs.push("--base-url",       opts.baseUrl);
    roomArgs.push("--headless",        String(opts.headless));
    roomArgs.push("--start-launcher",  String(opts.startLauncher));
    roomArgs.push("--overwrite",       String(opts.overwrite));
    roomArgs.push("--dry-run",         String(opts.dryRun));
    if (opts.limit > 0)    roomArgs.push("--limit",          String(opts.limit));
    if (opts.newerThan)    roomArgs.push("--newer-than",     opts.newerThan);

    const result = spawnSync(process.execPath, roomArgs, { stdio: "inherit" });
    if (result.status !== 0) {
      console.error(`[ROOM] generate_room_card.mjs exited with code ${result.status}`);
      process.exitCode = result.status ?? 1;
    }
  }
}

main().catch((err) => {
  console.error("Fatal:", err && err.message ? err.message : err);
  process.exit(1);
});
