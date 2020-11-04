import "./webworker-polyfill.js";
import {
  default as initWASM,
  onmessage as o,
} from "../../dist/render.browser.js";
import wasmBinary from "./render.wasm.arraybuffer.js";

removeEventListener("message", o);

onmessage = function (m) {
  initWASM({
    wasmBinary,
  })
    .then(() => o(m))
    .catch(console.error);
};
