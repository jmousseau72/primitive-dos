// Live preview: streams SVG fragments into an inline <svg> while the shape
// count is low, and swaps to raster snapshots for very large runs (the
// backend decides; see internal/session/session.go).

import type { BatchPayload, StartedPayload } from "./types";

const preview = document.getElementById("preview") as HTMLDivElement;
const progressFill = document.getElementById("progress-fill") as HTMLDivElement;
const statShapes = document.getElementById("stat-shapes") as HTMLSpanElement;
const statScore = document.getElementById("stat-score") as HTMLSpanElement;
const statRate = document.getElementById("stat-rate") as HTMLSpanElement;
const statElapsed = document.getElementById("stat-elapsed") as HTMLSpanElement;

const SVG_NS = "http://www.w3.org/2000/svg";

let liveGroup: SVGGElement | null = null;
let rasterImg: HTMLImageElement | null = null;

export function resetPreview() {
    preview.innerHTML = "";
    liveGroup = null;
    rasterImg = null;
    progressFill.style.width = "0";
    statShapes.textContent = "–";
    statScore.textContent = "";
    statRate.textContent = "";
    statElapsed.textContent = "";
}

// Build the same document structure Model.SVG() writes, but with a viewBox so
// it scales to fit the pane.
export function beginPreview(p: StartedPayload) {
    resetPreview();
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

    const g = document.createElementNS(SVG_NS, "g");
    g.setAttribute("transform", `scale(${p.scale}) translate(0.5 0.5)`);
    svg.appendChild(g);

    preview.appendChild(svg);
    liveGroup = g;
}

function showSnapshot(b64: string) {
    if (!rasterImg) {
        preview.innerHTML = "";
        liveGroup = null;
        rasterImg = document.createElement("img");
        rasterImg.alt = "Render preview";
        preview.appendChild(rasterImg);
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

export function updateStats(
    done: number,
    total: number,
    score: number,
    rate: number,
    elapsedMs: number,
) {
    progressFill.style.width = total > 0 ? `${Math.min(100, (done / total) * 100)}%` : "0";
    statShapes.textContent = `${done.toLocaleString()} / ${total.toLocaleString()}`;
    statScore.textContent = score > 0 ? `score ${score.toFixed(5)}` : "";
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
