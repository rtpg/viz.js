import type { SerializedError, RenderResponse, RenderRequest } from "./types";
import type { Worker } from "worker_threads";

import initializeWasm, {
  WebAssemblyModule,
  EMCCModuleOverrides,
} from "./render";
import render from "./viz_wrapper.js";

/* eslint-disable no-var */
//
// Emscripten "magic" globals
declare var ENVIRONMENT_IS_WORKER: boolean;
declare var ENVIRONMENT_IS_NODE: boolean;

// Worker global functions
declare var postMessage: (data: RenderResponse) => void;
declare var addEventListener: (type: "message", data: EventListener) => void;
//
/* eslint-enable no-var */

// eslint-disable-next-line @typescript-eslint/ban-ts-ignore
// @ts-ignore: exports must be declared in order to produce valid ES6 code
let exports: (
  moduleOverrides?: EMCCModuleOverrides
) => Promise<EMCCModuleOverrides> | Worker;

let asyncModuleOverrides: Promise<EMCCModuleOverrides>;
let Module: WebAssemblyModule;
async function getModule(): Promise<WebAssemblyModule> {
  if (Module === undefined) {
    Module = await asyncModuleOverrides.then(initializeWasm);
  }
  return Module;
}

export function onmessage(event: MessageEvent): Promise<void> {
  const { id, src, options } = event.data as RenderRequest;

  return getModule()
    .then((Module) => {
      const result = render(Module, src, options);
      postMessage({ id, result });
    })
    .catch((e) => {
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

if (ENVIRONMENT_IS_WORKER) {
  let resolveModuleOverrides: Function;
  asyncModuleOverrides = new Promise((done) => {
    resolveModuleOverrides = done;
  });
  exports = (
    moduleOverrides: EMCCModuleOverrides
  ): Promise<EMCCModuleOverrides> => {
    if (resolveModuleOverrides) {
      resolveModuleOverrides(moduleOverrides);
      return asyncModuleOverrides;
    } else {
      return Promise.resolve().then(
        () => exports(moduleOverrides) as Promise<any>
      );
    }
  };
  addEventListener("message", onmessage);
} else if (ENVIRONMENT_IS_NODE) {
  const {
    parentPort,
    isMainThread,
    Worker,
    workerData,
  } = require("worker_threads"); // eslint-disable-line
  if (isMainThread) {
    asyncModuleOverrides = {
      then() {
        return Promise.reject(
          new Error("Main thread initialization is not supported.")
        );
      },
    } as Promise<never>;
    exports = (moduleOverrides): Worker =>
      new Worker(__filename, {
        type: "module",
        workerData: { __filename, moduleOverrides },
      });
  } else if (workerData.__filename === __filename) {
    // if workerData is `__filename`, we assume worker has been spawned by this
    // module and user wants the default behavior.
    asyncModuleOverrides = Promise.resolve(workerData.moduleOverrides || {});

    parentPort.on("message", (data: RenderResponse) =>
      onmessage({ data } as MessageEvent)
    );
    postMessage = parentPort.postMessage.bind(parentPort);
  } else {
    // Worker spawned by another module or script, exports a function that lets
    // user define a custom override objects.
    let resolveModuleOverrides: Function;
    asyncModuleOverrides = new Promise((done) => {
      resolveModuleOverrides = done;
    });
    exports = (
      moduleOverrides: EMCCModuleOverrides
    ): Promise<EMCCModuleOverrides> => {
      if (resolveModuleOverrides) {
        resolveModuleOverrides(moduleOverrides);
        return asyncModuleOverrides;
      } else {
        return Promise.resolve().then(
          () => exports(moduleOverrides) as Promise<EMCCModuleOverrides>
        );
      }
    };
  }
}

export default exports;
