import "./style.css";
import { EventsOn } from "../wailsjs/runtime/runtime";
import {
    cancelRender,
    defaultExportName,
    exportRender,
    inspectInput,
    pauseRender,
    resumeRender,
    revealInFinder,
    selectInputFile,
    selectOutputDir,
    startRender,
} from "./api";
import {
    checkpointsEnabled,
    gatherParams,
    getCheckpointDir,
    initControls,
    setCheckpointDir,
    setControlsEnabled,
} from "./controls";
import { initPresets } from "./presets";
import { applyBatch, beginPreview, updateStats } from "./preview";
import type {
    BatchPayload,
    DonePayload,
    ErrorPayload,
    StartedPayload,
} from "./types";

type UIState = "empty" | "loaded" | "running" | "paused" | "done";

const $ = <T extends HTMLElement>(id: string): T =>
    document.getElementById(id) as T;

const dropzone = $("dropzone");
const previewWrap = $("preview-wrap");
const sourceThumb = $<HTMLImageElement>("source-thumb");
const sourceMeta = $("source-meta");
const btnBrowse = $<HTMLButtonElement>("btn-browse");
const btnStart = $<HTMLButtonElement>("btn-start");
const btnPause = $<HTMLButtonElement>("btn-pause");
const btnResume = $<HTMLButtonElement>("btn-resume");
const btnCancel = $<HTMLButtonElement>("btn-cancel");
const btnExport = $<HTMLButtonElement>("btn-export");
const btnCpDir = $<HTMLButtonElement>("btn-cp-dir");
const toast = $("toast");

let state: UIState = "empty";
let inputPath = "";
let sessionId = "";
let sessionStarted = false;
let toastTimer: number | undefined;

function setState(next: UIState) {
    state = next;
    dropzone.classList.toggle("hidden", next !== "empty");
    previewWrap.classList.toggle("hidden", next === "empty");

    btnStart.classList.toggle("hidden", next === "running" || next === "paused");
    btnStart.disabled = next === "empty";
    btnStart.textContent = next === "done" ? "▶ Restart" : "▶ Start";
    btnPause.classList.toggle("hidden", next !== "running");
    btnResume.classList.toggle("hidden", next !== "paused");
    btnCancel.classList.toggle("hidden", next !== "running" && next !== "paused");

    // Export works mid-run: the backend locks the model between steps.
    btnExport.disabled = !(sessionStarted && (next === "running" || next === "paused" || next === "done"));

    setControlsEnabled(next !== "running" && next !== "paused");
}

function showToast(message: string, isError = false, actions?: Array<[string, () => void]>) {
    toast.innerHTML = "";
    toast.classList.toggle("error", isError);
    const span = document.createElement("span");
    span.textContent = message;
    toast.appendChild(span);
    for (const [label, fn] of actions ?? []) {
        const btn = document.createElement("button");
        btn.textContent = label;
        btn.addEventListener("click", () => {
            fn();
            hideToast();
        });
        toast.appendChild(btn);
    }
    toast.classList.remove("hidden");
    if (toastTimer) window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(hideToast, isError ? 8000 : 4000);
}

function hideToast() {
    toast.classList.add("hidden");
}

async function loadImage(path: string) {
    if (state === "running" || state === "paused") {
        showToast("Stop the current render before loading a new image", true);
        return;
    }
    try {
        const info = await inspectInput(path);
        inputPath = info.path;
        sourceThumb.src = `data:image/jpeg;base64,${info.thumbJpegB64}`;
        sourceMeta.textContent = `${info.width} × ${info.height}`;
        sessionStarted = false;
        sessionId = "";
        setState("loaded");
        beginBlankPreview();
    } catch (err) {
        showToast(String(err), true);
    }
}

function beginBlankPreview() {
    // Show the source image dimmed as a placeholder until a render starts.
    const preview = $("preview");
    preview.innerHTML = "";
    const img = document.createElement("img");
    img.src = sourceThumb.src;
    img.style.opacity = "0.25";
    img.style.filter = "grayscale(0.6)";
    preview.appendChild(img);
    updateStats(0, 0, 0, 0, 0);
}

async function browse() {
    try {
        const path = await selectInputFile();
        if (path) await loadImage(path);
    } catch (err) {
        showToast(String(err), true);
    }
}

async function start() {
    if (!inputPath) return;
    if (checkpointsEnabled() && !getCheckpointDir()) {
        const dir = await selectOutputDir("");
        if (!dir) {
            showToast("Checkpoints are enabled but no folder is chosen", true);
            return;
        }
        setCheckpointDir(dir);
    }
    try {
        const params = gatherParams(inputPath);
        sessionStarted = false;
        sessionId = await startRender(params);
        setState("running");
    } catch (err) {
        showToast(String(err), true);
    }
}

function exportFormats(): string[] {
    const formats: string[] = [];
    for (const box of Array.from(
        document.querySelectorAll<HTMLInputElement>("#exportbar input[data-fmt]"),
    )) {
        if (box.checked && box.dataset.fmt) formats.push(box.dataset.fmt);
    }
    return formats;
}

async function doExport() {
    if (!sessionId || !sessionStarted) return;
    const formats = exportFormats();
    if (formats.length === 0) {
        showToast("Pick at least one export format", true);
        return;
    }
    try {
        const dir = await selectOutputDir("");
        if (!dir) return;
        btnExport.disabled = true;
        const wantsGif = formats.includes("gif");
        showToast(wantsGif ? "Exporting… (GIF encoding can take a while)" : "Exporting…");
        const baseName = await defaultExportName(sessionId);
        const paths = await exportRender(sessionId, {
            dir,
            baseName,
            formats,
            jpegQuality: 95,
        });
        showToast(`Exported ${paths.length} file${paths.length === 1 ? "" : "s"}`, false, [
            ["Reveal in Finder", () => void revealInFinder(paths[0])],
        ]);
    } catch (err) {
        showToast(String(err), true);
    } finally {
        btnExport.disabled = !(sessionStarted && state !== "empty" && state !== "loaded");
    }
}

function wireEvents() {
    EventsOn("session:started", (p: StartedPayload) => {
        if (p.sessionId !== sessionId) return;
        sessionStarted = true;
        beginPreview(p);
        setState("running");
    });

    EventsOn("session:batch", (p: BatchPayload) => {
        if (p.sessionId !== sessionId) return;
        applyBatch(p);
    });

    EventsOn("session:paused", () => setState("paused"));
    EventsOn("session:resumed", () => setState("running"));

    EventsOn("session:done", (p: DonePayload) => {
        if (p.sessionId !== sessionId) return;
        setState("done");
        showToast(
            p.cancelled
                ? `Stopped at ${p.shapesDone.toLocaleString()} shapes — you can still export`
                : `Finished ${p.shapesDone.toLocaleString()} shapes`,
        );
    });

    EventsOn("session:error", (p: ErrorPayload) => {
        showToast(p.message, true);
        if (p.sessionId === sessionId && !sessionStarted) {
            // Failed before the model was built (e.g. unreadable image).
            setState(inputPath ? "loaded" : "empty");
        }
    });

    EventsOn("file:dropped", (p: { path?: string }) => {
        if (p?.path) void loadImage(p.path);
    });

    EventsOn("menu:open", () => void browse());
    EventsOn("menu:export", () => void doExport());
}

function wireDom() {
    btnBrowse.addEventListener("click", () => void browse());
    btnStart.addEventListener("click", () => void start());
    btnPause.addEventListener("click", () => void pauseRender(sessionId));
    btnResume.addEventListener("click", () => void resumeRender(sessionId));
    btnCancel.addEventListener("click", () => void cancelRender(sessionId));
    btnExport.addEventListener("click", () => void doExport());
    btnCpDir.addEventListener("click", async () => {
        const dir = await selectOutputDir(getCheckpointDir());
        if (dir) setCheckpointDir(dir);
    });

    // Visual affordance for HTML5 drag-over (native drop is handled by Wails).
    for (const evt of ["dragenter", "dragover"]) {
        dropzone.addEventListener(evt, (e) => {
            e.preventDefault();
            dropzone.classList.add("drag-over");
        });
    }
    for (const evt of ["dragleave", "drop"]) {
        dropzone.addEventListener(evt, (e) => {
            e.preventDefault();
            dropzone.classList.remove("drag-over");
        });
    }
}

initControls();
initPresets(showToast, exportFormats);
wireDom();
wireEvents();
setState("empty");
