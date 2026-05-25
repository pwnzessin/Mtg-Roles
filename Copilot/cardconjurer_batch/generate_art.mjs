#!/usr/bin/env node
// generate_art.mjs – HuggingFace Inference API art generator for the card pipeline
//
// Usage:
//   node generate_art.mjs --names "Sol Ring,Black Lotus" --output <dir> [options]
//   node generate_art.mjs --cardlist <path-to-.txt-or-folder> --output <dir> [options]
//
// Requires a free HuggingFace API token via --token <hf_...> or HF_TOKEN env var.

import fs   from "fs";
import path from "path";

// ── CLI parsing ───────────────────────────────────────────────────────────────

const args = process.argv.slice(2);

function getArg(name, def = null) {
  const i = args.indexOf(`--${name}`);
  return i !== -1 && i + 1 < args.length ? args[i + 1] : def;
}
function hasFlag(name) { return args.includes(`--${name}`); }

const cardlistArg = getArg("cardlist");
const namesArg    = getArg("names");
const outputDir   = getArg("output");
const styleArg    = getArg("style",  "fantasy card art, digital painting, highly detailed, no text, no borders");
const prefixArg   = getArg("prefix", "");
const overwrite   = hasFlag("overwrite");
const dryRun      = hasFlag("dry-run");
const concurrency = Math.max(1, parseInt(getArg("concurrency", "1"), 10));
const width       = parseInt(getArg("width",  "626"), 10);
const height      = parseInt(getArg("height", "457"), 10);
const seedArg     = getArg("seed");
const modelArg    = getArg("model", "black-forest-labs/FLUX.1-schnell");
const tokenArg    = getArg("token") || process.env.HF_TOKEN || "";

if (!outputDir) {
  console.error("Error: --output <dir> is required.");
  process.exit(1);
}
if (!cardlistArg && !namesArg) {
  console.error("Error: --cardlist <path> or --names <csv> is required.");
  process.exit(1);
}
if (!tokenArg) {
  console.error("Error: --token <hf_...> or HF_TOKEN env var is required.");
  console.error("Get a free token at https://huggingface.co/settings/tokens");
  process.exit(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function safeName(str) {
  return str
    .replace(/[^a-zA-Z0-9 _\-',.]/g, "")
    .replace(/\s+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function getTag(text, tag) {
  const m = text.match(new RegExp(`<${tag}>([\\s\\S]*?)<\\/${tag}>`, "i"));
  return m ? m[1].trim() : "";
}

// ── Card list loading ─────────────────────────────────────────────────────────

function loadCards() {
  // Mode A: comma-separated names passed directly
  if (namesArg) {
    return namesArg
      .split(",")
      .map(n => n.trim())
      .filter(Boolean)
      .map(n => ({ name: n, type: "", color: "", stem: safeName(n) }));
  }

  const p = path.resolve(cardlistArg);
  const stat = fs.statSync(p);

  if (stat.isDirectory()) {
    // Mode B: folder of fetched .txt card files
    return fs.readdirSync(p)
      .filter(f => f.endsWith(".txt"))
      .map(f => {
        const raw  = fs.readFileSync(path.join(p, f), "utf-8");
        const name = getTag(raw, "TITLE") || path.basename(f, ".txt");
        return {
          name,
          type:  getTag(raw, "TYPE"),
          color: getTag(raw, "COLOR"),
          stem:  path.basename(f, ".txt"),  // preserves _back suffix
        };
      })
      .filter(c => c.name);
  }

  // Mode C: plain text file — one card name per line
  return fs.readFileSync(p, "utf-8")
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(l => l && !l.startsWith("#"))
    .map(n => ({ name: n, type: "", color: "", stem: safeName(n) }));
}

// ── Prompt building ───────────────────────────────────────────────────────────

const COLOR_MAP = {
  W: "white", U: "blue", B: "black", R: "red", G: "green",
  C: "colorless", M: "multicolor",
};

function buildPrompt(card) {
  const parts = [];
  if (prefixArg && prefixArg.trim()) parts.push(prefixArg.trim());
  parts.push(card.name);
  if (card.type) {
    // Shorten "Legendary Creature — Elf Warrior" → "creature"
    const typeShort = card.type.split("—")[0].trim().toLowerCase();
    if (typeShort) parts.push(typeShort);
  }
  if (card.color && COLOR_MAP[card.color]) {
    parts.push(COLOR_MAP[card.color]);
  }
  parts.push(styleArg.trim());
  return parts.join(", ");
}

// ── Art download ──────────────────────────────────────────────────────────────

async function generateArt(card) {
  const stem    = card.stem || safeName(card.name);
  const outFile = path.join(outputDir, `${stem}.jpg`);

  if (!overwrite && fs.existsSync(outFile)) {
    console.log(`  SKIP → ${stem}.jpg (exists)`);
    return "skip";
  }

  const prompt = buildPrompt(card);

  if (dryRun) {
    console.log(`  DRY  → ${stem}.jpg`);
    console.log(`         "${prompt}"`);
  }

  const url = `https://router.huggingface.co/hf-inference/models/${modelArg}`;

  const body = { inputs: prompt, parameters: { width, height } };
  if (seedArg !== null) body.parameters.seed = parseInt(seedArg, 10);

  try {
    const res = await fetch(url, {
      method:  "POST",
      headers: {
        "Authorization": `Bearer ${tokenArg}`,
        "Content-Type":  "application/json",
        "X-Wait-For-Model": "true",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const msg = await res.text().catch(() => res.statusText);
      throw new Error(`HTTP ${res.status} ${msg.slice(0, 120)}`);
    }
    const buf = Buffer.from(await res.arrayBuffer());
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(outFile, buf);
    console.log(`  OK  -> ${stem}.jpg`);
    return "ok";
  } catch (err) {
    console.error(`  FAIL -> ${stem}.jpg -- ${err.message}`);
    return "fail";
  }
}

// ── Concurrency queue ─────────────────────────────────────────────────────────

async function runQueue(cards) {
  let idx = 0, ok = 0, skip = 0, fail = 0;

  async function worker() {
    while (idx < cards.length) {
      const card = cards[idx++];
      const r    = await generateArt(card);
      if      (r === "ok" || r === "dry") ok++;
      else if (r === "skip")             skip++;
      else                               fail++;
    }
  }

  await Promise.all(Array.from({ length: concurrency }, worker));
  return { ok, skip, fail };
}

// ── Entry point ───────────────────────────────────────────────────────────────

const cards = loadCards();
if (cards.length === 0) {
  console.log("No cards found.");
  process.exit(0);
}

const sep = "─".repeat(60);
console.log(sep);
console.log(`Art generation — ${cards.length} card(s)`);
console.log(`Output: ${path.resolve(outputDir)}`);
if (dryRun) console.log("(dry-run — no files written)");
console.log(sep);

const { ok, skip, fail } = await runQueue(cards);
console.log(`\nDone. ${ok} generated, ${skip} skipped, ${fail} failed.`);
if (fail > 0) process.exit(1);
