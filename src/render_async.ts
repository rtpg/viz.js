import type Viz from "./index.js";
import type { Worker } from "worker_threads";
import type { RenderOptions } from "./types";

let viz: Viz;

/**
 * Renders a DOT graph to the specified format.
 * @param src DOT representation of the graph to render.
 * @param options Options for the rendering engine.
 * @returns Raw output of Graphviz as a string.
 */
export default async function renderStringAsync(
  src: string,
  options?: RenderOptions
): Promise<string> {
  if (viz == null) {
    /* eslint-disable @typescript-eslint/ban-ts-comment */
    const [Viz, getWorker] = await Promise.all([
      // @ts-ignore
      import("@aduh95/viz.js"),
      // @ts-ignore
      import("@aduh95/viz.js/worker"),
    ]);
    /* eslint-enable @typescript-eslint/ban-ts-comment */
    viz = new Viz.default({ worker: getWorker.default() as Worker });
  }
  return viz.renderString(src, options);
}
