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

You can either use the `worker` or the `workerURL` on the constructor. Note that
when using `workerURL`, `Viz` constructor will try to spawn a webworker using
`type=module`. If you don't want a module worker, you should provide a `worker`
instead.

The Worker module exports a function that takes
[an Emscripten Module object](https://emscripten.org/docs/api_reference/module.html#affecting-execution).
You can use that to tweak the defaults, the only requirement is to define a
`locateFile` method that returns the URL of the WASM file.

```js
// worker.js
import initWASM from "@aduh95/viz.js/worker";
// If you are not using a bundler that supports package.json#exports
// use /node_modules/@aduh95/viz.js/dist/render.browser.js instead.

import wasmURL from "file-loader!@aduh95/viz.js/wasm";
// If you are not using a bundler that supports package.json#exports
// Or doesn't have a file-loader plugin to get URL of the asset,
// use "/node_modules/@aduh95/viz.js/dist/render.wasm" instead.

initWASM({
  locateFile() {
    return wasmURL;
  },
});
```

And give feed that module to the main thread:

```js
//main.js
import Viz from "@aduh95/viz.js";
// If you are not using a bundler that supports package.json#exports
// use /node_modules/@aduh95/viz.js/dist/index.mjs instead.

const workerURL = "/worker.js";

let viz;
async function dot2svg(dot, options) {
  if (viz === undefined) {
    viz = new Viz({ workerURL });
  }
  return viz.renderString(dot, options);
}
```

If you are using a CDN and don't want a separate file for the worker module,
there is a workaround:

```js
import Viz from "https://unpkg.com/@aduh95/viz.js@3.0.0-beta.5/dist/index.mjs";

const workerURL = URL.createObjectURL(
  new Blob(
    [
      "const Module =",
      "{ locateFile: file =>",
      '"https://unpkg.com/@aduh95/viz.js@3.0.0-beta.5/dist/"',
      "+ file",
      "};", // Module.locateFile let the worker resolve the wasm file URL
      "import(", // importScripts is not restricted by same-origin policy
      "Module.locateFile(", // We can use it to load the JS file
      '"render.js"',
      ")).then(i=>i(Module));",
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
