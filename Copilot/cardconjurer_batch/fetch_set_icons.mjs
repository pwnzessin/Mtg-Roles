/**
 * fetch_set_icons.mjs — Download set code icons from Scryfall and generate
 *                        rarity-colored variants for use in CardConjurer.
 *
 * Scryfall only provides the base SVG (black fill). This script downloads it
 * and produces rarity-colored copies by recoloring the SVG fill:
 *   C (common):   #868686  gray/silver
 *   U (uncommon): #8DBDD8  silver-blue
 *   R (rare):     #D2A827  gold
 *   M (mythic):   #E05C13  orange-red
 *
 * Output filenames match CardConjurer's expected convention:
 *   {CODE}-c.svg, {CODE}-u.svg, {CODE}-r.svg, {CODE}-m.svg
 *
 * Usage:
 *   node fetch_set_icons.mjs --output Artworks/SetIcons --sets "m21,soi,tsr"
 *   node fetch_set_icons.mjs --output Artworks/SetIcons --sets "m21,soi" --rarities "c,u,r,m"
 *   node fetch_set_icons.mjs --output Artworks/SetIcons --all --rarities "r,m"
 *   node fetch_set_icons.mjs --install-missing --cardconjurer-dir path/to/cardconjurer-master
 *
 * Options:
 *   --output <dir>           Directory to write SVG files (default: current dir)
 *   --sets <codes>           Comma-separated set codes (e.g., "m21,soi,ltr")
 *   --rarities <list>        Rarity letters to generate (c,u,r,m; default: all)
 *   --all                    Download all available sets (WARNING: many files)
 *   --install-missing        Download & colorize missing symbols into CardConjurer directly
 *   --cardconjurer-dir <dir> Path to cardconjurer-master root (for --install-missing)
 *   --dry-run                Print what would be done without writing any files
 */

import fs from "node:fs";
import path from "node:path";

const SCRYFALL_BASE = "https://api.scryfall.com";
const USER_AGENT    = "MtgRolesCardGen/1.0";
const API_DELAY_MS  = 100; // 10 req/s — safely under Scryfall's 10 req/s limit

// Standard MTG rarity fill colors
const RARITY_COLORS = {
  c: "#868686", // Common   — silver/gray
  u: "#8DBDD8", // Uncommon — silver-blue
  r: "#D2A827", // Rare     — gold
  m: "#E05C13", // Mythic   — orange-red
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── SVG recoloring ────────────────────────────────────────────────────────────

/**
 * Given SVG text (from Scryfall, typically black-filled), replace the fill
 * color throughout to produce a rarity-colored variant.
 */
function recolorSvg(svgText, rarityLetter) {
  const color = RARITY_COLORS[rarityLetter.toLowerCase()];
  if (!color) throw new Error(`Unknown rarity: ${rarityLetter}`);

  // Replace fill="#000", fill="#000000", fill="black" and fill-rule-adjacent fills
  return svgText
    .replace(/fill="#000000"/gi, `fill="${color}"`)
    .replace(/fill="#000"/gi, `fill="${color}"`)
    .replace(/fill="black"/gi, `fill="${color}"`)
    // Also handle fill in style attributes: style="fill:#000"
    .replace(/fill:\s*#000000/gi, `fill:${color}`)
    .replace(/fill:\s*#000\b/gi, `fill:${color}`)
    .replace(/fill:\s*black/gi, `fill:${color}`);
}

// ── Fetch a single set's icon ──────────────────────────────────────────────────

async function fetchSetIcon(setCode) {
  const url = `${SCRYFALL_BASE}/sets/${setCode.toLowerCase()}`;

  try {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, "Accept": "application/json" },
    });

    if (res.status === 404) {
      return null; // Set not found
    }

    if (!res.ok) {
      const json = await res.json();
      throw new Error(json.details || json.code || `HTTP ${res.status}`);
    }

    const json = await res.json();
    if (!json.icon_svg_uri) return null;

    return {
      code: json.code,
      name: json.name,
      icon_svg_uri: json.icon_svg_uri,
    };
  } catch (err) {
    throw new Error(`Failed to fetch set ${setCode}: ${err.message}`);
  }
}

// ── Download base SVG text ───────────────────────────────────────────────────

async function downloadBaseSvg(iconSvgUri) {
  const res = await fetch(iconSvgUri, {
    headers: { "User-Agent": USER_AGENT, "Accept": "image/svg+xml" },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return await res.text();
}

/**
 * Download one set's base SVG and write rarity-colored variants.
 * Returns the number of files written.
 */
async function processSetIcon(setData, outputDir, rarities, dryRun) {
  if (dryRun) {
    console.log(`  Base URL: ${setData.icon_svg_uri}`);
    for (const r of rarities) {
      console.log(`    ${r} (${RARITY_COLORS[r]}): ${setData.code.toUpperCase()}-${r}.svg`);
    }
    return rarities.length;
  }

  const baseSvg = await downloadBaseSvg(setData.icon_svg_uri);
  let written = 0;

  for (const r of rarities) {
    const colored = recolorSvg(baseSvg, r);
    const filename = `${setData.code.toUpperCase()}-${r}.svg`;
    fs.writeFileSync(path.join(outputDir, filename), colored, "utf8");
    written++;
  }

  return written;
}

// ── Fetch all sets (paginated) ────────────────────────────────────────────────

async function fetchAllSets() {
  const sets = [];
  let page = 1;
  let hasMore = true;

  while (hasMore) {
    const url = `${SCRYFALL_BASE}/sets?page=${page}`;
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, "Accept": "application/json" },
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch sets page ${page}: HTTP ${res.status}`);
    }

    const json = await res.json();
    if (json.data && json.data.length > 0) {
      sets.push(...json.data);
    }

    hasMore = json.has_more || false;
    page++;
    if (hasMore) await sleep(API_DELAY_MS);
  }

  return sets;
}

// ── CLI ───────────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const opts = {
    output: ".",
    sets: [],
    rarities: ["c", "u", "r", "m"], // default: all rarities
    all: false,
    installMissing: false,
    cardconjurerDir: null,
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === "--output" && next) {
      opts.output = next;
      i++;
    } else if (arg === "--sets" && next) {
      opts.sets = next.split(",").map((s) => s.trim()).filter((s) => s);
      i++;
    } else if (arg === "--rarities" && next) {
      opts.rarities = next.split(",").map((r) => r.trim().toLowerCase()).filter((r) => r);
      i++;
    } else if (arg === "--all") {
      opts.all = true;
    } else if (arg === "--install-missing") {
      opts.installMissing = true;
    } else if (arg === "--cardconjurer-dir" && next) {
      opts.cardconjurerDir = next;
      i++;
    } else if (arg === "--dry-run") {
      opts.dryRun = true;
    }
  }

  return opts;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  // --install-missing mode: auto-detect CardConjurer dir and fill in missing symbols
  if (opts.installMissing) {
    const ccDir = opts.cardconjurerDir
      ? path.resolve(opts.cardconjurerDir)
      : path.resolve("../../cardconjurer-master/cardconjurer-master");
    const symbolDir = path.join(ccDir, "img", "setSymbols", "official");

    if (!fs.existsSync(symbolDir)) {
      console.error(`[error] CardConjurer symbol dir not found: ${symbolDir}`);
      console.error(`  Use --cardconjurer-dir to specify the correct path.`);
      process.exit(1);
    }

    console.log(`CardConjurer symbol dir: ${symbolDir}`);
    console.log("Fetching all sets from Scryfall to find missing symbols...");
    const allSets = await fetchAllSets();

    const missing = [];
    for (const set of allSets) {
      // Check if any rarity variant is missing
      const anyMissing = opts.rarities.some(
        (r) => !fs.existsSync(path.join(symbolDir, `${set.code.toUpperCase()}-${r}.svg`))
      );
      if (anyMissing) missing.push(set);
    }

    console.log(`Found ${missing.length} sets with missing rarity symbols (out of ${allSets.length} total).`);
    if (missing.length === 0) {
      console.log("Nothing to do.");
      return;
    }

    if (!opts.dryRun) fs.mkdirSync(symbolDir, { recursive: true });

    let ok = 0, skip = 0, fail = 0;
    for (let i = 0; i < missing.length; i++) {
      const set = missing[i];
      if (i > 0) await sleep(API_DELAY_MS);
      process.stdout.write(`Installing "${set.code}" (${set.name})... `);
      try {
        // Only write the rarity files that are actually missing
        const raritiesNeeded = opts.rarities.filter(
          (r) => !fs.existsSync(path.join(symbolDir, `${set.code.toUpperCase()}-${r}.svg`))
        );
        await processSetIcon(
          { code: set.code, name: set.name, icon_svg_uri: set.icon_svg_uri },
          symbolDir,
          raritiesNeeded,
          opts.dryRun
        );
        console.log(`✓ (${raritiesNeeded.join("/")})`);
        ok++;
      } catch (err) {
        console.log(`✗ ${err.message}`);
        fail++;
      }
    }
    console.log(`\nSummary: ${ok} sets installed, ${skip} skipped, ${fail} failed.`);
    process.exit(fail > 0 ? 1 : 0);
    return;
  }

  if (!opts.all && opts.sets.length === 0) {
    console.error(
      "Usage: node fetch_set_icons.mjs [options]\n" +
      "  --output <dir>              Directory to write SVG files (default: current dir)\n" +
      "  --sets <codes>              Comma-separated set codes (e.g., 'm21,soi,ltr')\n" +
      "  --rarities <list>           Rarity letters to generate (c,u,r,m; default: all)\n" +
      "  --all                       Download all available sets\n" +
      "  --install-missing           Fill in missing symbols in CardConjurer directly\n" +
      "  --cardconjurer-dir <dir>    Path to cardconjurer-master root\n" +
      "  --dry-run                   Show what would happen without writing files\n\n" +
      "Rarity colors applied locally (no rarity-specific URLs required):\n" +
      "  c=common #868686  u=uncommon #8DBDD8  r=rare #D2A827  m=mythic #E05C13"
    );
    process.exit(1);
  }

  const outDir = path.resolve(opts.output);

  if (!opts.dryRun) {
    fs.mkdirSync(outDir, { recursive: true });
  }

  let setCodesToFetch = opts.sets;

  if (opts.all) {
    console.log("Fetching all available sets from Scryfall...");
    const allSets = await fetchAllSets();
    setCodesToFetch = allSets.map((s) => s.code);
    console.log(`Found ${setCodesToFetch.length} sets.`);
  }

  let ok = 0, skip = 0, fail = 0;

  for (let i = 0; i < setCodesToFetch.length; i++) {
    const code = setCodesToFetch[i];
    if (i > 0) await sleep(API_DELAY_MS);

    try {
      process.stdout.write(`Fetching set "${code}"... `);
      const setData = await fetchSetIcon(code);

      if (!setData) {
        console.log("not found (skipped)");
        skip++;
        continue;
      }

      await processSetIcon(setData, outDir, opts.rarities, opts.dryRun);
      if (!opts.dryRun) {
        console.log(`✓ (${setData.name} — ${opts.rarities.join("/")})`);
      }
      ok++;
    } catch (err) {
      console.log(`✗ ${err.message}`);
      fail++;
    }
  }

  console.log(`\nSummary: ${ok} downloaded, ${skip} skipped, ${fail} failed.`);
  process.exit(fail > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(`\n[fatal] ${err.message}`);
  process.exit(1);
});
