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
   * @type {Browser}
   */
  let browser;

  /**
   * @type {Page}
   */
  let page;

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

  this.afterAll(() => page.close());
  after(() => Promise.all([server.close(), browser.close()]));

  this.beforeEach(async function() {
    page = await browser.newPage();

    await page.goto(`http://localhost:${await server.port}/`);
    await page.evaluate(function() {
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
  });

  it("rendering sample graphs should not throw errors", async function() {
    const graphs = [
      "digraph g {\n  n1 [shape = circle];\n  n2 [shape = egg];\n  n3 [shape = triangle];\n  n4 [shape = diamond];\n  n5 [shape = trapezium];\n}",
      'digraph g {\n    \n  {rank = same; n1; n2; n3; n4; n5}\n  \n  n1 -> n2;\n  n2 -> n3;\n  n3 -> n4;\n  n4 -> n5;\n  \n  subgraph cluster1 {\n    label = "cluster1";\n    color = lightgray;\n    style = filled;\n    \n    n6;\n  }\n  \n  subgraph cluster2 {\n    label = "cluster2";\n    color = red;\n    \n    n7;\n    n8;\n  }\n  \n  n1 -> n6;\n  n2 -> n7;\n  n8 -> n3;\n  n6 -> n7;\n  \n}',
      'digraph g {\nnode001->node002;\nsubgraph cluster1 {\n    node003;\n    node004;\n    node005;\n}\nnode006->node002;\nnode007->node005;\nnode007->node002;\nnode007->node008;\nnode002->node005[label="x"];\nnode004->node007;\n}',
    ];

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

  it("result from first graph in input is returned for multiple invocations", async function() {
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
    await assert.rejects(
      page.evaluate(() =>
        getViz().then(viz => viz.renderString("digraph { \n ->"))
      ),
      /error in line 2 near \'->\'/
    );
  });

  it("able to recover after throwing exceptions on invalid input", async function() {
    const viz = await page.evaluateHandle(() => window.getViz());

    await assert.rejects(
      page.evaluate(
        viz => viz.renderString('digraph {\n a -> b [label="erroneous]\n}'),
        viz
      ),
      /syntax error in line 2/
    );
    await assert.rejects(
      page.evaluate(
        viz => viz.renderString('digraph {\n a -> \n[label="erroneous]\n}'),
        viz
      ),
      /syntax error in line 3/
    );

    await assert.doesNotReject(
      page.evaluate(
        viz => viz.renderString('digraph {\n a -> b [label="correcteous"]\n}'),
        viz
      )
    );
    await assert.rejects(
      page.evaluate(viz => viz.renderString("digraph { a -> "), viz),
      /syntax error in line 1/
    );

    await assert.doesNotReject(
      page.evaluate(viz => viz.renderString("digraph { a -> b }"), viz)
    );
  });

  it("syntax error following graph throws exception", async function() {
    await assert.rejects(
      page.evaluate(() =>
        getViz().then(viz => viz.renderString("digraph { \n } ->"))
      ),
      /error in line 1 near \'->\'/
    );
  });

  it("syntax error message has correct line numbers for multiple invocations", async function() {
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

  it("repeated calls to render using setTimeout should not throw an error", async function() {
    const memoryStressTest = (done, error) => {
      let i = 0;
      const NB_ITERATIONS = 500;
      const MEMORY_TEST_SRC =
        'digraph G{\n\ttype="digraph";rankdir="TB";use="dot";ranksep="0.3";\n\t949[fontname="Helvetica",color="#000000",shape="box",label="S&#xa;n0",fontcolor="#000000",]\n\t950[fontname="Helvetica",color="#000000",shape="box",label="S&#xa;n1",fontcolor="#000000",]\n\t951[fontname="Helvetica",color="#00cc00",shape="box",label="R&#xa;n2",fontcolor="#00cc00",]\n\t949->944[fontname="Helvetica",color="#000000",weight="10",constraint="true",label="s&#xa;e0",fontcolor="#000000",]\n\t951->944[fontname="Helvetica",color="#00cc00",weight="1",constraint="true",label="ex&#xa;e1",fontcolor="#00cc00",]\n\t949->945[fontname="Helvetica",color="#000000",weight="10",constraint="true",label="pr&#xa;e2",fontcolor="#000000",]\n\t950->946[fontname="Helvetica",color="#000000",weight="10",constraint="true",label="aux&#xa;e3",fontcolor="#000000",]\n\t950->947[fontname="Helvetica",color="#000000",weight="10",constraint="true",label="s&#xa;e4",fontcolor="#000000",]\n\t951->947[fontname="Helvetica",color="#00cc00",weight="1",constraint="true",label="ex&#xa;e5",fontcolor="#00cc00",]\n\t950->948[fontname="Helvetica",color="#000000",weight="10",constraint="true",label="pr&#xa;e6",fontcolor="#000000",]\n\t949->950[fontname="Helvetica",color="#00cc00",weight="1",constraint="true",label="ad&#xa;rel: caus&#xa;e7",fontcolor="#00cc00",]\n\t944->945[style="invis",weight="100",]945->946[style="invis",weight="100",]946->947[style="invis",weight="100",]\n\t947->948[style="invis",weight="100",]\n\tsubgraph wnabyquvkgfmjxes{\n\t\trank="same";\n\t\t944[fontname="Helvetica",label="er&#xa;t0",shape="box",style="bold",color="#000000",fontcolor="#000000",]\n\t\t945[fontname="Helvetica",label="stirbt&#xa;t1",shape="box",style="bold",color="#000000",fontcolor="#000000",]\n\t\t946[fontname="Helvetica",label="weil&#xa;t2",shape="box",style="bold",color="#000000",fontcolor="#000000",]\n\t\t947[fontname="Helvetica",label="er&#xa;t3",shape="box",style="bold",color="#000000",fontcolor="#000000",]\n\t\t948[fontname="Helvetica",label="lacht&#xa;t4",shape="box",style="bold",color="#000000",fontcolor="#000000",]\n\t}\n\tsubgraph vpmznchgjtuxbrfe{\n\t\t949[]\n\t\t950[]\n\t}\n\tsubgraph ohzxavtqesiunwlk{\n\t\t951[]\n\t}\n}';
      function f() {
        viz
          .renderString(MEMORY_TEST_SRC)
          .then(() => {
            i++;

            if (i === NB_ITERATIONS) {
              done();
            } else {
              requestIdleCallback(f, { timeout: 100 });
            }
          })
          .catch(error);
      }

      f();
    };

    await assert.doesNotReject(
      page.evaluate(
        `()=>window.getViz().then(viz=>new Promise(${memoryStressTest}))`
      )
    );
  });

  it("should accept yInvert option", async function() {
    const viz = await page.evaluateHandle(() => window.getViz());

    await page.evaluate(() => {
      window.parse = output => output.match(/pos=\"[^\"]+\"/g).slice(0, 2);
    });

    const regular = await page.evaluate(
      viz =>
        viz
          .renderString("digraph { a -> b; }", { format: "xdot" })
          .then(window.parse),
      viz
    );

    assert.notStrictEqual(
      ...regular,
      "Regular positions should not be equal to each other"
    );

    const inverted = await page.evaluate(
      viz =>
        viz
          .renderString("digraph { a -> b; }", {
            format: "xdot",
            yInvert: true,
          })
          .then(window.parse),
      viz
    );

    assert.notStrictEqual(
      ...inverted,
      "Inverted positions should not be equal to each other"
    );

    assert.deepStrictEqual(
      inverted.reverse(),
      regular,
      "Inverted positions should be the reverse of regular"
    );

    assert.deepStrictEqual(
      await page.evaluate(
        viz =>
          viz
            .renderString("digraph { a -> b; }", { format: "xdot" })
            .then(window.parse),
        viz
      ),
      regular,
      "Subsequent calls not setting yInvert should return the regular positions"
    );
  });

  it("should accept nop option and produce different outputs", async function() {
    const viz = await page.evaluateHandle(() => window.getViz());

    await page.evaluate(() => {
      window.graphSrc =
        'digraph { a[pos="10,20"]; b[pos="12,22"]; a -> b [pos="20,20 20,20 20,20 20,20"]; }';
    });

    const regular = await page.evaluate(
      viz => viz.renderString(graphSrc, { engine: "neato", format: "svg" }),
      viz
    );
    const nop1 = await page.evaluate(
      viz =>
        viz.renderString(graphSrc, { engine: "neato", format: "svg", nop: 1 }),
      viz
    );

    assert.notStrictEqual(
      nop1,
      regular,
      "Nop = 1 should produce different result than default"
    );

    const nop2 = await page.evaluate(
      viz =>
        viz.renderString(graphSrc, { engine: "neato", format: "svg", nop: 2 }),
      viz
    );

    assert.notStrictEqual(
      nop2,
      regular,
      "Nop = 2 should produce different result than default"
    );
    assert.notStrictEqual(
      nop2,
      nop1,
      "Nop = 2 should produce different result than Nop = 1"
    );
  });

  it("should output SVG with correct labels", async function() {
    const [node1Text, node2Text] = await page.evaluate(() =>
      window.getViz().then(viz =>
        viz
          .renderString("digraph { a -> b; }")
          .then(window.parseSVG)
          .then(({ documentElement }) => [
            documentElement.querySelector("g#node1 text").textContent,
            documentElement.querySelector("g#node2 text").textContent,
          ])
      )
    );

    assert.strictEqual(node1Text, "a");
    assert.strictEqual(node2Text, "b");
  });

  it('can reference images by name if dimensions are specified using the "images" option', async function() {
    const [name, width, height] = await page.evaluate(() =>
      window.getViz().then(viz =>
        viz
          .renderString('digraph { a[image="test.png"]; }', {
            images: [{ path: "test.png", width: 400, height: 300 }],
          })
          .then(window.parseSVG)
          .then(({ documentElement }) => [
            documentElement
              .querySelector("image")
              .getAttributeNS("http://www.w3.org/1999/xlink", "href"),
            documentElement.querySelector("image").getAttribute("width"),
            documentElement.querySelector("image").getAttribute("height"),
          ])
      )
    );

    assert.strictEqual(name, "test.png");
    assert.strictEqual(width, "400px");
    assert.strictEqual(height, "300px");
  });

  it("can reference images with a protocol and hostname", async function() {
    const result = await page.evaluate(() =>
      window.getViz().then(viz =>
        viz
          .renderString(
            'digraph { a[id="a",image="http://example.com/xyz/test.png"]; b[id="b",image="http://example.com/xyz/test2.png"]; }',
            {
              images: [
                {
                  path: "http://example.com/xyz/test.png",
                  width: 400,
                  height: 300,
                },
                {
                  path: "http://example.com/xyz/test2.png",
                  width: 300,
                  height: 200,
                },
              ],
            }
          )
          .then(window.parseSVG)
          .then(({ documentElement }) => [
            documentElement
              .querySelector("#a image")
              .getAttributeNS("http://www.w3.org/1999/xlink", "href"),
            documentElement.querySelector("#a image").getAttribute("width"),
            documentElement.querySelector("#a image").getAttribute("height"),

            documentElement
              .querySelector("#b image")
              .getAttributeNS("http://www.w3.org/1999/xlink", "href"),
            documentElement.querySelector("#b image").getAttribute("width"),
            documentElement.querySelector("#b image").getAttribute("height"),
          ])
      )
    );

    assert.deepStrictEqual(result, [
      "http://example.com/xyz/test.png",
      "400px",
      "300px",

      "http://example.com/xyz/test2.png",
      "300px",
      "200px",
    ]);
  });
});
