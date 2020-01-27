function emitWarning() {
  if (!emitWarning.warned) {
    emitWarning.warned = true;
    const deprecation = new Error(
      `Requiring '${
        require("../package.json").name
      }' package is deprecated, please use import instead.`
    );
    deprecation.name = "DeprecationWarning";

    process.emitWarning(deprecation, "DeprecationWarning");
  }
}

emitWarning();
module.exports = import("./index.mjs").then(module => module.default);
