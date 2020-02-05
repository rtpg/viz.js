// Overhead for Node.js

import { fileURLToPath } from "url";
import { dirname } from "path";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Define a module-global postMessage to use inside workers
var postMessage;

// #include render.mjs
