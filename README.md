# Viz.js

[![Build Status](https://travis-ci.org/mdaines/viz.js.svg?branch=master)](https://travis-ci.org/mdaines/viz.js)

This project builds [Graphviz](http://www.graphviz.org) with
[Emscripten](http://kripken.github.io/emscripten-site/) and provides a simple
wrapper for using it in the browser.

## See Also

Have a look at [Dagre](https://dagrejs.github.io/), which is not a hack.

## Usage

### Node.js

```js
import Viz from "@aduh95/viz.js";
import getWorker from "@aduh95/viz.js/worker";

const worker = getWorker();
const viz = new Viz({ worker });

viz
  .renderString("digraph{1 -> 2 }")
  .then(svgString => {
    console.log(svgString);
  })
  .catch(error => {
    console.error(error);
  })
  .finally(() => {
    // If you don't terminate the worker explicitly, it will be terminated at the end of process
    worker.terminate();
  });
```

If you want to use it from a CommonJS script, you would need to use a dynamic
imports:

```js
async function dot2svg(dot, options = {}) {
  const Viz = await import("@aduh95/viz.js").then(m => m.default);
  const getWorker = await import("@aduh95/viz.js/worker").then(m => m.default);

  const worker = getWorker();
  const viz = new Viz({ worker });

  return viz.renderString(dot, options);
}
```

### Browsers

You can either use the `worker` or the `workerURL` on the constructor.

```js
import Viz from "/node_modules/@aduh95/viz.js/dist/index.mjs";

const workerURL = "/node_modules/@aduh95/viz.js/dist/render.js";
```

N.B.: Emscripten `render.js` expects to find a `render.wasm` on the same
directory as `render.js`. If you are using a building tool that changes file
names and/or file location, the loading would fail.

If you are using a CDN or loading the files from a different origin, most
browsers will block you from spawning a cross-origin webworker. There is a
workaround:

```js
import Viz from "https://unpkg.com/@aduh95/viz.js@3.0.0-beta.2/dist/index.mjs";

const workerURL = URL.createObjectURL(
  new Blob(
    [
      "self.Module =",
      "{ locateFile: file =>",
      '"https://unpkg.com/@aduh95/viz.js@3.0.0-beta.2/dist/"',
      "+ file",
      "};", // Module.locateFile let the worker resolve the wasm file URL
      "importScripts(", // importScripts is not restricted by same-origin policy
      "Module.locateFile(", // We can use it to load the JS file
      '"render.js"',
      "));",
    ],
    { type: "application/javascript" }
  )
);

async function dot2svg(dot, options) {
  const viz = new Viz({ workerURL });

  return viz.renderString(dot, options);
}
```

## Building From Source

To build from source, first
[install the Emscripten SDK](http://kripken.github.io/emscripten-site/docs/getting_started/index.html).
You'll also need [Node.js 13+](https://nodejs.org/) and
[Yarn 2+](https://yarnpkg.com).

On macOS:

```shell
brew install yarn binaryen emscripten automake libtool pkg-config qt
```

You will certainly need to tweak config files to make sure your system knows
where it should find each binary.

The build process for Viz.js is split into two parts: building the Graphviz and
Expat dependencies, and building the rendering script files and API.

    make deps
    make all -j4
    make test
