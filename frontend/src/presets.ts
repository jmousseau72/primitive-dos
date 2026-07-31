// Preset dropdown: built-ins from Go plus user presets persisted to
// ~/Library/Application Support/PrimitiveDos/presets.json.

import { deletePreset, listPresets, savePreset } from "./api";
import { applyPreset, gatherParams } from "./controls";
import type { Preset } from "./types";

const select = document.getElementById("preset-select") as HTMLSelectElement;
const saveBtn = document.getElementById("btn-preset-save") as HTMLButtonElement;
const deleteBtn = document.getElementById("btn-preset-delete") as HTMLButtonElement;
const saveRow = document.getElementById("preset-save-row") as HTMLDivElement;
const nameInput = document.getElementById("preset-name") as HTMLInputElement;
const confirmBtn = document.getElementById("btn-preset-confirm") as HTMLButtonElement;

let presets: Preset[] = [];
let notify: (msg: string, isError?: boolean) => void = () => {};
let getExportFormats: () => string[] = () => [];

export async function refreshPresets(selected?: string) {
    try {
        presets = await listPresets();
    } catch (err) {
        notify(String(err), true);
        return;
    }
    select.innerHTML = "";
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "Presets…";
    select.appendChild(placeholder);

    const groups: Array<[string, Preset[]]> = [
        ["Built-in", presets.filter((p) => p.builtIn)],
        ["Custom", presets.filter((p) => !p.builtIn)],
    ];
    for (const [label, list] of groups) {
        if (list.length === 0) continue;
        const group = document.createElement("optgroup");
        group.label = label;
        for (const p of list) {
            const opt = document.createElement("option");
            opt.value = p.name;
            opt.textContent = p.name;
            group.appendChild(opt);
        }
        select.appendChild(group);
    }
    if (selected) select.value = selected;
    updateDeleteState();
}

function updateDeleteState() {
    const current = presets.find((p) => p.name === select.value);
    deleteBtn.disabled = !current || current.builtIn;
}

export function initPresets(
    notifyFn: (msg: string, isError?: boolean) => void,
    exportFormatsFn: () => string[],
) {
    notify = notifyFn;
    getExportFormats = exportFormatsFn;

    select.addEventListener("change", () => {
        const preset = presets.find((p) => p.name === select.value);
        if (preset) {
            applyPreset(preset);
            notify(`Applied “${preset.name}”`);
        }
        updateDeleteState();
    });

    saveBtn.addEventListener("click", () => {
        saveRow.classList.toggle("hidden");
        if (!saveRow.classList.contains("hidden")) nameInput.focus();
    });

    confirmBtn.addEventListener("click", saveCurrent);
    nameInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter") void saveCurrent();
    });

    deleteBtn.addEventListener("click", async () => {
        const name = select.value;
        if (!name) return;
        try {
            await deletePreset(name);
            await refreshPresets();
            notify(`Deleted “${name}”`);
        } catch (err) {
            notify(String(err), true);
        }
    });

    void refreshPresets();
}

async function saveCurrent() {
    const name = nameInput.value.trim();
    if (!name) return;
    const params = gatherParams("");
    delete params.autoSave; // checkpoint folder is machine-specific, not preset-worthy
    const preset: Preset = {
        name,
        builtIn: false,
        params,
        exportFormats: getExportFormats(),
    };
    try {
        await savePreset(preset);
        saveRow.classList.add("hidden");
        nameInput.value = "";
        await refreshPresets(name);
        notify(`Saved “${name}”`);
    } catch (err) {
        notify(String(err), true);
    }
}
