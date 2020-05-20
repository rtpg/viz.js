import Module from "./asm.mjs";
import render from "./viz_wrapper.js";

import type { RenderOptions } from "./types";
import type { WebAssemblyModule } from "./render";

let asmModule: WebAssemblyModule;

/**
 * Renders a DOT graph to the specified format.
 * @param src DOT representation of the graph to render.
 * @param options Options for the rendering engine.
 * @returns Raw output of Graphviz as a string.
 */
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
