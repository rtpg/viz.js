import { unreachable, runTests, test } from "std::testing";

/// @deno-types="@aduh95/viz.js/types"
import Viz from "@aduh95/viz.js";
import workerURL from "@aduh95/viz.js/worker";

test({
  name: "Test graph rendering using Deno",
  fn(): Promise<any> {
    return getViz()
      .then(viz => viz.renderString("digraph { a -> b; }"))
      .catch(console.error)
      .catch(unreachable);
  },
});

test({
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
      .catch(unreachable);
  },
});

runTests();

async function getViz() {
  const worker = new Worker(workerURL, { type: "module" });
  return new Viz({ worker });
}
