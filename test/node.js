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

  it("should render a graph using sync version", function () {
    const renderStringSync = require("@aduh95/viz.js/sync");

    assert.ok(renderStringSync("digraph { a -> b; }"));
  });

  it("should render same graph using async and sync versions", async function () {
    const viz = await getViz();
    const renderStringSync = require("@aduh95/viz.js/sync");

    const resultSync = renderStringSync("digraph { a -> b; }");
    return viz
      .renderString("digraph { a -> b; }")
      .then((result) => assert.strictEqual(result, resultSync))
      .finally(() => viz.terminateWorker());
  });
});
