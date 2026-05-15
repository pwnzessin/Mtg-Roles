import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

function parseArgs(argv) {
  const opts = {
    roleFolder: "Bandits",
    baseUrl: null,
    headless: false,
    startLauncher: true,
    dryRun: false,
    overwrite: false,
    artist: "Unknown",
    baseUrlProvided: false,
    limit: 0
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];

    if (arg === "--role" && next) {
      opts.roleFolder = next;
      i += 1;
    } else if (arg === "--base-url" && next) {
      opts.baseUrl = next;
      opts.baseUrlProvided = true;
      i += 1;
    } else if (arg === "--headless" && next) {
      opts.headless = next.toLowerCase() === "true";
      i += 1;
    } else if (arg === "--start-launcher" && next) {
      opts.startLauncher = next.toLowerCase() === "true";
      i += 1;
    } else if (arg === "--dry-run" && next) {
      opts.dryRun = next.toLowerCase() === "true";
      i += 1;
    } else if (arg === "--overwrite" && next) {
      opts.overwrite = next.toLowerCase() === "true";
      i += 1;
    } else if (arg === "--artist" && next) {
      opts.artist = next;
      i += 1;
    } else if (arg === "--limit" && next) {
      opts.limit = Number.parseInt(next, 10) || 0;
      i += 1;
    }
  }

  return opts;
}

function parseTaggedCardFile(raw, filePath) {
  const titleMatch = raw.match(/<TITLE>([\s\S]*?)<\/TITLE>/i);
  const roleMatch = raw.match(/<ROLE>([\s\S]*?)<\/ROLE>/i);
  const setCodeMatch = raw.match(/<SETCODE>([\s\S]*?)<\/SETCODE>/i);
  const rulesMatch = raw.match(/<RULES>[\r\n]*([\s\S]*?)[\r\n]*<\/RULES>/i);

  if (!titleMatch || !roleMatch || !rulesMatch) {
    throw new Error(`Missing TITLE/ROLE/RULES tags in ${filePath}`);
  }

  return {
    title: titleMatch[1].trim(),
    role: roleMatch[1].trim(),
    setCode: setCodeMatch ? setCodeMatch[1].trim() : "",
    rules: rulesMatch[1].trim()
  };
}

function parseSetCodeInfo(setCodeRaw) {
  const tokens = String(setCodeRaw || "").trim().split(/\s+/).filter(Boolean);
  const zoomToken = tokens[2] && /^\d*\.?\d+$/.test(tokens[2]) ? parseFloat(tokens[2]) : null;
  return {
    setCode: tokens[0] ? tokens[0].toUpperCase() : "",
    rarity: tokens[1] ? tokens[1].charAt(0).toUpperCase() : "",
    zoom: zoomToken,
    number: ""
  };
}

function singularizeRoleFolder(roleFolder) {
  const normalized = String(roleFolder || "").trim();
  const map = {
    Assassins: "Assassin",
    Bandits: "Bandit",
    Guardians: "Guardian",
    Kings: "King",
    Renegades: "Renegade"
  };

  if (map[normalized]) {
    return map[normalized];
  }

  if (normalized.toLowerCase().endsWith("s") && normalized.length > 1) {
    return normalized.slice(0, -1);
  }

  return normalized || "Assassin";
}

function resolveTemplatePath(workspaceRoot, roleFolder) {
  const templatesDir = path.join(workspaceRoot, "Cards", "templates");
  const roleStem = singularizeRoleFolder(roleFolder);
  const roleTemplatePath = path.join(templatesDir, `${roleStem}_Layout.cardconjurer`);

  if (fs.existsSync(roleTemplatePath)) {
    return roleTemplatePath;
  }

  return path.join(templatesDir, "Assassin_Layout.cardconjurer");
}

function loadTemplateCard(templatePath) {
  if (!fs.existsSync(templatePath)) {
    throw new Error(`Template file not found: ${templatePath}`);
  }

  const templateBundle = JSON.parse(fs.readFileSync(templatePath, "utf8"));
  const templateCard = templateBundle?.[0]?.data;

  if (!templateCard) {
    throw new Error(`Template file is missing a card payload: ${templatePath}`);
  }

  return templateCard;
}

function fillTemplateText(templateText, tagName, value) {
  if (typeof templateText !== "string" || !templateText.length) {
    return value;
  }

  const pattern = new RegExp(`<${tagName}>[\\s\\S]*?<\\/${tagName}>`, "i");
  return templateText.replace(pattern, value);
}

function loadRoleSetCodes(workspaceRoot) {
  const setCodesPath = path.join(workspaceRoot, "Copilot", "SetCodes.txt");
  const map = {};
  if (!fs.existsSync(setCodesPath)) {
    return map;
  }
  const lines = fs.readFileSync(setCodesPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || !trimmed.includes(":")) {
      continue;
    }
    const colonIdx = trimmed.indexOf(":");
    const role = trimmed.slice(0, colonIdx).trim();
    const value = trimmed.slice(colonIdx + 1).trim();
    if (role && value) {
      map[role] = value;
    }
  }
  return map;
}

function slugifyForUrl(p) {
  return p.split(path.sep).join("/");
}

function findArtworkByStem(artDir, stem) {
  if (!fs.existsSync(artDir)) {
    return null;
  }

  const entries = fs.readdirSync(artDir, { withFileTypes: true });
  const target = stem.toLowerCase();
  for (const entry of entries) {
    if (!entry.isFile()) {
      continue;
    }
    const ext = path.extname(entry.name).toLowerCase();
    if (ext !== ".png") {
      continue;
    }
    const base = path.parse(entry.name).name.toLowerCase();
    if (base === target) {
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
      if (res.ok) {
        return true;
      }
    } catch {
      // Keep retrying.
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

function maybeStartLauncher(cardConjurerRoot) {
  const launcherPath = path.join(cardConjurerRoot, "launcher.exe");
  if (!fs.existsSync(launcherPath)) {
    throw new Error(`launcher.exe not found at ${launcherPath}`);
  }

  const child = spawn(launcherPath, [], {
    cwd: cardConjurerRoot,
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });
  child.unref();
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.baseUrl) {
    opts.baseUrl = opts.startLauncher ? "http://localhost:8080" : "http://localhost:4242";
  }

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const workspaceRoot = path.resolve(scriptDir, "..", "..");
  const cardsRoleDir = path.join(workspaceRoot, "Cards", opts.roleFolder);
  const artworksRoleDir = path.join(workspaceRoot, "Artworks", opts.roleFolder);
  const cardConjurerRoot = path.join(workspaceRoot, "cardconjurer-master", "cardconjurer-master");
  const localArtOutDir = path.join(cardConjurerRoot, "local_art", "auto", opts.roleFolder);
  const generatedOutDir = path.join(workspaceRoot, "Cards", "templates", opts.roleFolder);
  const reportPath = path.join(workspaceRoot, "Copilot", `cardconjurer_batch_${opts.roleFolder.toLowerCase()}_report.txt`);
  const roleSetCodes = loadRoleSetCodes(workspaceRoot);
  const roleSingular = singularizeRoleFolder(opts.roleFolder);
  const roleDefaultSetCode = roleSetCodes[roleSingular] || "";

  const templatePath = resolveTemplatePath(workspaceRoot, opts.roleFolder);
  const templateCard = loadTemplateCard(templatePath);
  // Overwrite the set symbol baked into the template with the role's setcode
  const roleSetInfo = parseSetCodeInfo(roleDefaultSetCode);
  if (roleSetInfo.setCode && roleSetInfo.rarity) {
    templateCard.setSymbolSource = `${opts.baseUrl}/img/setSymbols/official/${roleSetInfo.setCode.toLowerCase()}-${roleSetInfo.rarity.toLowerCase()}.svg`;
    if (roleSetInfo.zoom !== null) {
      templateCard.setSymbolZoom = roleSetInfo.zoom;
    }
  }
  const templateText = {
    title: templateCard.text?.title?.text || "",
    type: templateCard.text?.type?.text || "",
    rules: templateCard.text?.rules?.text || ""
  };
  const templatePackScript = templateCard.version
    ? `/js/frames/pack${templateCard.version.charAt(0).toUpperCase()}${templateCard.version.slice(1)}.js`
    : null;

  if (!fs.existsSync(cardsRoleDir)) {
    throw new Error(`Role folder not found: ${cardsRoleDir}`);
  }

  fs.mkdirSync(localArtOutDir, { recursive: true });
  fs.mkdirSync(generatedOutDir, { recursive: true });

  const cardFiles = fs
    .readdirSync(cardsRoleDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && path.extname(entry.name).toLowerCase() === ".txt")
    .map((entry) => path.join(cardsRoleDir, entry.name))
    .sort((a, b) => a.localeCompare(b));

  const cards = [];
  for (const filePath of cardFiles) {
    const raw = fs.readFileSync(filePath, "utf8");
    const parsed = parseTaggedCardFile(raw, filePath);
    const effectiveSetCode = parsed.setCode || roleDefaultSetCode;
    const parsedSetInfo = parseSetCodeInfo(effectiveSetCode);
    const stem = path.parse(filePath).name;

    const artSrcPath = findArtworkByStem(artworksRoleDir, stem);
    let artUrl = "";
    if (artSrcPath) {
      const destPath = path.join(localArtOutDir, `${stem}.png`);
      fs.copyFileSync(artSrcPath, destPath);
      artUrl = "/" + slugifyForUrl(path.relative(cardConjurerRoot, destPath));
    }

    cards.push({
      stem,
      filePath,
      title: parsed.title,
      role: parsed.role,
      setCode: parsedSetInfo.setCode,
      rarity: parsedSetInfo.rarity,
      number: parsedSetInfo.number,
      rules: parsed.rules,
      artUrl,
      outputPath: path.join(generatedOutDir, `${stem}.png`)
    });
  }

  const queue = opts.limit > 0 ? cards.slice(0, opts.limit) : cards;

  const lines = [];
  lines.push(`CardConjurer batch report for role folder: ${opts.roleFolder}`);
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push("");
  lines.push(`Total parsed cards: ${cards.length}`);
  lines.push(`Cards in run queue: ${queue.length}`);
  lines.push(`Dry run: ${opts.dryRun}`);
  lines.push("");

  if (opts.dryRun) {
    lines.push("Dry run card list:");
    for (const c of queue) {
      lines.push(`- ${path.basename(c.filePath)} | title=${c.title} | art=${c.artUrl || "(none)"}`);
    }
    fs.writeFileSync(reportPath, lines.join("\n") + "\n", "utf8");
    console.log(`Dry run complete. Report: ${reportPath}`);
    return;
  }

  if (opts.startLauncher) {
    maybeStartLauncher(cardConjurerRoot);
  }

  const isUp = await waitForServer(opts.baseUrl, 45000);
  if (!isUp) {
    throw new Error(`CardConjurer not reachable at ${opts.baseUrl}. Start launcher manually and retry.`);
  }

  const { chromium } = await import("playwright");
  const browser = await chromium.launch({ headless: opts.headless });
  const context = await browser.newContext({ acceptDownloads: true });
  const page = await context.newPage();

  try {
    await page.goto(`${opts.baseUrl}/creator`, { waitUntil: "commit", timeout: 60000 });
    await page.waitForFunction(() => typeof window.downloadCard === "function" && typeof window.loadCard === "function", null, { timeout: 60000 });
    await page.evaluate(async ({ cardTemplate, packScript }) => {
      const loadScriptWait = (src) => new Promise((resolve, reject) => {
        const existing = Array.from(document.querySelectorAll("script")).find((s) => s.getAttribute("src") === src);
        if (existing) {
          if (typeof availableFrames !== "undefined" && Array.isArray(availableFrames) && availableFrames.length > 0) {
            resolve();
            return;
          }
          existing.addEventListener("load", () => resolve(), { once: true });
          existing.addEventListener("error", () => reject(new Error(`Failed to load ${src}`)), { once: true });
          return;
        }

        const script = document.createElement("script");
        script.type = "text/javascript";
        script.src = src;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error(`Failed to load ${src}`));
        document.head.appendChild(script);
      });

      if (packScript) {
        await loadScriptWait(packScript);
        if (typeof window.loadFramePack === "function") {
          window.loadFramePack();
        }
      }

      const templateKey = "__copilot_cardconjurer_template__";
      localStorage.setItem(templateKey, JSON.stringify(cardTemplate));
      await window.loadCard(templateKey);
    }, { cardTemplate: templateCard, packScript: templatePackScript });
    await page.waitForFunction(() => typeof card !== "undefined" && Array.isArray(card.frames) && card.frames.length > 0, null, { timeout: 30000 });
    await page.waitForFunction(() => card.frames.every((frame) => !frame.image || (frame.image.complete && frame.image.naturalWidth > 0)), null, { timeout: 30000 });
    await page.evaluate(() => {
      if (typeof window.drawFrames === "function") {
        window.drawFrames();
      }
      if (typeof window.drawCard === "function") {
        window.drawCard();
      }
    });

    let generated = 0;
    let skippedExisting = 0;
    let failed = 0;

    for (const c of queue) {
      if (!opts.overwrite && fs.existsSync(c.outputPath)) {
        skippedExisting += 1;
        lines.push(`SKIP_EXISTS | ${path.basename(c.filePath)} | ${c.outputPath}`);
        continue;
      }

      try {
        await page.evaluate(async () => {
          await window.loadCard("__copilot_cardconjurer_template__");
        });
        await page.waitForFunction(() => typeof card !== "undefined" && Array.isArray(card.frames) && card.frames.length > 0, null, { timeout: 30000 });
        await page.waitForFunction(() => card.frames.every((frame) => !frame.image || (frame.image.complete && frame.image.naturalWidth > 0)), null, { timeout: 30000 });

        await page.evaluate((payload) => {
          if (card.text?.title) {
            card.text.title.text = payload.templateText.title;
          }
          if (card.text?.type) {
            card.text.type.text = payload.templateText.type;
          }
          if (card.text?.rules) {
            card.text.rules.text = payload.templateText.rules;
          }
          if (card.text?.reminder) {
            card.text.reminder.text = "";
          }
          if (card.text?.pt) {
            card.text.pt.text = "";
          }

          const infoSet = document.querySelector("#info-set");
          if (infoSet) {
            infoSet.value = payload.setCode || "";
          }
          const infoRarity = document.querySelector("#info-rarity");
          if (infoRarity) {
            infoRarity.value = payload.rarity || "";
          }
          const infoNumber = document.querySelector("#info-number");
          if (infoNumber) {
            infoNumber.value = payload.number || "";
          }
          if (typeof window.bottomInfoEdited === "function") {
            window.bottomInfoEdited();
          }

          const artistValue = payload.artist || "Unknown";
          const artArtist = document.querySelector("#art-artist");
          if (artArtist) {
            artArtist.value = artistValue;
          }
          const infoArtist = document.querySelector("#info-artist");
          if (infoArtist) {
            infoArtist.value = artistValue;
          }
          if (typeof window.artistEdited === "function") {
            window.artistEdited(artistValue);
          }

          if (payload.artUrl) {
            window.uploadArt(payload.artUrl, "autoFit");
          } else {
            window.uploadArt("/img/blank.png");
          }

          if (typeof window.drawTextBuffer === "function") {
            window.drawTextBuffer();
          } else if (typeof window.drawCard === "function") {
            window.drawCard();
          }
        }, {
          ...c,
          artist: opts.artist,
          templateText: {
            title: fillTemplateText(templateText.title, "TITLE", c.title),
            type: fillTemplateText(templateText.type, "ROLE", c.role),
            rules: fillTemplateText(templateText.rules, "RULES", c.rules)
          }
        });

        await page.evaluate(() => {
          if (typeof window.drawFrames === "function") {
            window.drawFrames();
          }
        });
        await page.waitForFunction(() => window.art && window.art.complete && window.art.naturalWidth > 0, null, { timeout: 15000 });
        await page.waitForTimeout(700);

        const downloadPromise = page.waitForEvent("download", { timeout: 15000 });
        await page.evaluate(() => window.downloadCard(false, false));
        const download = await downloadPromise;
        await download.saveAs(c.outputPath);

        generated += 1;
        lines.push(`OK | ${path.basename(c.filePath)} | ${c.outputPath}`);
      } catch (err) {
        failed += 1;
        lines.push(`FAIL | ${path.basename(c.filePath)} | ${String(err && err.message ? err.message : err)}`);
      }
    }

    lines.push("");
    lines.push(`Generated: ${generated}`);
    lines.push(`Skipped existing: ${skippedExisting}`);
    lines.push(`Failed: ${failed}`);
  } finally {
    await context.close();
    await browser.close();
  }

  fs.writeFileSync(reportPath, lines.join("\n") + "\n", "utf8");
  console.log(`Done. Report: ${reportPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
