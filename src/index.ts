import type { Worker as NodeJSWorker } from "worker_threads";
import type {
  RenderRequestListener,
  RenderResponse,
  RenderOptions,
  GraphvizJSONOutput,
} from "./types";

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
      (this._worker as NodeJSWorker).on("message", (data) =>
        this._eventListener({ data } as MessageEvent)
      );
      (this._worker as NodeJSWorker).on("error", (e) =>
        this._listeners.forEach((listener) => listener(e))
      );
    } else {
      (this._worker as Worker).addEventListener("message", (event) =>
        this._eventListener(event)
      );
    }
  }

  _eventListener(event: MessageEvent): void {
    const { id, error, result } = event.data as RenderResponse;

    this._listeners[id](error, result);
    delete this._listeners[id];

    if (this._isNodeWorker && --this._executing === 0) {
      (this._worker as NodeJSWorker).unref();
    }
  }

  render(src: string, options: RenderOptions): Promise<string> {
    return new Promise((resolve, reject) => {
      const id = this._nextId++;

      if (this._isNodeWorker && this._executing++ === 0) {
        (this._worker as NodeJSWorker).ref();
      }

      this._listeners[id] = function (error, result): void {
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

  terminate(): Promise<number> | void {
    return this._worker.terminate();
  }
}

type VizConstructorOptionsWorkerURL = { workerURL: string };
type VizConstructorOptionsWorker = { worker: Worker | NodeJSWorker };
export type VizConstructorOptions =
  | VizConstructorOptionsWorkerURL
  | VizConstructorOptionsWorker;

class Viz {
  private _wrapper: WorkerWrapper;

  constructor(options = {} as VizConstructorOptions) {
    if (
      typeof (options as VizConstructorOptionsWorkerURL).workerURL !==
      "undefined"
    ) {
      this._wrapper = new WorkerWrapper(
        new Worker((options as VizConstructorOptionsWorkerURL).workerURL, {
          type: "module",
        })
      );
    } else if (
      typeof (options as VizConstructorOptionsWorker).worker !== "undefined"
    ) {
      this._wrapper = new WorkerWrapper(
        (options as VizConstructorOptionsWorker).worker
      );
    } else {
      throw new Error("Must specify workerURL or worker option.");
    }
  }

  /**
   * Renders a DOT graph to the specified format
   * @param src DOT representation of the graph to render.
   * @param options Options for the rendering engine.
   * @returns Raw output of Graphviz as a string.
   */
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
  ): Promise<string> {
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

  /**
   * Renders the graph as a JSON object.
   * @param src DOT representation of the graph to render
   * @param options Options for the rendering engine. `format` is ignored,
   *                unless it is json or json0.
   * @returns Parsed JSON object from Graphviz.
   * @see https://graphviz.gitlab.io/_pages/doc/info/output.html#d:json
   */
  renderJSONObject(
    src: string,
    options = {} as RenderOptions
  ): Promise<GraphvizJSONOutput> {
    let { format } = options;

    if (!format || !format.startsWith("json")) {
      format = "json";
    }

    return this.renderString(src, { ...options, format }).then(JSON.parse);
  }

  /**
   * Terminates the worker, clearing all on-going work.
   */
  terminateWorker(): Promise<number> | void {
    return this._wrapper.terminate();
  }
}

export default Viz;

export { RenderOptions, GraphvizJSONOutput };
