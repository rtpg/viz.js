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
import Viz from "https://unpkg.com/@aduh95/viz.js@3.0.0-beta.6";

const vizDistFolder = "https://unpkg.com/@aduh95/viz.js@3.0.0-beta.6/dist";
const workerURL = URL.createObjectURL(
  new Blob(
    [
      `import init from "${vizDistFolder}/render.browser.js";`,
      "init({",
      "locateFile(fileName) {",
      // allows the worker to resolve the wasm file URL
      `return \`${vizDistFolder}/\${fileName}\`;`,
      "}",
      "});",
    ],
    { type: "application/javascript" }
  )
);

async function dot2svg(dot, options) {
  const viz = new Viz({ workerURL });

  return viz.renderString(dot, options);
}
```

If you want to support browsers that do not support loading webworker as module,
or want a custom message handling, you can use dynamic imports to help you:

```js
// worker.js
/**
 * Lazy-loads Viz.js message handler
 * @returns {(event: MessageEvent) => Promise<any>}
 */
function getVizMessageHandler() {
  if (this._messageHandler === undefined) {
    const vizDistFolder = "https://unpkg.com/@aduh95/viz.js@3.0.0-beta.6/dist";
    const Module = {
      // locateFile is used by render module to locate WASM file.
      locateFile: fileName => `${vizDistFolder}/${fileName}`,
    };
    this._messageHandler = import(Module.locateFile("render.browser.js")).then(
      ({ default: init, onmessage }) => {
        // to avoid conflicts, disable viz.js message handler
        self.removeEventListener("message", onmessage);

        return init(Module).then(() => onmessage);
      }
    );
  }
  return this._messageHandler;
}

self.addEventListener("message", event => {
  if (event.data.id) {
    // handling event sent by viz.js
    getVizMessageHandler()
      .then(onmessage => onmessage(event))
      .catch(error => {
        // handle dynamic import error here
        console.error(error);

        // Note: If an error is emitted by Viz.js internals (dot syntax error,
        // WASM file initialization error, etc.), the error is catch and sent
        // directly through postMessage.
        // If you think this behavior is not ideal, please open an issue.
      });
  } else {
    // handle other messages
  }
});
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
