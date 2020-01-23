class WorkerWrapper {
  _listeners = [];
  _nextId = 0;
  _executing = 0;

  constructor(worker) {
    this._worker = worker;
    this._isNodeWorker = "function" === typeof worker.ref;

    if (this._isNodeWorker) {
      this._worker.on("message", data => this._eventListener({ data }));
      this._worker.on("error", console.error);
    } else {
      this._worker.addEventListener("message", this._eventListener);
    }
  }

  _eventListener(event) {
    const { id, error, result } = event.data;

    this._listeners[id](error, result);
    delete this._listeners[id];

    if (this._isNodeWorker && --this._executing === 0) {
      this._worker.unref();
    }
  }

  render(src, options) {
    return new Promise((resolve, reject) => {
      let id = this._nextId++;

      if (this._isNodeWorker && this._executing++ === 0) {
        this._worker.ref();
      }

      this._listeners[id] = function(error, result) {
        if (error) {
          reject(new Error(error.message, error.fileName, error.lineNumber));
          return;
        }
        resolve(result);
      };

      this._worker.postMessage({ id, src, options });
    });
  }
}

class Viz {
  constructor({ workerURL, worker } = {}) {
    if (typeof workerURL !== "undefined") {
      this.wrapper = new WorkerWrapper(new Worker(workerURL));
    } else if (typeof worker !== "undefined") {
      this.wrapper = new WorkerWrapper(worker);
    } else {
      throw new Error("Must specify workerURL or worker option.");
    }
  }

  renderString(
    src,
    {
      format = "svg",
      engine = "dot",
      files = [],
      images = [],
      yInvert = false,
      nop = 0,
    } = {}
  ) {
    if (files.length || images.length) {
      throw new Error("Not implemented");
    }

    return this.wrapper.render(src, {
      format,
      engine,
      files,
      images,
      yInvert,
      nop,
    });
  }

  renderJSONObject(src, options = {}) {
    let { format } = options;

    if (format !== "json" || format !== "json0") {
      format = "json";
    }

    return this.renderString(src, { ...options, format }).then(JSON.parse);
  }
}

export default Viz;
