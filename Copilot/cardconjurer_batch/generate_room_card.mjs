import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

// ── Split frame constants (mirrored from packSplit.js) ─────────────────────────

const SPLIT_COLOR_FRAMES = {
  W: { name: "White Frame",        src: "/img/frames/m15/room/w.png" },
  U: { name: "Blue Frame",         src: "/img/frames/m15/room/u.png" },
  B: { name: "Black Frame",        src: "/img/frames/m15/room/b.png" },
  R: { name: "Red Frame",          src: "/img/frames/m15/room/r.png" },
  G: { name: "Green Frame",        src: "/img/frames/m15/room/g.png" },
  M: { name: "Multicolored Frame", src: "/img/frames/m15/room/m.png" },
  A: { name: "Artifact Frame",     src: "/img/frames/m15/room/a.png" },
  L: { name: "Land Frame",         src: "/img/frames/m15/room/l.png" },
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
    newerThan: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg  = argv[i];
    const next = argv[i + 1];
    if      (arg === "--input"  && next)       { opts.input   = next; i += 1; }
    else if (arg === "--output" && next)       { opts.output  = next; i += 1; }
    else if (arg === "--art-dir" && next)      { opts.artDir  = next; i += 1; }
    else if (arg === "--base-url" && next)     { opts.baseUrl = next; i += 1; }
    else if (arg === "--headless")             { opts.headless      = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--start-launcher")       { opts.startLauncher = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--dry-run")              { opts.dryRun        = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--overwrite")            { opts.overwrite     = !next || next.startsWith("--") ? true  : (i += 1, next.toLowerCase() === "true"); }
    else if (arg === "--limit" && next)        { opts.limit    = Number.parseInt(next, 10) || 0; i += 1; }
    else if (arg === "--newer-than" && next)   { opts.newerThan = next; i += 1; }
  }

  return opts;
}

// ── File parsing ───────────────────────────────────────────────────────────────

function getTag(raw, tag) {
  const m = raw.match(new RegExp(`<${tag}>[\\r\\n]*([\\s\\S]*?)[\\r\\n]*<\\/${tag}>`, "i"));
  return m ? m[1].trim() : null;
}

function parseRoomCardFile(raw, filePath) {
  const face1Title = getTag(raw, "FACE1_TITLE");
  const face2Title = getTag(raw, "FACE2_TITLE");

  if (!face1Title || !face2Title) {
    throw new Error(`Missing FACE1_TITLE / FACE2_TITLE tags in ${filePath}`);
  }

  return {
    color:   (getTag(raw, "COLOR") || "U").toUpperCase(),
    setCode: getTag(raw, "SETCODE") || "",
    artist:  getTag(raw, "ARTIST") || "Unknown",
    face1: {
      title: face1Title,
      mana:  getTag(raw, "FACE1_MANA") || "",
      rules: getTag(raw, "FACE1_RULES") || "",
    },
    face2: {
      title: face2Title,
      mana:  getTag(raw, "FACE2_MANA") || "",
      rules: getTag(raw, "FACE2_RULES") || "",
    },
  };
}

function parseSetCodeInfo(setCodeRaw) {
  const tokens    = String(setCodeRaw || "").trim().split(/\s+/).filter(Boolean);
  const zoomToken = tokens[2] && /^\d*\.?\d+$/.test(tokens[2]) ? parseFloat(tokens[2]) : null;
  return {
    setCode: tokens[0] ? tokens[0].toUpperCase() : "",
    rarity:  tokens[1] ? tokens[1].charAt(0).toUpperCase() : "",
    zoom:    zoomToken,
    number:  "",
  };
}

// ── Card object builder ────────────────────────────────────────────────────────

function buildRoomCardObject(baseUrl, c) {
  const setInfo = parseSetCodeInfo(c.setCode);

  const setSymbolSource = setInfo.setCode && setInfo.rarity
    ? `${baseUrl}/img/setSymbols/official/${setInfo.setCode.toLowerCase()}-${setInfo.rarity.toLowerCase()}.svg`
    : "";
  const setSymbolZoom = setInfo.zoom !== null ? setInfo.zoom : 1;

  const colorKey = c.color in SPLIT_COLOR_FRAMES ? c.color : "U";
  const frame    = SPLIT_COLOR_FRAMES[colorKey];

  return {
    width:    745,
    height:   1040,
    marginX:  0,
    marginY:  0,
    manaSymbols: [],

    version:        "split",
    onload:         null,
    showsFlavorBar: false,

    // masks: [] — do NOT include both split masks. drawFrames() applies masks
    // with source-in compositing (intersection). top.svg ∩ bottom.svg = empty
    // → invisible frame. The frame PNG already contains the full visual chrome.
    frames: [{ ...frame, masks: [] }],

    // Art spans the full continuous art window of both doors
    artSource: "/img/blank.png",
    artX:      0,
    artY:      0,
    artZoom:   1,
    artRotate: 0,
    artBounds: { x: 0.158, y: 0.0534, width: 0.3734, height: 0.887 },

    // Set symbol on the horizontal divider bar
    setSymbolSource,
    setSymbolX:      0,
    setSymbolY:      0,
    setSymbolZoom,
    setSymbolBounds:  { x: 0.5, y: 0.08, width: 0.067, height: 0.048, vertical: "center", horizontal: "center" },
    setSymbolRotate:  -90,

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

    margins:              false,
    bottomInfoTranslate:  0,
    bottomInfoRotate:     0,
    bottomInfoZoom:       1,
    bottomInfoColor:      "#000000",
    hideBottomInfoBorder: false,

    serialNumber: "",
    serialTotal:  "",
    serialX:      "",
    serialY:      "",
    serialScale:  "",

    text: {
      // ── Face 2 — right door (landscape) / top half (portrait output) ──────
      mana: {
        name: "Mana Cost (Right)", text: c.face2.mana,
        x: 0.0847, y: 0.4381, width: 0.5367, height: 71 / 2100,
        oneLine: true, size: 71 / 1638, align: "right",
        shadowX: -0.001, shadowY: 0.0029,
        manaCost: true, manaSpacing: 0, rotation: -90,
      },
      title: {
        name: "Title (Right)", text: `{bold}${c.face2.title}{/bold}`,
        x: 0.072, y: 0.4381, width: 0.5367, height: 0.0543,
        oneLine: true, font: "belerenb", size: 0.0381, rotation: -90,
      },
      type: {
        name: "Type (Right)", text: "Enchantment \u2014 Room",
        x: 0.55, y: 0.4381, width: 0.5367, height: 0.0286,
        oneLine: true, font: "belerenb", size: 0.0286, rotation: -90,
      },
      rules: {
        name: "Rules Text (Right)", text: c.face2.rules,
        x: 0.6087, y: 0.4334, width: 0.5174, height: 0.2443,
        size: 0.0362, rotation: -90,
      },

      // ── Face 1 — left door (landscape) / bottom half (portrait output) ────
      mana2: {
        name: "Mana Cost (Left)", text: c.face1.mana,
        x: 0.0847, y: 0.8943, width: 0.5367, height: 71 / 2100,
        oneLine: true, size: 71 / 1638, align: "right",
        shadowX: -0.001, shadowY: 0.0029,
        manaCost: true, manaSpacing: 0, rotation: -90,
      },
      title2: {
        name: "Title (Left)", text: `{bold}${c.face1.title}{/bold}`,
        x: 0.072, y: 0.8943, width: 0.5367, height: 0.0543,
        oneLine: true, font: "belerenb", size: 0.0381, rotation: -90,
      },
      type2: {
        name: "Type (Left)", text: "Enchantment \u2014 Room",
        x: 0.55, y: 0.8943, width: 0.5367, height: 0.0286,
        oneLine: true, font: "belerenb", size: 0.0286, rotation: -90,
      },
      rules2: {
        name: "Rules Text (Left)", text: c.face1.rules,
        x: 0.6087, y: 0.8896, width: 0.5174, height: 0.2443,
        size: 0.0362, rotation: -90,
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
  for (const ext of [".jpg", ".jpeg", ".png"]) {
    const match = entries.find(
      (e) => e.isFile() &&
             path.extname(e.name).toLowerCase() === ext &&
             path.parse(e.name).name.toLowerCase() === target
    );
    if (match) return path.join(artDir, match.name);
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
      "Usage: node generate_room_card.mjs --input <dir|file> [--output <dir>] [--art-dir <dir>]\n" +
      "       [--base-url <url>] [--headless true] [--start-launcher false]\n" +
      "       [--overwrite true] [--dry-run true] [--limit <n>]\n\n" +
      "Renders Room cards (.txt files containing <LAYOUT>room</LAYOUT>) using the\n" +
      "M15 Split frame with one shared art spanning both doors."
    );
    process.exit(1);
  }

  if (!opts.baseUrl) {
    opts.baseUrl = opts.startLauncher ? "http://localhost:8080" : "http://localhost:4242";
  }

  const scriptDir        = path.dirname(fileURLToPath(import.meta.url));
  const workspaceRoot    = path.resolve(scriptDir, "..", "..");
  const cardConjurerRoot = path.join(workspaceRoot, "cardconjurer-master", "cardconjurer-master");
  const localArtOutDir   = path.join(cardConjurerRoot, "local_art", "auto", "Rooms");

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

  // Filter to only Room card files
  txtFiles = txtFiles.filter((f) => {
    const raw = fs.readFileSync(f, "utf8");
    return /room/i.test(getTag(raw, "LAYOUT") || "");
  });

  if (txtFiles.length === 0) {
    console.log("No Room card files found (expected <LAYOUT>room</LAYOUT> tag).");
    return;
  }

  // --newer-than filter
  if (opts.newerThan) {
    const cutoff = new Date(opts.newerThan).getTime();
    txtFiles = txtFiles.filter((f) => fs.statSync(f).mtimeMs >= cutoff);
    console.log(`[newer-than] ${txtFiles.length} file(s) match after ${opts.newerThan}`);
  }

  const outputDir  = opts.output ? path.resolve(opts.output) : path.join(workspaceRoot, "Cards", "Generic");
  const reportPath = path.join(workspaceRoot, "Copilot", "cardconjurer_batch_room_report.txt");

  fs.mkdirSync(localArtOutDir, { recursive: true });
  fs.mkdirSync(outputDir,      { recursive: true });

  // Parse card files and resolve artwork
  const cards = [];
  for (const filePath of txtFiles) {
    const raw    = fs.readFileSync(filePath, "utf8");
    const parsed = parseRoomCardFile(raw, filePath);
    const stem   = path.parse(filePath).name;

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
  lines.push(`Room card batch report`);
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
      lines.push(`- ${path.basename(c.filePath)} | face1=${c.face1.title} | face2=${c.face2.title} | color=${c.color} | art=${c.artUrl || "(none)"}`);
    }
    fs.writeFileSync(reportPath, lines.join("\n") + "\n", "utf8");
    console.log(`Dry run complete. Report: ${reportPath}`);
    return;
  }

  // ── Server readiness ───────────────────────────────────────────────────────

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

  // ── Playwright rendering ───────────────────────────────────────────────────

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: opts.headless });
  const context = await browser.newContext({ acceptDownloads: true });
  const page    = await context.newPage();

  const PACK_SCRIPT_SPLIT = "/js/frames/packSplit.js";
  const CARD_KEY          = "__copilot_room_card__";

  let generated       = 0;
  let skippedExisting = 0;
  let failed          = 0;

  try {
    await gotoWithRetries(page, `${opts.baseUrl}${creatorPath}`, 90000, 3);
    await page.waitForFunction(
      () => typeof window.downloadCard === "function" && typeof window.loadCard === "function",
      null,
      { timeout: 60000 }
    );

    // Preload the split frame pack once
    await page.evaluate(async (packScript) => {
      await new Promise((resolve, reject) => {
        const existing = Array.from(document.querySelectorAll("script")).find(
          (s) => s.getAttribute("src") === packScript
        );
        if (existing) { resolve(); return; }
        const s = document.createElement("script");
        s.type    = "text/javascript";
        s.src     = packScript;
        s.onload  = () => resolve();
        s.onerror = () => reject(new Error(`Failed to load ${packScript}`));
        document.head.appendChild(s);
      });
      if (typeof window.loadFramePack === "function") window.loadFramePack();
    }, PACK_SCRIPT_SPLIT);

    for (const c of queue) {
      if (!opts.overwrite && fs.existsSync(c.outputPath)) {
        skippedExisting += 1;
        lines.push(`SKIP_EXISTS | ${path.basename(c.filePath)} | ${c.outputPath}`);
        continue;
      }

      try {
        const cardObj = buildRoomCardObject(opts.baseUrl, c);

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

        // Wait for set symbol
        if (cardObj.setSymbolSource) {
          await page.waitForFunction(
            () => window.setSymbol && window.setSymbol.complete && window.setSymbol.naturalWidth > 0,
            null,
            { timeout: 15000 }
          );
          await page.waitForTimeout(200);
        }

        // Upload artwork (auto-fit across both halves)
        if (c.artUrl) {
          await page.evaluate((artUrl) => window.uploadArt(artUrl, "autoFit"), c.artUrl);
          await page.waitForFunction(
            () => window.art && window.art.complete && window.art.naturalWidth > 0,
            null,
            { timeout: 15000 }
          );
        }

        await page.waitForTimeout(300);

        // Render with bleed border — drawText() populates textCanvas then calls drawCard() internally
        const dataUrl = await page.evaluate(async () => {
          if (typeof window.drawFrames === "function") window.drawFrames();
          if (typeof window.drawText   === "function") await window.drawText();
          else if (typeof window.drawCard === "function") window.drawCard();
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
        console.log(`[${generated}] OK: ${c.face1.title} // ${c.face2.title} → ${c.outputPath}`);
      } catch (err) {
        failed += 1;
        const msg = err && err.message ? err.message : String(err);
        lines.push(`FAIL | ${path.basename(c.filePath)} | ${msg}`);
        console.error(`[FAIL] ${c.face1.title} // ${c.face2.title}: ${msg}`);
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
