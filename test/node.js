const assert = require("assert");

async function getViz() {
  const worker = await import("@aduh95/viz.js/worker").then((module) =>
    module.default()
  );
  const Viz = await import("@aduh95/viz.js").then((module) => module.default);
  return new Viz({ worker });
}

describe("Test graph rendering using Node.js", function () {
  it("should render a graph using worker", async function () {
    const viz = await getViz();
    return viz
      .renderString("digraph { a -> b; }")
      .then((result) => assert.ok(result))
      .finally(() => viz.terminateWorker());
  });

  it("should be able to render several graphs with same instance", async function () {
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
      .then((result) => assert.ok(result))
      .finally(() => viz.terminateWorker());
  });
});
