import Module from "./asm.mjs";
import render from "./renderFunction.js";

import type { RenderOptions } from "./types";

let asmModule;
export default function renderStringSync(
  src: string,
  options?: RenderOptions
): string {
  if (asmModule == null) {
    asmModule = Module();
  }
  return render(asmModule, src, {
    format: "svg",
    engine: "dot",
    files: [],
    images: [],
    yInvert: false,
    nop: 0,
    ...(options || {}),
  });
}
