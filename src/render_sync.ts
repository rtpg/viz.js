import Module from "./asm";
import render from "./viz_wrapper.js";

import type { RenderOptions } from "./types";

/**
 * Renders a DOT graph to the specified format.
 * @param src DOT representation of the graph to render.
 * @param options Options for the rendering engine.
 * @returns Raw output of Graphviz as a string.
 */
export default function renderStringSync(
  src: string,
  {
    format = "svg",
    engine = "dot",
    files = [],
    images = [],
    yInvert = false,
    nop = 0,
  }: RenderOptions = {}
): string {
  for (const { path, width, height } of images) {
    files.push({
      path,
      data:
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n' +
        '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n' +
        `<svg width="${width}" height="${height}"></svg>`,
    });
  }
  return render(Module, src, {
    format,
    engine,
    files,
    yInvert,
    nop,
  });
}
