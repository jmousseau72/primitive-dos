// Live preview: streams SVG fragments into an inline <svg> while the shape
// count is low, and swaps to raster snapshots for very large runs (the
// backend decides; see internal/session/session.go). Also owns the source
// underlay layer and the drawing-mode brush.

import type { BatchPayload, StartedPayload } from "./types";

const preview = document.getElementById("preview") as HTMLDivElement;
const underlay = document.getElementById("underlay") as HTMLImageElement;
const underlayBtn = document.getElementById("btn-underlay") as HTMLButtonElement;
const progress = document.getElementById("progress") as HTMLDivElement;
const progressFill = document.getElementById("progress-fill") as HTMLDivElement;
const statShapes = document.getElementById("stat-shapes") as HTMLSpanElement;
const statScore = document.getElementById("stat-score") as HTMLSpanElement;
const statRate = document.getElementById("stat-rate") as HTMLSpanElement;
const statElapsed = document.getElementById("stat-elapsed") as HTMLSpanElement;

const SVG_NS = "http://www.w3.org/2000/svg";

let liveGroup: SVGGElement | null = null;
let bgRect: SVGRectElement | null = null;
let rasterImg: HTMLImageElement | null = null;
let underlayOn = false;
let outW = 0;
let outH = 0;
let inW = 0;
let inH = 0;

export function resetPreview() {
    preview.innerHTML = "";
    liveGroup = null;
    bgRect = null;
    rasterImg = null;
    progress.classList.remove("indeterminate");
    progressFill.style.width = "0";
    statShapes.textContent = "–";
    statScore.textContent = "";
    statScore.title = "";
    statRate.textContent = "";
    statElapsed.textContent = "";
}

// ---------- underlay ----------

export function setUnderlaySource(dataUrl: string) {
    underlay.src = dataUrl;
}

// The SVG background is opaque, so showing the underlay also means making
// the background transparent. Raster previews have the background baked in,
// so the toggle is unavailable there.
export function setUnderlayVisible(on: boolean) {
    underlayOn = on;
    underlay.classList.toggle("hidden", !on);
    underlayBtn.classList.toggle("active", on);
    if (bgRect) {
        bgRect.setAttribute("fill-opacity", on ? "0" : "1");
    }
}

export function underlayVisible(): boolean {
    return underlayOn;
}

export function underlayAvailable(): boolean {
    return rasterImg === null;
}

// ---------- live document ----------

// Build the same document structure Model.SVG() writes, but with a viewBox so
// it scales to fit the pane.
export function beginPreview(p: StartedPayload) {
    resetPreview();
    outW = p.width;
    outH = p.height;
    inW = p.inputW;
    inH = p.inputH;

    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("viewBox", `0 0 ${p.width} ${p.height}`);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");

    const rect = document.createElementNS(SVG_NS, "rect");
    rect.setAttribute("x", "0");
    rect.setAttribute("y", "0");
    rect.setAttribute("width", String(p.width));
    rect.setAttribute("height", String(p.height));
    rect.setAttribute("fill", p.background);
    svg.appendChild(rect);
    bgRect = rect;

    const g = document.createElementNS(SVG_NS, "g");
    g.setAttribute("transform", `scale(${p.scale}) translate(0.5 0.5)`);
    svg.appendChild(g);

    preview.appendChild(svg);
    liveGroup = g;

    if (p.totalShapes === 0) {
        progress.classList.add("indeterminate");
    }
    setUnderlayVisible(underlayOn); // reapply current toggle to the new doc
}

function showSnapshot(b64: string) {
    if (!rasterImg) {
        preview.innerHTML = "";
        liveGroup = null;
        bgRect = null;
        rasterImg = document.createElement("img");
        rasterImg.alt = "Render preview";
        preview.appendChild(rasterImg);
        // Background is baked into raster frames; the underlay can't show.
        underlay.classList.add("hidden");
        underlayBtn.classList.remove("active");
        underlayBtn.disabled = true;
        underlayBtn.title = "Underlay unavailable in raster preview (very large runs)";
    }
    rasterImg.src = `data:image/jpeg;base64,${b64}`;
}

export function applyBatch(b: BatchPayload) {
    if (b.previewMode === "raster") {
        if (b.snapshotJpeg) showSnapshot(b.snapshotJpeg);
    } else if (b.fragments && b.fragments.length > 0 && liveGroup) {
        // One DOM operation per batch, never per shape.
        liveGroup.insertAdjacentHTML("beforeend", b.fragments.join(""));
    }
    updateStats(b.shapesDone, b.totalShapes, b.score, b.shapesPerSec, b.elapsedMs);
}

export function resetUnderlayButton() {
    underlayBtn.disabled = false;
    underlayBtn.title = "Toggle the source-image underlay";
}

// ---------- stats ----------

export function updateStats(
    done: number,
    total: number,
    score: number,
    rate: number,
    elapsedMs: number,
) {
    if (total > 0) {
        progressFill.style.width = `${Math.min(100, (done / total) * 100)}%`;
        statShapes.textContent = `${done.toLocaleString()} / ${total.toLocaleString()}`;
    } else {
        statShapes.textContent = `${done.toLocaleString()} shapes`;
    }
    if (score > 0) {
        const similarity = Math.max(0, (1 - score) * 100);
        statScore.textContent = `${similarity.toFixed(2)}% similar`;
        statScore.title = `RMSE score ${score.toFixed(5)}`;
    } else {
        statScore.textContent = "";
        statScore.title = "";
    }
    statRate.textContent = rate > 0 ? `${rate >= 10 ? rate.toFixed(0) : rate.toFixed(1)} shapes/s` : "";
    statElapsed.textContent = formatElapsed(elapsedMs);
}

function formatElapsed(ms: number): string {
    const totalSec = Math.floor(ms / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    const pad = (n: number) => String(n).padStart(2, "0");
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

// ---------- drawing-mode brush ----------

// Maps a pointer event to input-image coordinates by reversing the
// object-fit:contain letterboxing of the current preview element.
function pointerToImage(e: PointerEvent): { x: number; y: number } | null {
    const el = (rasterImg ?? preview.querySelector("svg")) as Element | null;
    if (!el || outW === 0 || outH === 0 || inW === 0 || inH === 0) return null;
    const box = el.getBoundingClientRect();
    const boxAspect = box.width / box.height;
    const contentAspect = outW / outH;
    let cw = box.width;
    let ch = box.height;
    let cx = box.left;
    let cy = box.top;
    if (boxAspect > contentAspect) {
        cw = box.height * contentAspect;
        cx += (box.width - cw) / 2;
    } else {
        ch = box.width / contentAspect;
        cy += (box.height - ch) / 2;
    }
    const fx = (e.clientX - cx) / cw;
    const fy = (e.clientY - cy) / ch;
    if (fx < 0 || fx > 1 || fy < 0 || fy > 1) return null;
    return { x: fx * inW, y: fy * inH };
}

export function initBrush(
    enabled: () => boolean,
    onFocus: (x: number, y: number, radius: number, active: boolean) => void,
) {
    let painting = false;
    let lastSent = 0;

    const send = (e: PointerEvent) => {
        const pt = pointerToImage(e);
        if (!pt) return;
        const radius = Math.max(inW, inH) * 0.08;
        onFocus(pt.x, pt.y, radius, true);
    };

    const stop = () => {
        if (!painting) return;
        painting = false;
        onFocus(0, 0, 0, false);
    };

    preview.addEventListener("pointerdown", (e) => {
        if (!enabled()) return;
        painting = true;
        try {
            preview.setPointerCapture(e.pointerId);
        } catch {
            // Synthetic events have no capturable pointer; painting works anyway.
        }
        send(e);
    });

    preview.addEventListener("pointermove", (e) => {
        if (!painting || !enabled()) return;
        const now = performance.now();
        if (now - lastSent < 33) return;
        lastSent = now;
        send(e);
    });

    preview.addEventListener("pointerup", stop);
    preview.addEventListener("pointercancel", stop);

    return { stopBrush: stop };
}

export function setBrushCursor(on: boolean) {
    preview.classList.toggle("brush", on);
}
