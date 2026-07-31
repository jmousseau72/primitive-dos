export namespace main {
	
	export class InputInfo {
	    path: string;
	    width: number;
	    height: number;
	    thumbJpegB64: string;
	
	    static createFrom(source: any = {}) {
	        return new InputInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.path = source["path"];
	        this.width = source["width"];
	        this.height = source["height"];
	        this.thumbJpegB64 = source["thumbJpegB64"];
	    }
	}

}

export namespace session {
	
	export class AutoSaveOptions {
	    dir: string;
	    baseName: string;
	    formats: string[];
	    nth: number;
	
	    static createFrom(source: any = {}) {
	        return new AutoSaveOptions(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.dir = source["dir"];
	        this.baseName = source["baseName"];
	        this.formats = source["formats"];
	        this.nth = source["nth"];
	    }
	}
	export class GIFOptions {
	    scoreDelta: number;
	    delayCS: number;
	    lastDelayCS: number;
	    maxDim: number;
	
	    static createFrom(source: any = {}) {
	        return new GIFOptions(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.scoreDelta = source["scoreDelta"];
	        this.delayCS = source["delayCS"];
	        this.lastDelayCS = source["lastDelayCS"];
	        this.maxDim = source["maxDim"];
	    }
	}
	export class ExportOptions {
	    dir: string;
	    baseName: string;
	    formats: string[];
	    jpegQuality: number;
	    gif?: GIFOptions;
	
	    static createFrom(source: any = {}) {
	        return new ExportOptions(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.dir = source["dir"];
	        this.baseName = source["baseName"];
	        this.formats = source["formats"];
	        this.jpegQuality = source["jpegQuality"];
	        this.gif = this.convertValues(source["gif"], GIFOptions);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	export class Stage {
	    count: number;
	    mode: number;
	    alpha: number;
	    repeat: number;
	
	    static createFrom(source: any = {}) {
	        return new Stage(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.count = source["count"];
	        this.mode = source["mode"];
	        this.alpha = source["alpha"];
	        this.repeat = source["repeat"];
	    }
	}
	export class Params {
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
	    runMode: string;
	    targetScore: number;
	    autoSave?: AutoSaveOptions;
	    stages?: Stage[];
	
	    static createFrom(source: any = {}) {
	        return new Params(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.inputPath = source["inputPath"];
	        this.mode = source["mode"];
	        this.shapeCount = source["shapeCount"];
	        this.alpha = source["alpha"];
	        this.repeat = source["repeat"];
	        this.inputResize = source["inputResize"];
	        this.outputSize = source["outputSize"];
	        this.background = source["background"];
	        this.workers = source["workers"];
	        this.strokeWidth = source["strokeWidth"];
	        this.runMode = source["runMode"];
	        this.targetScore = source["targetScore"];
	        this.autoSave = this.convertValues(source["autoSave"], AutoSaveOptions);
	        this.stages = this.convertValues(source["stages"], Stage);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Preset {
	    name: string;
	    builtIn: boolean;
	    params: Params;
	    exportFormats: string[];
	
	    static createFrom(source: any = {}) {
	        return new Preset(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.builtIn = source["builtIn"];
	        this.params = this.convertValues(source["params"], Params);
	        this.exportFormats = source["exportFormats"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}

}

