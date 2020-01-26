import { promises as fs, createReadStream } from "fs";
import path from "path";
import { createServer } from "http";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PROJECT_ROOT = path.join(__dirname, "..", "..");

/**
 * Loading list of client side modules to make url resolution faster
 * @type {Promise<string[]>}
 */
const runtimeModules = fs
  .readFile(path.join(PROJECT_ROOT, "/package.json"))
  .then(JSON.parse)
  .then(({ files }) => files);

const requestListener = async (req, res) => {
  try {
    if (req.url === "/") {
      res.setHeader("Content-Type", "text/html");
      createReadStream(path.join(__dirname, "index.html")).pipe(res);
    } else if ((await runtimeModules).includes(req.url.substring(1))) {
      const mime = `application/${
        req.url.endsWith("wasm") ? "wasm" : "javascript"
      }`;
      res.setHeader("Content-Type", mime);

      createReadStream(path.join(PROJECT_ROOT, req.url)).pipe(res);
    } else {
      console.log(404, req.url);
      res.statusCode = 404;
      res.end(`Cannot find '${req.url}' on this server.`);
    }
  } catch (e) {
    console.error(e);
    res.statusCode = 500;
    res.end("Internal Error");
  }
};

export const startServer = () => {
  let resolvePort;
  const port = new Promise(done => {
    resolvePort = done;
  });
  const server = createServer(requestListener).listen(
    0,
    "localhost",
    function() {
      const { port } = server.address();
      resolvePort(port);
      console.log(`Server started on http://localhost:${port}`);
    }
  );

  return {
    port,
    close: () =>
      new Promise(done => {
        server.unref().close(done);
      }),
  };
};

export default startServer;
