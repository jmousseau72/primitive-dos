// Right-panel controls: reads/writes a Params object, mirrors the CLI flags.

import type { Params, Preset, Stage } from "./types";

const $ = <T extends HTMLElement>(id: string): T =>
    document.getElementById(id) as T;

const modeGrid = $("mode-grid");
const countNum = $<HTMLInputElement>("count-num");
const countSlider = $<HTMLInputElement>("count-slider");
const alphaAuto = $<HTMLInputElement>("alpha-auto");
const alphaNum = $<HTMLInputElement>("alpha-num");
const alphaSlider = $<HTMLInputElement>("alpha-slider");
const repeatNum = $<HTMLInputElement>("repeat-num");
const inresFull = $<HTMLInputElement>("inres-full");
const inresNum = $<HTMLInputElement>("inres-num");
const outsizeMatch = $<HTMLInputElement>("outsize-match");
const outsizeNum = $<HTMLInputElement>("outsize-num");
const bgAuto = $<HTMLInputElement>("bg-auto");
const bgColor = $<HTMLInputElement>("bg-color");
const workersAll = $<HTMLInputElement>("workers-all");
const workersNum = $<HTMLInputElement>("workers-num");
const cpEnable = $<HTMLInputElement>("cp-enable");
const cpNth = $<HTMLInputElement>("cp-nth");
const cpOptions = $("cp-options");
const cpPng = $<HTMLInputElement>("cp-png");
const cpJpg = $<HTMLInputElement>("cp-jpg");
const cpSvg = $<HTMLInputElement>("cp-svg");
const cpDirLabel = $("cp-dir-label");
const stagesText = $<HTMLTextAreaElement>("stages-text");

let mode = 6;
let checkpointDir = "";

// Log-scale slider mapping for the shape count (10 .. 120,000).
const COUNT_MIN = 10;
const COUNT_MAX = 120000;
const SLIDER_MAX = 1000;

function countToSlider(count: number): number {
    const clamped = Math.min(Math.max(count, COUNT_MIN), COUNT_MAX);
    return Math.round(
        (Math.log(clamped / COUNT_MIN) / Math.log(COUNT_MAX / COUNT_MIN)) * SLIDER_MAX,
    );
}

function sliderToCount(t: number): number {
    const raw = COUNT_MIN * Math.pow(COUNT_MAX / COUNT_MIN, t / SLIDER_MAX);
    // Snap to friendly increments as the magnitude grows.
    const step = raw < 100 ? 10 : raw < 1000 ? 50 : raw < 10000 ? 100 : 1000;
    return Math.round(raw / step) * step;
}

function selectMode(m: number) {
    mode = m;
    for (const btn of Array.from(modeGrid.querySelectorAll("button"))) {
        btn.classList.toggle("selected", Number(btn.dataset.mode) === m);
    }
}

function num(input: HTMLInputElement, fallback: number): number {
    const v = Number(input.value);
    return Number.isFinite(v) && v > 0 ? Math.round(v) : fallback;
}

function parseStages(text: string): Stage[] {
    const stages: Stage[] = [];
    for (const line of text.split("\n")) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        const parts = trimmed.split(",").map((p) => Number(p.trim()));
        if (parts.length < 1 || !Number.isFinite(parts[0]) || parts[0] < 1) continue;
        stages.push({
            count: Math.round(parts[0]),
            mode: Number.isFinite(parts[1]) ? Math.round(parts[1]) : mode,
            alpha: Number.isFinite(parts[2]) ? Math.round(parts[2]) : 128,
            repeat: Number.isFinite(parts[3]) ? Math.round(parts[3]) : 0,
        });
    }
    return stages;
}

export function initControls() {
    for (const btn of Array.from(modeGrid.querySelectorAll("button"))) {
        btn.addEventListener("click", () => selectMode(Number(btn.dataset.mode)));
    }
    selectMode(6);
    countSlider.value = String(countToSlider(Number(countNum.value)));

    countSlider.addEventListener("input", () => {
        countNum.value = String(sliderToCount(Number(countSlider.value)));
    });
    countNum.addEventListener("change", () => {
        countSlider.value = String(countToSlider(num(countNum, 2000)));
    });

    alphaAuto.addEventListener("change", () => {
        alphaNum.disabled = alphaSlider.disabled = alphaAuto.checked;
    });
    alphaSlider.addEventListener("input", () => (alphaNum.value = alphaSlider.value));
    alphaNum.addEventListener("change", () => (alphaSlider.value = alphaNum.value));

    inresFull.addEventListener("change", () => (inresNum.disabled = inresFull.checked));
    outsizeMatch.addEventListener("change", () => (outsizeNum.disabled = outsizeMatch.checked));
    bgAuto.addEventListener("change", () => (bgColor.disabled = bgAuto.checked));
    workersAll.addEventListener("change", () => (workersNum.disabled = workersAll.checked));

    cpEnable.addEventListener("change", () => {
        cpNth.disabled = !cpEnable.checked;
        cpOptions.classList.toggle("hidden", !cpEnable.checked);
    });
}

export function setCheckpointDir(dir: string) {
    checkpointDir = dir;
    cpDirLabel.textContent = dir;
}

export function getCheckpointDir(): string {
    return checkpointDir;
}

export function checkpointsEnabled(): boolean {
    return cpEnable.checked;
}

export function gatherParams(inputPath: string): Params {
    const stages = parseStages(stagesText.value);
    const p: Params = {
        inputPath,
        mode,
        shapeCount: num(countNum, 2000),
        alpha: alphaAuto.checked ? 0 : num(alphaNum, 128),
        repeat: Math.max(0, Math.round(Number(repeatNum.value) || 0)),
        inputResize: inresFull.checked ? 0 : num(inresNum, 256),
        outputSize: outsizeMatch.checked ? 0 : num(outsizeNum, 1024),
        background: bgAuto.checked ? "" : bgColor.value,
        workers: workersAll.checked ? 0 : num(workersNum, 1),
    };
    if (stages.length > 0) {
        p.stages = stages;
    }
    if (cpEnable.checked && checkpointDir) {
        const formats: string[] = [];
        if (cpPng.checked) formats.push("png");
        if (cpJpg.checked) formats.push("jpg");
        if (cpSvg.checked) formats.push("svg");
        if (formats.length > 0) {
            p.autoSave = {
                dir: checkpointDir,
                baseName: "",
                formats,
                nth: num(cpNth, 100),
            };
        }
    }
    return p;
}

export function applyPreset(preset: Preset) {
    const p = preset.params;
    selectMode(p.mode);
    countNum.value = String(p.shapeCount);
    countSlider.value = String(countToSlider(p.shapeCount));
    alphaAuto.checked = p.alpha === 0;
    alphaNum.disabled = alphaSlider.disabled = alphaAuto.checked;
    if (p.alpha > 0) {
        alphaNum.value = alphaSlider.value = String(p.alpha);
    }
    repeatNum.value = String(p.repeat || 0);
    inresFull.checked = p.inputResize === 0;
    inresNum.disabled = inresFull.checked;
    if (p.inputResize > 0) inresNum.value = String(p.inputResize);
    outsizeMatch.checked = p.outputSize === 0;
    outsizeNum.disabled = outsizeMatch.checked;
    if (p.outputSize > 0) outsizeNum.value = String(p.outputSize);
    bgAuto.checked = !p.background;
    bgColor.disabled = bgAuto.checked;
    if (p.background) bgColor.value = p.background;
    workersAll.checked = !p.workers;
    workersNum.disabled = workersAll.checked;
    if (p.workers > 0) workersNum.value = String(p.workers);
}

// Disable every control while a render runs (transport buttons stay live).
export function setControlsEnabled(enabled: boolean) {
    const inputs = document.querySelectorAll<HTMLInputElement>(
        "#sidebar input, #sidebar select, #sidebar button, #sidebar textarea",
    );
    for (const el of Array.from(inputs)) {
        el.disabled = !enabled;
    }
    if (enabled) {
        // Restore the dependent-disable states.
        alphaNum.disabled = alphaSlider.disabled = alphaAuto.checked;
        inresNum.disabled = inresFull.checked;
        outsizeNum.disabled = outsizeMatch.checked;
        bgColor.disabled = bgAuto.checked;
        workersNum.disabled = workersAll.checked;
        cpNth.disabled = !cpEnable.checked;
    }
}
