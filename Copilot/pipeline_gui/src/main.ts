import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

type TabId = "generic" | "rolecard";

type PipelineConfig = {
  path: string;
  text: string;
};

const app = document.querySelector<HTMLDivElement>("#app");
if (!app) throw new Error("Missing #app");

app.innerHTML = `
  <div class="shell">
    <header class="topbar">
      <h1>MTG Pipeline Control</h1>
      <p>Edit config and launch scripts from one place.</p>
    </header>

    <nav class="tabs">
      <button data-tab="generic" class="tab active">Generic Pipeline</button>
      <button data-tab="rolecard" class="tab">Rolecard Pipeline</button>
    </nav>

    <section id="generic" class="panel active">
      <div class="row">
        <label>Config file path</label>
        <input id="generic-config-path" value="C:/Users/hecke/Desktop/Mtg-Roles/Copilot/cardconjurer_batch/generic_card_config.json" />
      </div>
      <div class="row buttons">
        <button id="generic-load">Load config</button>
        <button id="generic-save">Save config</button>
        <button id="generic-run">Run generic pipeline</button>
      </div>
      <textarea id="generic-text" spellcheck="false"></textarea>
    </section>

    <section id="rolecard" class="panel">
      <div class="row">
        <label>Config file path</label>
        <input id="rolecard-config-path" value="C:/Users/hecke/Desktop/Mtg-Roles/Copilot/cardconjurer_batch/Rolecard_Batch_Generator.config.json" />
      </div>
      <div class="row buttons">
        <button id="rolecard-load">Load config</button>
        <button id="rolecard-save">Save config</button>
        <button id="rolecard-run">Run rolecard pipeline</button>
      </div>
      <textarea id="rolecard-text" spellcheck="false"></textarea>
    </section>

    <section class="logs">
      <h2>Status</h2>
      <pre id="status"></pre>
    </section>
  </div>
`;

const statusEl = document.querySelector<HTMLPreElement>("#status")!;

function log(msg: string) {
  const ts = new Date().toLocaleTimeString();
  statusEl.textContent = `[${ts}] ${msg}\n${statusEl.textContent}`;
}

function setTab(tab: TabId) {
  document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
  document.querySelectorAll(".panel").forEach((p) => p.classList.remove("active"));
  document.querySelector(`.tab[data-tab='${tab}']`)?.classList.add("active");
  document.getElementById(tab)?.classList.add("active");
}

document.querySelectorAll<HTMLButtonElement>(".tab").forEach((btn) => {
  btn.addEventListener("click", () => setTab(btn.dataset.tab as TabId));
});

async function loadConfig(pathInputId: string, textId: string) {
  const path = (document.getElementById(pathInputId) as HTMLInputElement).value.trim();
  const textEl = document.getElementById(textId) as HTMLTextAreaElement;
  try {
    const text = await invoke<string>("read_file_text", { path });
    textEl.value = text;
    log(`Loaded config: ${path}`);
  } catch (err) {
    log(`Load failed: ${String(err)}`);
  }
}

async function saveConfig(pathInputId: string, textId: string) {
  const path = (document.getElementById(pathInputId) as HTMLInputElement).value.trim();
  const text = (document.getElementById(textId) as HTMLTextAreaElement).value;
  try {
    await invoke("write_file_text", { path, content: text });
    log(`Saved config: ${path}`);
  } catch (err) {
    log(`Save failed: ${String(err)}`);
  }
}

async function runPipeline(scriptPath: string) {
  try {
    log(`Running: ${scriptPath}`);
    const out = await invoke<string>("run_powershell_script", {
      scriptPath,
      args: [],
    });
    log(out || "Script finished.");
  } catch (err) {
    log(`Run failed: ${String(err)}`);
  }
}

document.getElementById("generic-load")!.addEventListener("click", () => loadConfig("generic-config-path", "generic-text"));
document.getElementById("generic-save")!.addEventListener("click", () => saveConfig("generic-config-path", "generic-text"));
document.getElementById("rolecard-load")!.addEventListener("click", () => loadConfig("rolecard-config-path", "rolecard-text"));
document.getElementById("rolecard-save")!.addEventListener("click", () => saveConfig("rolecard-config-path", "rolecard-text"));
document.getElementById("generic-run")!.addEventListener("click", () => runPipeline("C:/Users/hecke/Desktop/Mtg-Roles/Copilot/cardconjurer_batch/generic_card_pipeline.ps1"));
document.getElementById("rolecard-run")!.addEventListener("click", () => runPipeline("C:/Users/hecke/Desktop/Mtg-Roles/Copilot/cardconjurer_batch/Rolecard_Batch_Generator.ps1"));

log("Ready.");
