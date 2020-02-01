const { name, exports } = require("../package.json");
const path = require("path");

const importURL = path.join(__dirname, "..", exports["."].import);

function emitWarning() {
  if (!emitWarning.warned) {
    emitWarning.warned = true;
    const deprecation = new Error(
      `Requiring '${name}' package is deprecated, please use import instead.`
    );
    deprecation.name = "DeprecationWarning";

    process.emitWarning(deprecation, "DeprecationWarning");
  }
}

emitWarning();
module.exports = import(importURL).then(module => module.default);
