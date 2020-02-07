import type {
  RenderOptions,
  SerializedError,
  RenderResponse,
  RenderRequest,
} from "./types";

import initializeWasm, {
  WebAssemblyModule,
  EMCCModuleOverrides,
} from "./render";

// Emscripten "magic" globals
declare var ENVIRONMENT_IS_WORKER: boolean;
declare var ENVIRONMENT_IS_NODE: boolean;

// Worker global functions
declare var postMessage: (data: RenderResponse) => void;
declare var addEventListener: (type: "message", data: EventListener) => void;

// @ts-ignore
let exports: any;

let asyncModuleOverrides: Promise<EMCCModuleOverrides>;
let Module: WebAssemblyModule;
async function getModule() {
  if (Module === undefined) {
    Module = await asyncModuleOverrides.then(initializeWasm);
  }
  return Module;
}

if (ENVIRONMENT_IS_WORKER) {
  let resolveModuleOverrides;
  asyncModuleOverrides = new Promise(done => {
    resolveModuleOverrides = done;
  });
  exports = (moduleOverrides: EMCCModuleOverrides) => {
    if (resolveModuleOverrides) {
      resolveModuleOverrides(moduleOverrides);
    } else {
      Promise.resolve().then(() => exports(moduleOverrides));
    }
  };
  addEventListener("message", onmessage);
} else if (ENVIRONMENT_IS_NODE) {
  const { parentPort, isMainThread, Worker } = require("worker_threads");
  if (isMainThread) {
    asyncModuleOverrides = {
      then() {
        return Promise.reject(
          new Error("Main thread initialization is not supported.")
        );
      },
    } as Promise<never>;
    exports = () => new Worker(__filename);
  } else {
    // On Node.js, EMCC doesn't use `locateFile` method to find the WASM file
    asyncModuleOverrides = Promise.resolve({} as EMCCModuleOverrides);

    parentPort.on("message", (data: RenderResponse) =>
      onmessage({ data } as MessageEvent)
    );
    postMessage = function() {
      "use strict";
      return parentPort.postMessage.apply(parentPort, arguments);
    };
  }
}

function render(
  Module: WebAssemblyModule,
  src: string,
  options: RenderOptions
) {
  "use strict";

  for (const { path, data } of options.files) {
    Module.vizCreateFile(path, data);
  }

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

function onmessage(event: MessageEvent) {
  "use strict";
  const { id, src, options } = event.data as RenderRequest;

  getModule()
    .then(Module => {
      const result = render(Module, src, options);
      postMessage({ id, result });
    })
    .catch(e => {
      const error: SerializedError =
        e instanceof Error
          ? {
              message: e.message,
              fileName: (e as any).fileName,
              lineNumber: (e as any).lineNumber,
            }
          : { message: e.toString() };

      postMessage({ id, error });
    });
}

export default exports;
