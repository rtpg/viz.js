import { assertStrContains, unreachable } from "std::testing";

/// @deno-types="@aduh95/viz.js/types"
import Viz from "@aduh95/viz.js";
const workerURL = "./deno-files/worker.js";

{
  const { addEventListener } = Worker.prototype as any;
  (Worker as any).prototype.addEventListener = function (
    eventType: string,
    handler: Function
  ) {
    if ("message" === eventType) {
      this.onmessage = handler;
    } else {
      addEventListener.apply(this, arguments);
    }
  };
}

Deno.test({
  name: "Test graph rendering using Deno",
  fn(): Promise<any> {
    return getViz()
      .then((viz) => viz.renderString("digraph { a -> b; }"))
      .then((svg) => assertStrContains(svg, "</svg>"))
      .catch(unreachable);
  },
  disableOpSanitizer: true, // Cannot terminate Worker from main thread
});

Deno.test({
  name: "Test render several graphs with same instance",
  async fn(): Promise<any> {
    const viz = await getViz();

    let dot = "digraph {";
    let i = 0;
    dot += `node${i} -> node${i + 1};`;

    return viz
      .renderString(dot + "}")
      .then(() => {
        dot += `node${i} -> node${i + 1};`;

        return viz.renderString(dot + "}");
      })
      .then((svg: string) => assertStrContains(svg, "</svg>"))
      .catch(unreachable);
  },
});

Deno.runTests();

async function getViz() {
  return new Viz({ workerURL });
}
