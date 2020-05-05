import type { RenderOptions } from "./types";
import type { WebAssemblyModule } from "./render";

export default function render(
  Module: WebAssemblyModule,
  src: string,
  options: RenderOptions
): string {
  for (const { path, data } of options.files) {
    Module.vizCreateFile(path, data);
  }

  Module.vizSetY_invert(options.yInvert ? 1 : 0);
  Module.vizSetNop(options.nop || 0);

  const resultString = Module.vizRenderFromString(
    src,
    options.format,
    options.engine
  );

  const errorMessageString = Module.vizLastErrorMessage();

  if (errorMessageString !== "") {
    throw new Error(errorMessageString);
  }

  return resultString;
}
