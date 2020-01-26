const assert = require("assert");
const puppeteer = require("puppeteer");

const args = puppeteer.defaultArgs();
args[args.findIndex(flag => /enable-features/.test(flag))] +=
  ",ExperimentalProductivityFeatures,ImportMaps";
const PUPPETEER_OPTIONS = { args };

describe("Test graph rendering using web browser", function() {
  /**
   * @type {{close:Promise<void>, port: Promise<number>}}
   */
  let server;

  /**
   * type {Browser}
   */
  let browser;

  before(() =>
    Promise.all([
      import("./web-server/bootstrap.mjs").then(module => {
        server = module.default();
      }),
      puppeteer.launch(PUPPETEER_OPTIONS).then(b => {
        browser = b;
      }),
    ])
  );

  after(() => Promise.all([server.close(), browser.close()]));

  it("rendering sample graphs should not throw errors", async function() {
    const page = await browser.newPage();

    const graphs = [
      "digraph g {\n  n1 [shape = circle];\n  n2 [shape = egg];\n  n3 [shape = triangle];\n  n4 [shape = diamond];\n  n5 [shape = trapezium];\n}",
      'digraph g {\n    \n  {rank = same; n1; n2; n3; n4; n5}\n  \n  n1 -> n2;\n  n2 -> n3;\n  n3 -> n4;\n  n4 -> n5;\n  \n  subgraph cluster1 {\n    label = "cluster1";\n    color = lightgray;\n    style = filled;\n    \n    n6;\n  }\n  \n  subgraph cluster2 {\n    label = "cluster2";\n    color = red;\n    \n    n7;\n    n8;\n  }\n  \n  n1 -> n6;\n  n2 -> n7;\n  n8 -> n3;\n  n6 -> n7;\n  \n}',
      'digraph g {\nnode001->node002;\nsubgraph cluster1 {\n    node003;\n    node004;\n    node005;\n}\nnode006->node002;\nnode007->node005;\nnode007->node002;\nnode007->node008;\nnode002->node005[label="x"];\nnode004->node007;\n}',
    ];

    await page.goto(`http://localhost:${await server.port}/`);
    await page.evaluate(function getViz() {
      window.getViz = () =>
        Promise.all([
          import("@aduh95/viz.js").then(m => m.default),
          import("@aduh95/viz.js/worker").then(m => m.default),
        ]).then(([Viz, workerURL]) => new Viz({ workerURL }));
      window.domParser = new DOMParser();
      window.parseSVG = svg =>
        window.domParser.parseFromString(svg, "image/svg+xml");
      window.checkSVG = svg => {
        try {
          return window.parseSVG(svg) instanceof SVGDocument;
        } catch {
          return false;
        }
      };
    });
    for (const graph of graphs) {
      await assert.doesNotReject(
        page.evaluate(
          graph =>
            getViz()
              .then(viz => viz.renderString(graph))
              .then(window.check),
          graph
        )
      );
    }
  });
});
