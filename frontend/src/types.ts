// Mirrors internal/session/events.go and session.go — keep in sync.

export interface Stage {
    count: number;
    mode: number;
    alpha: number;
    repeat: number;
}

export interface AutoSaveOptions {
    dir: string;
    baseName: string;
    formats: string[];
    nth: number;
}

export type RunMode = "count" | "forever" | "score" | "draw";

export interface Params {
    inputPath: string;
    mode: number;
    shapeCount: number;
    alpha: number;
    repeat: number;
    inputResize: number;
    outputSize: number;
    background: string;
    workers: number;
    strokeWidth: number;
    runMode: RunMode;
    targetScore: number;
    autoSave?: AutoSaveOptions;
    stages?: Stage[];
}

export interface Preset {
    name: string;
    builtIn: boolean;
    params: Params;
    exportFormats: string[];
}

export interface InputInfo {
    path: string;
    width: number;
    height: number;
    thumbJpegB64: string;
}

export interface ExportOptions {
    dir: string;
    baseName: string;
    formats: string[];
    jpegQuality: number;
}

export interface StartedPayload {
    sessionId: string;
    width: number;
    height: number;
    scale: number;
    background: string;
    totalShapes: number;
    previewMode: string;
    inputW: number;
    inputH: number;
}

export interface BatchPayload {
    sessionId: string;
    fragments?: string[];
    snapshotJpeg?: string;
    previewMode: string;
    shapesDone: number;
    totalShapes: number;
    score: number;
    elapsedMs: number;
    shapesPerSec: number;
}

export interface StatePayload {
    sessionId: string;
    shapesDone: number;
}

export interface DonePayload {
    sessionId: string;
    cancelled: boolean;
    shapesDone: number;
    score: number;
    elapsedMs: number;
}

export interface ErrorPayload {
    sessionId: string;
    message: string;
}

export interface ExportedPayload {
    sessionId: string;
    paths: string[];
}
