#!/usr/bin/env node
// generate_art.mjs – AI art generator for the card pipeline
//
// Usage:
//   node generate_art.mjs --names "Sol Ring,Black Lotus" --output <dir> [options]
//   node generate_art.mjs --cardlist <path-to-.txt-or-folder> --output <dir> [options]
//
// Providers:
//   huggingface (default): requires --token <hf_...> or HF_TOKEN env var.
//   midjourney:            requires --discord-token / DISCORD_TOKEN env var,
//                          --discord-channel <id>, --discord-guild <id>.
//                          Uses your Discord user token to post /imagine commands
//                          and poll for responses via the Discord HTTP API.
//                          NOTE: Discord's ToS prohibits self-bot automation;
//                          use at your own risk.

import fs             from "fs";
import path           from "path";
import { randomUUID } from "crypto";

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
const providerArg       = modelArg === "midjourney" ? "midjourney" : "huggingface";
const tokenArg          = getArg("token") || process.env.HF_TOKEN || "";
const discordTokenArg   = getArg("discord-token") || process.env.DISCORD_TOKEN || "";
const discordChannelArg = getArg("discord-channel", "");
const discordGuildArg   = getArg("discord-guild", "");

if (!outputDir) {
  console.error("Error: --output <dir> is required.");
  process.exit(1);
}
if (!cardlistArg && !namesArg) {
  console.error("Error: --cardlist <path> or --names <csv> is required.");
  process.exit(1);
}
if (providerArg === "huggingface" && !tokenArg) {
  console.error("Error: --token <hf_...> or HF_TOKEN env var is required for HuggingFace.");
  console.error("Get a free token at https://huggingface.co/settings/tokens");
  process.exit(1);
}
if (providerArg === "midjourney") {
  if (!discordTokenArg) {
    console.error("Error: --discord-token or DISCORD_TOKEN env var is required for Midjourney.");
    process.exit(1);
  }
  if (!discordChannelArg) {
    console.error("Error: --discord-channel <channel_id> is required for Midjourney.");
    process.exit(1);
  }
  if (!discordGuildArg) {
    console.error("Error: --discord-guild <guild_id> is required for Midjourney.");
    process.exit(1);
  }
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

// ── Midjourney via Discord self-bot ──────────────────────────────────────────

const MJ_BOT_ID   = "936929561302675456";
const DISCORD_API = "https://discord.com/api/v9";
let   mjCachedCmd = null;

// Browser-like headers required for Discord's application-commands/search endpoint
const DISCORD_CLIENT_HEADERS = {
  "User-Agent":         "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
  "x-discord-locale":  "en-US",
  "x-super-properties": Buffer.from(JSON.stringify({
    os: "Windows", browser: "Chrome", device: "",
    system_locale: "en-US",
    browser_user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    browser_version: "125.0.0.0", os_version: "10",
    release_channel: "stable", client_build_number: 310000, client_event_source: null,
  })).toString("base64"),
};

/** Generate a Discord snowflake nonce from the current timestamp. */
function makeNonce() {
  const DISCORD_EPOCH = 1420070400000n;
  return String((BigInt(Date.now()) - DISCORD_EPOCH) << 22n);
}

async function discordGet(endpoint, token) {
  const res = await fetch(`${DISCORD_API}${endpoint}`, {
    headers: { ...DISCORD_CLIENT_HEADERS, "Authorization": token },
  });
  if (!res.ok) {
    const msg = await res.text().catch(() => res.statusText);
    throw new Error(`Discord GET ${endpoint}: HTTP ${res.status} ${msg.slice(0, 200)}`);
  }
  return res.json();
}

async function discordPost(endpoint, token, body) {
  const res = await fetch(`${DISCORD_API}${endpoint}`, {
    method:  "POST",
    headers: { ...DISCORD_CLIENT_HEADERS, "Authorization": token, "Content-Type": "application/json" },
    body:    JSON.stringify(body),
  });
  if (res.status !== 204 && !res.ok) {
    const msg = await res.text().catch(() => res.statusText);
    throw new Error(`Discord POST ${endpoint}: HTTP ${res.status} ${msg.slice(0, 200)}`);
  }
  return res.status === 204 ? null : res.json().catch(() => null);
}

/** Fetch and cache the Midjourney /imagine slash command details. */
async function getMjImagineCmd() {
  if (mjCachedCmd) return mjCachedCmd;
  // Use the public applications endpoint — works for user-installed apps
  // (channel/guild application-commands/search returns 0 for user-install apps)
  const cmds = await discordGet(`/applications/${MJ_BOT_ID}/commands`, discordTokenArg);
  const cmd = (Array.isArray(cmds) ? cmds : []).find(c => c.name === "imagine");
  if (!cmd) throw new Error(
    `Midjourney /imagine not found in application commands. Got: ${JSON.stringify(cmds).slice(0, 200)}`,
  );
  console.log(`  MJ cmd id=${cmd.id} version=${cmd.version}`);
  mjCachedCmd = cmd;
  return cmd;
}

/** Submit a /imagine command and return the nonce string used. */
async function submitImagine(prompt, cmd) {
  const nonce = makeNonce();
  await discordPost("/interactions", discordTokenArg, {
    type:           2,
    application_id: MJ_BOT_ID,
    guild_id:       discordGuildArg,
    channel_id:     discordChannelArg,
    session_id:     randomUUID().replace(/-/g, ""),
    data: {
      version:             cmd.version,
      id:                  cmd.id,
      name:                "imagine",
      type:                1,
      options:             [{ type: 3, name: "prompt", value: prompt }],
      application_command: cmd,
      attachments:         [],
    },
    nonce,
  });
  return nonce;
}

/** Poll channel messages until matchFn returns truthy or timeout elapses. */
async function pollMessages(matchFn, timeoutMs, intervalMs = 7000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, intervalMs));
    const msgs = await discordGet(
      `/channels/${discordChannelArg}/messages?limit=20`,
      discordTokenArg,
    );
    const found = msgs.find(matchFn);
    if (found) return found;
  }
  throw new Error(`Timed out after ${timeoutMs / 1000}s waiting for Midjourney response.`);
}

async function generateArtMidjourney(card) {
  const stem    = card.stem || safeName(card.name);
  const outFile = path.join(outputDir, `${stem}.jpg`);

  if (!overwrite && fs.existsSync(outFile)) {
    console.log(`  SKIP → ${stem}.jpg (exists)`);
    return "skip";
  }

  const prompt = buildPrompt(card) + " --ar 6:7";

  if (dryRun) {
    console.log(`  DRY  → ${stem}.jpg`);
    console.log(`         "${prompt}"`);
    return "dry";
  }

  try {
    const cmd = await getMjImagineCmd();

    // 1. Submit /imagine
    console.log(`  MJ   → ${stem} (submitting…)`);
    await submitImagine(prompt, cmd);
    const submitTime = Date.now();

    // 2. Poll for the 2×2 grid message (has U1–U4 upscale buttons)
    console.log(`  MJ   → ${stem} (waiting for grid ~1–2 min…)`);
    const nameLower = card.name.toLowerCase();
    const gridMsg = await pollMessages(
      msg => {
        if (msg.author?.id !== MJ_BOT_ID) return false;
        if (!msg.attachments?.length) return false;
        if (new Date(msg.timestamp).getTime() < submitTime - 5000) return false;
        if (!(msg.content ?? "").toLowerCase().includes(nameLower)) return false;
        return msg.components?.some(row =>
          row.components?.some(btn => btn.label === "U1"),
        );
      },
      300_000, // 5 min timeout
    );

    // 3. Click U1 to upscale the top-left image
    console.log(`  MJ   → ${stem} (upscaling U1…)`);
    const u1Row = gridMsg.components.find(row =>
      row.components?.some(btn => btn.label === "U1"),
    );
    const u1Btn = u1Row.components.find(btn => btn.label === "U1");
    await discordPost("/interactions", discordTokenArg, {
      type:           3,
      application_id: MJ_BOT_ID,
      guild_id:       discordGuildArg,
      channel_id:     discordChannelArg,
      session_id:     randomUUID().replace(/-/g, ""),
      message_id:     gridMsg.id,
      message_flags:  gridMsg.flags ?? 0,
      data:           { component_type: 2, custom_id: u1Btn.custom_id },
      nonce:          makeNonce(),
    });
    const upscaleTime = Date.now();

    // 4. Poll for the upscaled single image (references the grid, no U1–U4 buttons)
    console.log(`  MJ   → ${stem} (waiting for upscale…)`);
    const upscaleMsg = await pollMessages(
      msg => {
        if (msg.author?.id !== MJ_BOT_ID) return false;
        if (!msg.attachments?.length) return false;
        if (new Date(msg.timestamp).getTime() < upscaleTime - 5000) return false;
        if (!(msg.content ?? "").toLowerCase().includes(nameLower)) return false;
        const noGridBtns = !msg.components?.some(row =>
          row.components?.some(btn => btn.label === "U1"),
        );
        const refGrid =
          msg.message_reference?.message_id === gridMsg.id ||
          msg.referenced_message?.id        === gridMsg.id;
        return noGridBtns && refGrid;
      },
      180_000, // 3 min timeout
    );

    // 5. Download attachment (MJ returns PNG; saved as .jpg for pipeline compat)
    const att    = upscaleMsg.attachments[0];
    const imgRes = await fetch(att.url);
    if (!imgRes.ok) throw new Error(`Image download failed: HTTP ${imgRes.status}`);
    const buf = Buffer.from(await imgRes.arrayBuffer());
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(outFile, buf);
    console.log(`  OK  -> ${stem}.jpg`);
    return "ok";

  } catch (err) {
    console.error(`  FAIL -> ${stem}.jpg -- ${err.message}`);
    return "fail";
  }
}

// ── Art download (HuggingFace) ────────────────────────────────────────────────

async function generateArt(card) {
  if (providerArg === "midjourney") return generateArtMidjourney(card);

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
console.log(`Art generation — ${cards.length} card(s) [${providerArg}]`);
console.log(`Output: ${path.resolve(outputDir)}`);
if (dryRun) console.log("(dry-run — no files written)");
console.log(sep);

const { ok, skip, fail } = await runQueue(cards);
console.log(`\nDone. ${ok} generated, ${skip} skipped, ${fail} failed.`);
if (fail > 0) process.exit(1);
