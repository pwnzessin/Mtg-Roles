import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
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

// ── Argument parsing ───────────────────────────────────────────────────────────

function parseArgs(argv) {
  const opts = {
    input: null,
    output: null,
    artDir: null,
    baseUrl: null,
    headless: false,
    startLauncher: true,
    dryRun: false,
    overwrite: false,
    limit: 0,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === "--input" && next)         { opts.input = next; i += 1; }
    else if (arg === "--output" && next)   { opts.output = next; i += 1; }
    else if (arg === "--art-dir" && next)  { opts.artDir = next; i += 1; }
    else if (arg === "--base-url" && next) { opts.baseUrl = next; i += 1; }
    else if (arg === "--headless")  { opts.headless  = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--start-launcher") { opts.startLauncher = !next || next.startsWith("--") ? true : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--dry-run")   { opts.dryRun    = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--overwrite") { opts.overwrite = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--limit" && next)    { opts.limit = Number.parseInt(next, 10) || 0; i += 1; }
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
  const rules    = getTag(raw, "RULES");

  if (!title || !typeLine || !rules) {
    throw new Error(`Missing TITLE/TYPE/RULES tags in ${filePath}`);
  }

  const artYPosRaw = getTag(raw, "ART_YPOS");

  return {
    title,
    color:    (getTag(raw, "COLOR") || "W").toUpperCase(),
    mana:     getTag(raw, "MANA") || "",
    typeLine,
    setCode:  getTag(raw, "SETCODE") || "",
    artYPos:  artYPosRaw !== null ? parseFloat(artYPosRaw) : null,
    pt:       getTag(raw, "PT") || "",
    rules,
    flavor:   getTag(raw, "FLAVOR") || "",
    artist:   getTag(raw, "ARTIST") || "Unknown",
  };
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

function buildCardObject(baseUrl, c) {
  const colorKey  = c.color in COLOR_FRAMES ? c.color : "W";
  const mainFrame = COLOR_FRAMES[colorKey];
  const frames    = [{ ...mainFrame, masks: [] }];

  if (c.pt && colorKey in COLOR_PT) {
    frames.push({ ...COLOR_PT[colorKey], bounds: M15_PT_BOUNDS, masks: [] });
  }

  let rulesText = c.rules || "";
  if (c.flavor) {
    rulesText = `${rulesText}\n{flavor}\n${c.flavor}`;
  }

  const setInfo = parseSetCodeInfo(c.setCode);

  return {
    width:    745,
    height:   1040,
    marginX:  0,
    marginY:  0,
    version:  "m15Regular",
    manaSymbols: [],
    frames,

    artSource: "/img/blank.png",
    artX:      0,
    artY:      0,
    artZoom:   1,
    artRotate: 0,
    artBounds: { x: 0.0767, y: 0.1129, width: 0.8476, height: 0.4429 },

    setSymbolSource:
      setInfo.setCode && setInfo.rarity
        ? `${baseUrl}/img/setSymbols/official/${setInfo.setCode.toLowerCase()}-${setInfo.rarity.toLowerCase()}.svg`
        : "",
    setSymbolX:    0,
    setSymbolY:    0,
    setSymbolZoom: setInfo.zoom !== null ? setInfo.zoom : 1,
    setSymbolBounds: {
      x: 0.9213, y: 0.591, width: 0.12, height: 0.041,
      vertical: "center", horizontal: "right",
    },

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
    showsFlavorBar:      !!c.flavor,
    serialNumber: "",
    serialTotal:  "",
    serialX:      "",
    serialY:      "",
    serialScale:  "",
    onload: null,

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
        text:    c.title || "",
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
        text:    c.typeLine || "",
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
        text:    c.pt || "",
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
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const ext = path.extname(entry.name).toLowerCase();
    if (ext !== ".png") continue;
    if (path.parse(entry.name).name.toLowerCase() === target) {
      return path.join(artDir, entry.name);
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

  const outputDir  = opts.output  ? path.resolve(opts.output)  : path.join(workspaceRoot, "Cards", "Generic");
  const reportPath = path.join(workspaceRoot, "Copilot", "cardconjurer_batch_generic_report.txt");

  fs.mkdirSync(localArtOutDir, { recursive: true });
  fs.mkdirSync(outputDir, { recursive: true });

  // Parse card files and resolve artwork
  const cards = [];
  for (const filePath of txtFiles) {
    const raw    = fs.readFileSync(filePath, "utf8");
    const parsed = parseGenericCardFile(raw, filePath);
    const stem   = path.parse(filePath).name;

    // Art lookup: --art-dir > same directory as txt file
    const artSearchDir = opts.artDir ? path.resolve(opts.artDir) : path.dirname(filePath);
    const artSrcPath   = findArtworkByStem(artSearchDir, stem);

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
      lines.push(`- ${path.basename(c.filePath)} | title=${c.title} | color=${c.color} | art=${c.artUrl || "(none)"}`);
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

  const PACK_SCRIPT = "/js/frames/packM15Regular-1.js";
  const CARD_KEY    = "__copilot_generic_card__";

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
    }, PACK_SCRIPT);

    for (const c of queue) {
      if (!opts.overwrite && fs.existsSync(c.outputPath)) {
        skippedExisting += 1;
        lines.push(`SKIP_EXISTS | ${path.basename(c.filePath)} | ${c.outputPath}`);
        continue;
      }

      try {
        const cardObj = buildCardObject(opts.baseUrl, c);

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

        // Draw
        await page.evaluate(() => {
          if (typeof window.drawFrames === "function") window.drawFrames();
          if (typeof window.drawCard   === "function") window.drawCard();
        });

        // Apply art vertical offset if specified
        if (c.artYPos !== null && !Number.isNaN(c.artYPos)) {
          await page.evaluate((artYPos) => {
            card.artY = artYPos;
            const input = document.querySelector("#art-y");
            if (input) input.value = Math.round(artYPos * card.height);
            if (typeof window.drawCard === "function") window.drawCard();
          }, c.artYPos);
          await page.waitForTimeout(200);
        }

        await page.waitForTimeout(500);

        const downloadPromise = page.waitForEvent("download", { timeout: 30000 });
        await page.evaluate(() => window.downloadCard(false, false));
        const download = await downloadPromise;
        await download.saveAs(c.outputPath);

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
}

main().catch((err) => {
  console.error("Fatal:", err && err.message ? err.message : err);
  process.exit(1);
});
