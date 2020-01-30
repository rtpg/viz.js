# Viz.js

[![Build Status](https://travis-ci.org/mdaines/viz.js.svg?branch=master)](https://travis-ci.org/mdaines/viz.js)

This project builds [Graphviz](http://www.graphviz.org) with
[Emscripten](http://kripken.github.io/emscripten-site/) and provides a simple
wrapper for using it in the browser.

For more information, [see the wiki](https://github.com/mdaines/viz.js/wiki).

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
  const Viz = await import("@aduh95/viz.js").then(module => module.default);
  const getWorker = await import("@aduh95/viz.js/worker").then(
    module => module.default
  );

  const worker = getWorker();
  const viz = new Viz({ worker });

  return viz.renderString(dot, options);
}
```

### Browsers

In a world where Import Maps and `import.meta.resolve` are reality, you could
have something like that:

```js
import Viz from "@aduh95/viz.js";

async function dot2svg(dot, options) {
  const workerURL = await import.meta.resolve("@aduh95/viz.js/worker");

  const viz = new Viz({ workerURL });

  return viz.renderString(dot, options);
}
```

## Building From Source

To build from source, first
[install the Emscripten SDK](http://kripken.github.io/emscripten-site/docs/getting_started/index.html).
You'll also need [Node.js](https://nodejs.org/) and [Yarn](https://yarnpkg.com).

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
