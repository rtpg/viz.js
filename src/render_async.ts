import type Viz from "./index.js";
import type { Worker } from "worker_threads";
import type { RenderOptions } from "./types";

let viz: Viz;
export default async function renderStringAsync(
  src: string,
  options?: RenderOptions
): Promise<string> {
  if (viz == null) {
    /* eslint-disable @typescript-eslint/ban-ts-ignore */
    const [Viz, getWorker] = await Promise.all([
      // @ts-ignore
      import("@aduh95/viz.js"),
      // @ts-ignore
      import("@aduh95/viz.js/worker"),
    ]);
    /* eslint-enable @typescript-eslint/ban-ts-ignore */
    viz = new Viz.default({ worker: getWorker.default() as Worker });
  }
  return viz.renderString(src, options);
}
