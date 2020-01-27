const WASM_MODULE_ENTRY = "./render.js";

if ("function" === typeof importScripts) {
  // On webworker
  const { href } = self.location;
  const scriptDirectory = href.substr(0, href.lastIndexOf("/") + 1);
  importScripts(scriptDirectory + WASM_MODULE_ENTRY);
  addEventListener("message", onmessage);
} else if ("function" === typeof require) {
  // On Node.js
  const { parentPort, isMainThread, Worker } = require("worker_threads");
  if (isMainThread) {
    Module = {};
    module.exports = () => new Worker(__filename);
  } else {
    Module = require(WASM_MODULE_ENTRY);
    parentPort.on("message", data => onmessage({ data }));
    function postMessage() {
      return parentPort.postMessage(...arguments);
    }
  }
}

const wasmInitialisation = new Promise(done => {
  Module.onRuntimeInitialized = done;
});

function render(src, options) {
  "use strict";
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

function onmessage(event) {
  "use strict";
  const { id, src, options } = event.data;

  wasmInitialisation
    .then(() => {
      const result = render(src, options);
      postMessage({ id, result });
    })
    .catch(e => {
      const error =
        e instanceof Error
          ? {
              message: e.message,
              fileName: e.fileName,
              lineNumber: e.lineNumber,
            }
          : { message: e.toString() };

      postMessage({ id, error });
    });
}
