const WASM_MODULE_ENTRY = "./render.js";

let parentPort = {};

if ("function" === typeof importScripts) {
  importScripts(WASM_MODULE_ENTRY);
} else if ("function" === typeof require) {
  const { parentPort: pt, isMainThread, Worker } = require("worker_threads");
  if (isMainThread) {
    module.exports = () => new Worker(__filename);
    return;
  }
  Module = require(WASM_MODULE_ENTRY);
  parentPort = pt;
}

if ("function" === typeof parentPort.postMessage) {
  // Polyfill for Node.js
  function postMessage() {
    return parentPort.postMessage(...arguments);
  }
}

function render(src, options) {
  // var i;
  // for (i = 0; i < options.files.length; i++) {
  //   instance['ccall']('vizCreateFile', 'number', ['string', 'string'], [options.files[i].path, options.files[i].data]);
  // }

  Module.vizSetY_invert(options.yInvert ? 1 : 0);
  Module.vizSetNop(options.nop || 0);

  var resultString = Module.vizRenderFromString(
    src,
    options.format,
    options.engine
  );

  var errorMessageString = Module.vizLastErrorMessage();

  if (errorMessageString !== "") {
    throw new Error(errorMessageString);
  }

  return resultString;
}

Module.onRuntimeInitialized = _ => {
  onmessage = function(event) {
    const { id, src, options } = event.data;

    try {
      var result = render(src, options);
      postMessage({ id, result });
    } catch (e) {
      var error;
      if (e instanceof Error) {
        error = {
          message: e.message,
          fileName: e.fileName,
          lineNumber: e.lineNumber,
        };
      } else {
        error = { message: e.toString() };
      }
      postMessage({ id, error });
    }
  };
  if ("function" === typeof parentPort.on) {
    parentPort.on("message", data => onmessage({ data }));
  }
};
