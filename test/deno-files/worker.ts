import initWASM from "@aduh95/viz.js/worker";

initWASM({
  locateFile() {
    return "../../dist/render.wasm";
  },
});
