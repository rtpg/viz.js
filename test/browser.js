const assert = require("assert");
const puppeteer = require("puppeteer");

const args = puppeteer.defaultArgs();
args[args.findIndex(flag => /enable-features/.test(flag))] +=
  ",ExperimentalProductivityFeatures,ImportMaps";
const PUPPETEER_OPTIONS = { args };

const makeVizGloballyAvailableOn = page =>
  page.evaluate(function() {
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
    await makeVizGloballyAvailableOn(page);

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

    await page.close();
  });

  it("result from first graph in input is returned for multiple invocations", async function() {
    const page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await makeVizGloballyAvailableOn(page);

    const viz = await page.evaluateHandle(() => window.getViz());

    const resultAThenB = await page.evaluate(
      viz => viz.renderString("digraph A {} digraph B {}", { format: "xdot" }),
      viz
    );
    assert.match(
      resultAThenB,
      /digraph A/,
      'Result should contain "digraph A"'
    );
    assert.doesNotMatch(
      resultAThenB,
      /digraph B/,
      'Result should not contain "digraph B"'
    );

    const resultBThenA = await page.evaluate(
      viz => viz.renderString("digraph B {} digraph A {}", { format: "xdot" }),
      viz
    );
    assert.doesNotMatch(
      resultBThenA,
      /digraph A/,
      'Result should not contain "digraph A"'
    );
    assert.match(
      resultBThenA,
      /digraph B/,
      'Result should contain "digraph B"'
    );
  });

  it("syntax error in graph throws exception", async function() {
    const page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await makeVizGloballyAvailableOn(page);

    await assert.rejects(
      page.evaluate(() =>
        getViz().then(viz => viz.renderString("digraph { \n ->"))
      ),
      /error in line 2 near \'->\'/
    );
  });

  it("after throwing an exception on invalid input with an incomplete quoted string, continue to throw exceptions on valid input", async function() {
    const page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await makeVizGloballyAvailableOn(page);

    const viz = await page.evaluateHandle(() => window.getViz());

    await assert.rejects(
      page.evaluate(
        viz => viz.renderString('digraph {\n a -> b [label="erroneous]\n}'),
        viz
      )
    );

    await assert.rejects(
      page.evaluate(
        viz => viz.renderString('digraph {\n a -> b [label="correcteous"]\n}'),
        viz
      )
    );
  });

  it("syntax error following graph throws exception", async function() {
    const page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await makeVizGloballyAvailableOn(page);

    await assert.rejects(
      page.evaluate(() =>
        getViz().then(viz => viz.renderString("digraph { \n } ->"))
      ),
      /error in line 1 near \'->\'/
    );
  });

  it("syntax error message has correct line numbers for multiple invocations", async function() {
    const page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await makeVizGloballyAvailableOn(page);

    const viz = await page.evaluateHandle(() => window.getViz());

    await assert.rejects(
      page.evaluate(viz => viz.renderString("digraph { \n } ->"), viz),
      /error in line 1 near \'->\'/
    );

    await assert.rejects(
      page.evaluate(viz => viz.renderString("digraph { \n } ->"), viz),
      /error in line 1 near \'->\'/
    );
  });

  it("input with characters outside of basic latin should not throw an error", async function() {
    const page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await makeVizGloballyAvailableOn(page);

    await Promise.all([
      page
        .evaluate(() =>
          getViz().then(viz => viz.renderString("digraph { α -> β; }"))
        )
        .then(result => {
          assert.match(result, /α/, 'Result should contain "α"');
          assert.match(result, /β/, 'Result should contain "β"');
        }),

      page
        .evaluate(() =>
          getViz().then(viz => viz.renderString('digraph { a [label="åäö"]; }'))
        )
        .then(result =>
          assert.match(result, /åäö/, 'Result should contain "åäö"')
        ),
    ]);
  });
});
