const assert = require("assert");

async function getViz() {
  const worker = await import("@aduh95/viz.js/worker").then(
    module => module.default
  );
  const Viz = await import("@aduh95/viz.js").then(module => module.default);
  return new Viz({ worker });
}
const globalViz = getViz();

it("should render a graph using worker", async function() {
  const viz = await globalViz;
  return viz.renderString("digraph { a -> b; }").then(function(result) {
    assert.ok(result);
  });
});

it("should throw descriptive error when not enough memory allocated", async function() {
  const viz = await globalViz;

  let dot = "digraph {";
  for (let i = 0; i < 50000; ++i) {
    dot += `node${i} -> node${i + 1};`;
  }
  dot += "}";

  return viz.renderString(dot).then(
    () => {
      assert.fail("should throw");
    },
    error => {
      assert(
        /Cannot enlarge memory arrays/.test(error.message),
        "should return descriptive error",
        console.error(error)
      );
    }
  );
});
