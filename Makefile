PREFIX_FULL = $(abspath ./prefix-full)
PREFIX_LITE = $(abspath ./prefix-lite)

VIZ_VERSION = $(shell node -p "require('./package.json').version")
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.43.20200109.0924
EMSCRIPTEN_VERSION = 1.38.44

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.bz2"
GRAPHVIZ_SOURCE_URL = "https://gitlab.com/graphviz/graphviz/-/archive/f4e30e65c1b2f510412d62e81e30c27dd7665861/graphviz-f4e30e65c1b2f510412d62e81e30c27dd7665861.tar.gz"

CC_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=0 -s ENVIRONMENT=node,worker -s USE_CLOSURE_COMPILER=1
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

PREAMBLE = "/**\n\
 * Viz.js $(VIZ_VERSION) (Graphviz $(GRAPHVIZ_VERSION), Expat $(EXPAT_VERSION), Emscripten $(EMSCRIPTEN_VERSION))\n\
 */"
BEAUTIFY?=false

.PHONY: all
# Should be kept in sync with the "files" field in package.json
all: src/index.cjs src/index.mjs src/worker.js src/render.js src/render.wasm

.PHONY: test
test: all
	yarn mocha test

.PHONY: debug
debug:
	$(MAKE) clean
	EMCC_DEBUG=1 emcc $(CC_FLAGS) -s ASSERTIONS=2 -g4 -o build-full/render.js src/viz.cpp $(CC_INCLUDES)
	BEAUTIFY=true $(MAKE) all

.PHONY: deps
deps: expat-full graphviz-full
	yarn install

.PHONY: clean
clean:
	echo "\033[1;33mHint: use \033[1;32mmake clobber\033[1;33m to start from a clean slate\033[0m" >&2
	rm -f build-full/render.js build-full/render.wasm
	rm -f src/render.js src/render.wasm src/index.js src/index.mjs

.PHONY: clobber
clobber: | clean
	rm -rf build-main build-full build-lite $(PREFIX_FULL) $(PREFIX_LITE)

src/worker.js: src/worker.ts
	yarn tsc --lib esnext,WebWorker -m es6 --target es5 $^

src/index.js: src/index.ts
	yarn tsc --lib esnext,WebWorker -m es6 --target esnext $^

src/index.mjs: src/index.js
	yarn terser --toplevel -m --warn -b beautify=$(BEAUTIFY),preamble='$(PREAMBLE)' $^ > $@

src/render.js: build-full/render.js src/worker.js
	yarn terser -m --warn -b beautify=$(BEAUTIFY),preamble='$(PREAMBLE)' $^ > $@

build-full/render.wasm: build-full/render.js

src/render.wasm: build-full/render.wasm
	cp build-full/render.wasm src/render.wasm

build-full/render.js: src/viz.cpp
	emcc --version | grep $(EMSCRIPTEN_VERSION)
	emcc $(CC_FLAGS) -Oz -o $@ $< $(CC_INCLUDES)

$(PREFIX_FULL):
	mkdir -p $(PREFIX_FULL)

.PHONY: expat–full
expat-full: | build-full/expat-$(EXPAT_VERSION) $(PREFIX_FULL)
	grep $(EXPAT_VERSION) build-full/expat-$(EXPAT_VERSION)/expat_config.h
	cd build-full/expat-$(EXPAT_VERSION) && emconfigure ./configure --quiet --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd build-full/expat-$(EXPAT_VERSION) && emmake make --quiet -C lib all install

.PHONY: graphviz-full
graphviz-full: | build-full/graphviz-$(GRAPHVIZ_VERSION) $(PREFIX_FULL)
	grep $(GRAPHVIZ_VERSION) build-full/graphviz-$(GRAPHVIZ_VERSION)/graphviz_version.h
	cd build-full/graphviz-$(GRAPHVIZ_VERSION) && ./configure --quiet
	cd build-full/graphviz-$(GRAPHVIZ_VERSION)/lib/gvpr && make --quiet mkdefs CFLAGS="-w"
	mkdir -p build-full/graphviz-$(GRAPHVIZ_VERSION)/FEATURE
	cp hacks/FEATURE/sfio hacks/FEATURE/vmalloc build-full/graphviz-$(GRAPHVIZ_VERSION)/FEATURE
	cd build-full/graphviz-$(GRAPHVIZ_VERSION) && emconfigure ./configure --quiet --without-sfdp --disable-ltdl --enable-static --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd build-full/graphviz-$(GRAPHVIZ_VERSION) && emmake make --quiet lib plugin
	cd build-full/graphviz-$(GRAPHVIZ_VERSION)/lib && emmake make --quiet install
	cd build-full/graphviz-$(GRAPHVIZ_VERSION)/plugin && emmake make --quiet install


build-full/expat-$(EXPAT_VERSION): sources/expat-$(EXPAT_VERSION).tar.bz2
	mkdir -p $@
	tar -jxf sources/expat-$(EXPAT_VERSION).tar.bz2 --strip-components 1 -C $@

build-full/graphviz-$(GRAPHVIZ_VERSION): sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz
	mkdir -p $@
	tar -zxf sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz --strip-components 1 -C $@

sources:
	mkdir -p sources

sources/expat-$(EXPAT_VERSION).tar.bz2: | sources
	curl --fail --location $(EXPAT_SOURCE_URL) -o $@

sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz: | sources
	curl --fail --location $(GRAPHVIZ_SOURCE_URL) -o $@
