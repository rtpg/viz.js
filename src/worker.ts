import type {
  RenderOptions,
  SerializedError,
  RenderResponse,
  RenderRequest,
} from "./index";

// Emscripten "magic" globals
declare var Module: { [functionName: string]: any };
declare var ENVIRONMENT_IS_WORKER: boolean;
declare var ENVIRONMENT_IS_NODE: boolean;

// Worker global functions
declare var postMessage: (data: RenderResponse) => void;
declare var addEventListener: (type: "message", data: EventListener) => void;

if (ENVIRONMENT_IS_WORKER) {
  addEventListener("message", onmessage);
} else if (ENVIRONMENT_IS_NODE) {
  const { parentPort, isMainThread, Worker } = require("worker_threads");
  if (isMainThread) {
    module.exports = () => new Worker(__filename);
  } else {
    parentPort.on("message", (data: RenderResponse) =>
      onmessage({ data } as MessageEvent)
    );
    // @ts-ignore
    function postMessage() {
      "use strict";
      return parentPort.postMessage.apply(parentPort, arguments);
    }
  }
}

const wasmInitialisation = new Promise(done => {
  "use strict";
  Module.onRuntimeInitialized = done;
});

function render(src: string, options: RenderOptions) {
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

  wasmInitialisation
    .then(() => {
      const result = render(src, options);
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
