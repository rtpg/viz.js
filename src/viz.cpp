#include <emscripten.h>
#include <emscripten/bind.h>
#include <gvc.h>

using namespace emscripten;

extern int Y_invert;
extern int Nop;

extern gvplugin_library_t gvplugin_core_LTX_library;
extern gvplugin_library_t gvplugin_dot_layout_LTX_library;
#ifndef VIZ_LITE
extern gvplugin_library_t gvplugin_neato_layout_LTX_library;
#endif

char *errorMessage = NULL;

int vizErrorf(char *buf) {
  errorMessage = buf;
  return 0;
}

std::string vizLastErrorMessage() {
  if (errorMessage == NULL) return "";
  std::string str(errorMessage);
  return str;
}

void vizSetY_invert(int invert) {
  Y_invert = invert;
}

void vizSetNop(int value) {
  if (value != 0)
    Nop = value;
}

std::string vizRenderFromString(std::string src, std::string format, std::string engine) {
  GVC_t *context;
  Agraph_t *graph;
  const char *input = src.c_str();
  char *output = NULL;
  std::string result;
  unsigned int length;
  
  context = gvContext();
  gvAddLibrary(context, &gvplugin_core_LTX_library);
  gvAddLibrary(context, &gvplugin_dot_layout_LTX_library);
#ifndef VIZ_LITE
  gvAddLibrary(context, &gvplugin_neato_layout_LTX_library);
#endif

  agseterr(AGERR);
  agseterrf(vizErrorf);
  
  agreadline(1);
  
  while ((graph = agmemread(input))) {
    if (output == NULL) {
      gvLayout(context, graph, engine.c_str());
      gvRenderData(context, graph, format.c_str(), &output, &length);
      gvFreeLayout(context, graph);
    }
    
    agclose(graph);
    
    input = "";
  }

  result.assign(output, length);
  free(output);
  
  return result;
}

EMSCRIPTEN_BINDINGS(viz_js) {
  function("vizRenderFromString", &vizRenderFromString);
  function("vizSetY_invert", &vizSetY_invert);
  function("vizSetNop", &vizSetNop);
  function("vizLastErrorMessage", &vizLastErrorMessage);
}
