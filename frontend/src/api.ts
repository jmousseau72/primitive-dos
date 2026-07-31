// Thin typed wrapper around the Wails-generated bindings. The generated
// model classes carry helper methods that make plain object literals fail
// structural typing, so calls cast through `any` and results are typed by
// the interfaces in types.ts (which mirror the Go structs exactly).

import * as App from "../wailsjs/go/main/App";
import type { ExportOptions, InputInfo, Params, Preset } from "./types";

export const selectInputFile = (): Promise<string> => App.SelectInputFile();

export const selectOutputDir = (defaultDir: string): Promise<string> =>
    App.SelectOutputDir(defaultDir);

export const inspectInput = (path: string): Promise<InputInfo> =>
    App.InspectInput(path) as Promise<InputInfo>;

export const startRender = (p: Params): Promise<string> =>
    App.StartRender(p as any);

export const pauseRender = (id: string): Promise<void> => App.PauseRender(id);

export const resumeRender = (id: string): Promise<void> => App.ResumeRender(id);

export const cancelRender = (id: string): Promise<void> => App.CancelRender(id);

export const exportRender = (id: string, opts: ExportOptions): Promise<string[]> =>
    App.ExportRender(id, opts as any);

export const defaultExportName = (id: string): Promise<string> =>
    App.DefaultExportName(id);

export const listPresets = (): Promise<Preset[]> =>
    App.ListPresets() as Promise<Preset[]>;

export const savePreset = (p: Preset): Promise<void> => App.SavePreset(p as any);

export const deletePreset = (name: string): Promise<void> => App.DeletePreset(name);

export const revealInFinder = (path: string): Promise<void> => App.RevealInFinder(path);
