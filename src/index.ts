import type { Worker as NodeJSWorker } from "worker_threads";

export type SerializedError = {
  message: string;
  lineNumber?: number;
  fileName?: string;
};
type RenderRequestListener = (error: SerializedError, result?: string) => void;

export type RenderRequest = {
  id: number;
  src: string;
  options: RenderOptions;
};
export type RenderResponse = {
  id: number;
  error?: SerializedError;
  result?: string;
};

class WorkerWrapper {
  private _worker: Worker | NodeJSWorker;
  private _isNodeWorker: boolean;

  private _listeners: RenderRequestListener[] = [];
  private _nextId = 0;
  private _executing = 0;

  constructor(worker: Worker | NodeJSWorker) {
    this._worker = worker;
    this._isNodeWorker = "function" === typeof (worker as NodeJSWorker).ref;

    if (this._isNodeWorker) {
      (this._worker as NodeJSWorker).on("message", data =>
        this._eventListener({ data } as MessageEvent)
      );
      (this._worker as NodeJSWorker).on("error", e =>
        this._listeners.forEach(listener => listener(e))
      );
    } else {
      (this._worker as Worker).addEventListener("message", event =>
        this._eventListener(event)
      );
    }
  }

  _eventListener(event: MessageEvent) {
    const { id, error, result } = event.data as RenderResponse;

    this._listeners[id](error, result);
    delete this._listeners[id];

    if (this._isNodeWorker && --this._executing === 0) {
      (this._worker as NodeJSWorker).unref();
    }
  }

  render(src: string, options: RenderOptions) {
    return new Promise((resolve, reject) => {
      let id = this._nextId++;

      if (this._isNodeWorker && this._executing++ === 0) {
        (this._worker as NodeJSWorker).ref();
      }

      this._listeners[id] = function(error, result) {
        if (error) {
          const e = new Error(error.message);
          if (error.fileName) (e as any).fileName = error.fileName;
          if (error.lineNumber) (e as any).lineNumber = error.lineNumber;
          return reject(e);
        }
        resolve(result);
      };

      this._worker.postMessage({ id, src, options });
    });
  }
}

export type VizConstructorOptions = {
  workerURL?: string;
  worker?: Worker | NodeJSWorker;
};

export type Image = {
  path: string;
  height: string | number;
  width: string | number;
};

export type File = {
  path: string;
  data: string;
};

export type RenderOptions = {
  engine?: "circo" | "dot" | "fdp" | "neato" | "osage" | "twopi";
  format?:
    | "svg"
    | "dot"
    | "xdot"
    | "plain"
    | "plain-ext"
    | "ps"
    | "ps2"
    | "json"
    | "json0";
  yInvert?: boolean;
  images?: Image[];
  files?: File[];
  nop: number;
};

class Viz {
  private _wrapper: WorkerWrapper;

  constructor({ workerURL, worker } = {} as VizConstructorOptions) {
    if (typeof workerURL !== "undefined") {
      this._wrapper = new WorkerWrapper(new Worker(workerURL));
    } else if (typeof worker !== "undefined") {
      this._wrapper = new WorkerWrapper(worker);
    } else {
      throw new Error("Must specify workerURL or worker option.");
    }
  }

  renderString(
    src: string,
    {
      format = "svg",
      engine = "dot",
      files = [],
      images = [],
      yInvert = false,
      nop = 0,
    } = {} as RenderOptions
  ) {
    for (const { path, width, height } of images) {
      files.push({
        path,
        data:
          '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n' +
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n' +
          `<svg width="${width}" height="${height}"></svg>`,
      });
    }

    return this._wrapper.render(src, {
      format,
      engine,
      files,
      yInvert,
      nop,
    });
  }

  renderJSONObject(src: string, options = {} as RenderOptions) {
    let { format } = options;

    if (!format.startsWith("json")) {
      format = "json";
    }

    return this.renderString(src, { ...options, format }).then(JSON.parse);
  }
}

export default Viz;
