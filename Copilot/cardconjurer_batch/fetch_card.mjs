/**
 * fetch_card.mjs — Query Scryfall by card name and write a Generic Card .txt file
 *                  plus the artwork image ready for generate_generic_card.mjs.
 *
 * Usage:
 *   node fetch_card.mjs "Lightning Bolt" "Llanowar Elves" --output Cards/Generic
 *
 * Options:
 *   --output <dir>       Directory to write .txt files (default: current dir)
 *   --art-output <dir>   Directory to write artwork .jpg files (default: same as --output)
 *   --set <code>         Prefer a specific printing, e.g. "m21"
 *   --art-version <name> Scryfall image variant for artwork
 *                        (art_crop|border_crop|normal|large|png; default: art_crop)
 *   --overwrite          Re-create files even if they already exist
 *   --no-art             Skip downloading the artwork image
 *   --dry-run            Print the .txt to stdout without writing any files
 */

import fs from "node:fs";
import path from "node:path";

const SCRYFALL_BASE  = "https://api.scryfall.com";
const USER_AGENT     = "MtgRolesCardGen/1.0";
const API_DELAY_MS   = 200; // 5 req/s — safely under Scryfall's 10 req/s limit
const ART_VERSIONS   = ["art_crop", "border_crop", "normal", "large", "png"];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── Symbol conversion (Scryfall uppercase → CardConjurer lowercase) ────────────

function convertSymbols(text) {
  if (!text) return "";
  return text
    // Tap / untap
    .replace(/\{T\}/g, "{t}")
    .replace(/\{Q\}/g, "{untap}")
    // Snow, energy
    .replace(/\{S\}/g, "{s}")
    .replace(/\{E\}/g, "{e}")
    // Phyrexian mana: {W/P} → {wp}
    .replace(/\{([WUBRG])\/P\}/gi, (_, c) => `{${c.toLowerCase()}p}`)
    // Hybrid mana: {W/U} → {wu}
    .replace(/\{([WUBRG2])\/([WUBRG])\}/gi, (_, a, b) => `{${a.toLowerCase()}${b.toLowerCase()}}`)
    // Single-letter colored/colorless/X mana
    .replace(/\{([WUBRGCX])\}/g, (_, c) => `{${c.toLowerCase()}}`)
    // Bullet point indentation used in some rules text
    .replace(/^• /gm, "• {indent}")
    // Loyalty ability markers [+N] [-N] [0] — kept as-is
    ;
}

// ── Planeswalker ability parser ────────────────────────────────────────────────

function parsePlaneswalkerAbilities(oracleText) {
  // Each PW ability is one line: "[cost]: [text]"
  // Scryfall uses Unicode minus sign (\u2212) for negative loyalty costs.
  const lines = (oracleText || "").split("\n").filter((l) => l.trim() !== "");
  const abilities = [];
  for (const line of lines) {
    const m = line.match(/^([+\-\u2212][0-9X]*|0): (.+)/);
    if (m) abilities.push({ cost: m[1].trim().replace(/\u2212/g, "-"), text: m[2].trim() });
  }
  return abilities;
}

// ── Color key ─────────────────────────────────────────────────────────────────

function determineColorKey(card) {
  const type     = card.type_line || "";
  const colors   = card.colors || [];

  // Vehicle (has its own frame regardless of color)
  if (/\bVehicle\b/.test(type)) return "V";
  // Land: use color_identity so basics/duals/shocks get the right frame color.
  // e.g. Forest → G, Mountain → R, Sacred Foundry → M, Arid Mesa → M (W+U identity)
  // For lands with no color_identity (e.g. Command Tower), fall back to produced_mana.
  // Colorless lands (Wastes, etc.) fall back to the land frame.
  if (/\bLand\b/.test(type)) {
    const identity = card.color_identity || [];
    if (identity.length >= 2) return "M";
    if (identity.length === 1) return identity[0]; // "W" "U" "B" "R" "G"
    // No color identity — check produced_mana (filters out "C" colorless and "S" snow)
    const produced = (card.produced_mana || []).filter(c => c !== "C" && c !== "S");
    if (produced.length >= 2) return "M";
    if (produced.length === 1) return produced[0];
    return "L"; // truly colorless land
  }
  // Multi-color
  if (colors.length >= 2) return "M";
  // Single color
  if (colors.length === 1) return colors[0]; // "W" "U" "B" "R" "G"
  // Colorless: artifact vs pure colorless / Eldrazi
  if (/\bArtifact\b/.test(type)) return "A";
  return "C";
}

function getPrimaryName(card) {
  if (card.card_faces && Array.isArray(card.card_faces) && card.card_faces[0] && card.card_faces[0].name) {
    return String(card.card_faces[0].name).trim();
  }
  return String(card.name || "Unknown Card").trim();
}

function getSafeFileBase(card) {
  const base = getPrimaryName(card);
  return base.replace(/[\\/]/g, "_").replace(/\s*\/\/\s*/g, " ").trim();
}

// ── Room card detection & builder ────────────────────────────────────────────

function isRoomCard(card) {
  if (card.layout !== "split") return false;
  if (!card.card_faces || card.card_faces.length < 2) return false;
  return card.card_faces.every((f) => /\bRoom\b/i.test(f.type_line || ""));
}

function buildRoomTxt(card) {
  const face1   = card.card_faces[0];
  const face2   = card.card_faces[1];
  const setCode = (card.set    || "").toUpperCase();
  const rarity  = (card.rarity || "common")[0].toUpperCase();

  // Determine color key from combined card colors
  const colors = card.colors || [];
  let colorKey;
  if      (colors.length >= 2)                            colorKey = "M";
  else if (colors.length === 1)                           colorKey = colors[0];
  else if (/\bArtifact\b/.test(face1.type_line || ""))   colorKey = "A";
  else                                                    colorKey = "C";

  const artist = face1.artist || face2.artist || card.artist || "Unknown";

  const lines = [];
  lines.push(`<LAYOUT>room</LAYOUT>`);
  lines.push(`<COLOR>${colorKey}</COLOR>`);
  lines.push(`<SETCODE>${setCode} ${rarity}</SETCODE>`);
  lines.push(`<ARTIST>${artist}</ARTIST>`);
  lines.push(``);
  lines.push(`<FACE1_TITLE>${face1.name}</FACE1_TITLE>`);
  lines.push(`<FACE1_MANA>${face1.mana_cost || ""}</FACE1_MANA>`);
  lines.push(`<FACE1_RULES>`);
  lines.push(convertSymbols(face1.oracle_text || "").trim());
  lines.push(`</FACE1_RULES>`);
  lines.push(``);
  lines.push(`<FACE2_TITLE>${face2.name}</FACE2_TITLE>`);
  lines.push(`<FACE2_MANA>${face2.mana_cost || ""}</FACE2_MANA>`);
  lines.push(`<FACE2_RULES>`);
  lines.push(convertSymbols(face2.oracle_text || "").trim());
  lines.push(`</FACE2_RULES>`);

  return lines.join("\n");
}

// ── .txt builder ──────────────────────────────────────────────────────────────

function buildTxt(card, includeFlavor = true) {
  const colorKey = determineColorKey(card);
  const cardName = getPrimaryName(card);
  const setCode  = (card.set  || "").toUpperCase();
  const rarity   = (card.rarity || "common")[0].toUpperCase(); // C U R M
  const hasPt    = card.power != null && card.toughness != null;

  // Mana cost comes from Scryfall already in {X}{R} brace format — keep as-is
  // for the MANA field (CardConjurer renders those uppercase correctly).
  // But inside oracle text, single-letter symbols need to be lowercase.
  const rules   = convertSymbols(card.oracle_text || "").trim();
  const flavor  = (card.flavor_text || "").trim();
  const mana    = (card.mana_cost   || "").trim();

  const isPlaneswalker = /planeswalker/i.test(card.type_line || "");

  const lines = [];
  lines.push(`<COLOR>${colorKey}</COLOR>`);
  lines.push(`<TITLE>${cardName}</TITLE>`);
  if (mana) lines.push(`<MANA>${mana}</MANA>`);
  lines.push(`<TYPE>${card.type_line}</TYPE>`);
  lines.push(`<SETCODE>${setCode} ${rarity}</SETCODE>`);

  if (isPlaneswalker) {
    const loyalty   = card.loyalty || "";
    const abilities = parsePlaneswalkerAbilities(card.oracle_text || "");
    if (loyalty) lines.push(`<LOYALTY>${loyalty}</LOYALTY>`);
    abilities.slice(0, 4).forEach((a, i) => {
      lines.push(`<ABILITY${i}>${a.cost} | ${convertSymbols(a.text)}</ABILITY${i}>`);
    });
  } else {
    if (hasPt) lines.push(`<PT>${card.power}/${card.toughness}</PT>`);
    lines.push(`<RULES>`);
    lines.push(rules);
    lines.push(`</RULES>`);
    if (flavor && includeFlavor) {
      lines.push(`<FLAVOR>`);
      lines.push(flavor);
      lines.push(`</FLAVOR>`);
    }
  }

  if (card.artist) lines.push(`<ARTIST>${card.artist}</ARTIST>`);

  return lines.join("\n");
}

// ── Scryfall fetch ────────────────────────────────────────────────────────────

async function fetchCard(name, preferSet) {
  const params = new URLSearchParams({ fuzzy: name });
  if (preferSet) params.set("set", preferSet.toLowerCase());

  const url = `${SCRYFALL_BASE}/cards/named?${params}`;

  for (let attempt = 1; attempt <= 4; attempt++) {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, "Accept": "application/json" },
    });

    if (res.status === 429) {
      const retryAfterSec = parseInt(res.headers.get("Retry-After") || "60", 10);
      console.log(`\n  [rate-limit] Waiting ${retryAfterSec}s then retrying (attempt ${attempt}/3)...`);
      await sleep(retryAfterSec * 1000);
      continue;
    }

    const json = await res.json();
    if (!res.ok) throw new Error(json.details || json.code || `HTTP ${res.status}`);

    // Room cards: keep both faces intact — buildRoomTxt() handles them
    if (isRoomCard(json)) return json;

    // For double-faced / adventure cards use the front face data
    if (json.card_faces && !json.oracle_text) {
      const front = json.card_faces[0];
      json.oracle_text  = front.oracle_text;
      json.mana_cost    = json.mana_cost || front.mana_cost;
      json.power        = front.power;
      json.toughness    = front.toughness;
      json.type_line    = front.type_line;
      json.flavor_text  = front.flavor_text;
      // Art URL: prefer face-level image_uris, fall back to card-level
      if (!json.image_uris && front.image_uris) json.image_uris = front.image_uris;
    }
    return json;
  }
  throw new Error("Rate-limited by Scryfall after 3 retries. Try again later.");
}

// ── Art download ──────────────────────────────────────────────────────────────

function getArtInfo(card, artVersion) {
  const imageUris = card.image_uris;
  if (!imageUris) return null;

  const url = imageUris[artVersion];
  if (!url) return null;

  return {
    version: artVersion,
    url,
    extension: artVersion === "png" ? ".png" : ".jpg",
  };
}

async function downloadArt(card, artDir, artVersion, fileBase, extension) {
  const artInfo = getArtInfo(card, artVersion);
  if (!artInfo) return null;

  const artPath = path.join(artDir, `${fileBase}${extension}`);
  const res = await fetch(artInfo.url, {
    headers: { "User-Agent": USER_AGENT, "Accept": "image/*" },
  });
  if (!res.ok) throw new Error(`Art HTTP ${res.status}`);

  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(artPath, buf);
  return artPath;
}

// ── CLI ───────────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const opts = { names: [], output: ".", artOutput: null, set: null, artVersion: "art_crop", dryRun: false, overwrite: false, art: true, flavor: true };
  for (let i = 0; i < argv.length; i++) {
    const arg  = argv[i];
    const next = argv[i + 1];
    if      (arg === "--output"     && next) { opts.output    = next;  i++; }
    else if (arg === "--art-output" && next) { opts.artOutput = next;  i++; }
    else if (arg === "--set"        && next) { opts.set       = next;  i++; }
    else if (arg === "--art-version"&& next) { opts.artVersion = next.toLowerCase(); i++; }
    else if (arg === "--dry-run")            { opts.dryRun    = true;       }
    else if (arg === "--overwrite")          { opts.overwrite = true;       }
    else if (arg === "--no-art")             { opts.art       = false;      }
    else if (arg === "--no-flavor")          { opts.flavor    = false;      }
    else if (!arg.startsWith("--"))          { opts.names.push(arg);        }
  }
  if (!ART_VERSIONS.includes(opts.artVersion)) {
    throw new Error(`Invalid --art-version '${opts.artVersion}'. Expected one of: ${ART_VERSIONS.join(", ")}`);
  }
  return opts;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.names.length === 0) {
    console.error(
      "Usage: node fetch_card.mjs [options] \"Card Name\" [\"Card Name 2\" ...]\n" +
      "  --output <dir>       Directory to write .txt files (default: current dir)\n" +
      "  --art-output <dir>   Directory to write artwork image files (default: same as --output)\n" +
      "  --set <code>         Prefer a specific set (e.g. m21)\n" +
      "  --art-version <name> Scryfall image variant: art_crop|border_crop|normal|large|png\n" +
      "  --overwrite          Re-create files even if they already exist\n" +
      "  --no-art             Skip downloading the artwork image\n" +
      "  --dry-run            Print the .txt to stdout without writing any files"
    );
    process.exit(1);
  }

  const outDir = path.resolve(opts.output);
  const artDir = path.resolve(opts.artOutput || opts.output);

  if (!opts.dryRun) {
    fs.mkdirSync(outDir, { recursive: true });
    if (artDir !== outDir) fs.mkdirSync(artDir, { recursive: true });
  }

  let ok = 0, skip = 0, fail = 0;

  for (let i = 0; i < opts.names.length; i++) {
    const name = opts.names[i];
    // Respect Scryfall's rate limit
    if (i > 0) await sleep(API_DELAY_MS);

    try {
      // Strip trailing _N suffix (e.g. "Forest_3" → lookup "Forest", save as "Forest_3")
      const copyMatch = name.match(/^(.+)_(\d+)$/);
      const lookupName = copyMatch ? copyMatch[1] : name;

      process.stdout.write(`Fetching "${name}"... `);
      const card = await fetchCard(lookupName, opts.set);

      const txt = isRoomCard(card) ? buildRoomTxt(card) : buildTxt(card, opts.flavor);

      const scryfallBase = getSafeFileBase(card);
      const fileBase = copyMatch ? `${scryfallBase}_${copyMatch[2]}` : scryfallBase;

      if (opts.dryRun) {
        console.log(`\n${"─".repeat(60)}\n${txt}\n`);
        ok++;
        continue;
      }

      const outPath  = path.join(outDir, `${fileBase}.txt`);
      const artInfo  = opts.art ? getArtInfo(card, opts.artVersion) : null;
      const artPath  = artInfo ? path.join(artDir, `${fileBase}${artInfo.extension}`) : null;
      const txtExists = fs.existsSync(outPath);
      const artExists = artPath ? fs.existsSync(artPath) : false;

      const allTargetsExist = opts.art ? (txtExists && artExists) : txtExists;
      if (allTargetsExist && !opts.overwrite) {
        console.log(`SKIP (exists)`);
        skip++;
        continue;
      }

      // Write .txt
      if (!txtExists || opts.overwrite) {
        fs.writeFileSync(outPath, txt, "utf8");
      }

      // Download selected Scryfall image variant
      let artNote = "";
      if (opts.art && (!artExists || opts.overwrite)) {
        if (!artInfo) {
          artNote = ` (no '${opts.artVersion}' image available)`;
        } else {
        try {
          await downloadArt(card, artDir, opts.artVersion, fileBase, artInfo.extension);
          artNote = ` + art(${opts.artVersion})`;
        } catch (artErr) {
          artNote = ` (art failed: ${artErr.message})`;
        }
        }
      }

      console.log(`OK → ${fileBase}.txt${artNote}`);
      ok++;
    } catch (err) {
      console.log(`FAIL: ${err.message}`);
      fail++;
    }
  }

  console.log(`\nDone. ${ok} written, ${skip} skipped, ${fail} failed.`);
}

main();
