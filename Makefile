PREFIX_FULL = $(abspath ./prefix-full)
PREFIX_LITE = $(abspath ./prefix-lite)
DIST_FOLDER = $(abspath ./dist)

VIZ_VERSION ?= $(shell node -p "require('./package.json').version")
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.43.20200109.0924
EMSCRIPTEN_VERSION = 1.38.44

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.bz2"
GRAPHVIZ_SOURCE_URL = "https://gitlab.com/graphviz/graphviz/-/archive/f4e30e65c1b2f510412d62e81e30c27dd7665861/graphviz-f4e30e65c1b2f510412d62e81e30c27dd7665861.tar.gz"

CC ?= emcc
CC_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=0 -s ENVIRONMENT=node,worker --closure 0 -g1
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

TSC ?= yarn tsc
TS_FLAGS = --lib esnext,WebWorker

PREAMBLE = "/**\n\
 * Viz.js $(VIZ_VERSION) (Graphviz $(GRAPHVIZ_VERSION), Expat $(EXPAT_VERSION), Emscripten $(EMSCRIPTEN_VERSION))\n\
 */"
BEAUTIFY?=false

ifeq ($(BEAUTIFY), false)
	TERSER = yarn terser --warn -m -b beautify=$(BEAUTIFY),preamble='$(PREAMBLE)'
else
	TERSER = yarn terser --warn -b
endif

MOCHA ?= yarn mocha

.PHONY: all
all: \
		dist \
			dist/index.cjs dist/index.mjs dist/index.d.ts \
			dist/render.node.mjs dist/render.browser.js dist/render.wasm \
	 	wasm \
		worker \


.PHONY: test
test: all
	$(MOCHA) $@
	# Deno test don't pass, skipping
	# deno --importmap test/deno-files/importmap.json test/deno.ts

.PHONY: publish
publish:
	npm version $(VIZ_VERSION)
	$(MAKE) clean
	$(MAKE) test -j4 || (git reset HEAD^ --hard && git tag -d v$(VIZ_VERSION) && exit 1)
	yarn pack -o sources/viz.js-v$(VIZ_VERSION).tar.gz
	npm publish --access public
	git push && git push --tags

.PHONY: debug
debug:
	$(MAKE) clean
	EMCC_DEBUG=1 $(CC) $(CC_FLAGS) -s ASSERTIONS=2 -g4 -o build/render.js src/viz.cpp $(CC_INCLUDES)
	BEAUTIFY=true $(MAKE) all

.PHONY: deps
deps: | expat-full graphviz-full
	yarn install

.PHONY: clean
clean:
	@echo "\033[1;33mHint: use \033[1;32mmake clobber\033[1;33m to start from a clean slate\033[0m" >&2
	rm -rf build dist
	rm -f wasm worker
	mkdir build dist

.PHONY: clobber
clobber: | clean
	rm -rf build build-full $(PREFIX_FULL) $(PREFIX_LITE)

dist:
	mkdir -p $(DIST_FOLDER)

wasm worker:
	echo "throw new Error('The bundler you are using does not support package.json#exports.')" > $@

build/worker.js: src/worker.ts
	$(TSC) $(TS_FLAGS) --outDir build -m es6 --target es6 $^

build/index.js: src/index.ts
	$(TSC) $(TS_FLAGS) --outDir build -m es6 --target esnext $^

dist/index.d.ts: src/index.ts
	$(TSC) $(TS_FLAGS) --outDir $(DIST_FOLDER) -d --emitDeclarationOnly $^

dist/index.mjs: build/index.js
	$(TERSER) --toplevel $^ > $@

dist/index.cjs: src/index.cjs
	$(TERSER) --toplevel $^ > $@

build/render: build/render.js
	# Creates an ES2015 module from emcc render.js
	# Don't use any extension to match TS resolution
	echo "export default function(Module){" |\
	cat - $^ |\
	sed -E \
		-e "s/ENVIRONMENT_(IS|HAS)_[A-Z]+ *=[^=]/false\&\&/" \
		-e "s/var false\&\&false;//" \
		> $@ &&\
	echo "return new Promise(done=>{\
			Module.onRuntimeInitialized = ()=>done(Module);\
	})}" >> $@

build/render.rollup.js: build/worker.js build/render 
	yarn rollup -f esm $< > $@

build/render.node.mjs: src/nodejs-module-interop.mjs build/render.rollup.js
	cat $^ > $@

dist/render.node.mjs: build/render.node.mjs
	$(TERSER) --toplevel \
		-d ENVIRONMENT_HAS_NODE=true -d ENVIRONMENT_IS_WEB=false \
		-d ENVIRONMENT_IS_WORKER=false -d ENVIRONMENT_IS_NODE=true \
		$^ > $@

dist/render.browser.js: build/render.rollup.js
	$(TERSER) --toplevel \
		-d ENVIRONMENT_HAS_NODE=false -d ENVIRONMENT_IS_WEB=false \
		-d ENVIRONMENT_IS_WORKER=true -d ENVIRONMENT_IS_NODE=false \
		$^ > $@

dist/render.js: build/render.js build/worker.js
	$(TERSER) $^ > $@

build/render.wasm: build/render.js

dist/render.wasm: build/render.wasm
	cp $< $@

build/render.js: src/viz.cpp
	$(CC) --version | grep $(EMSCRIPTEN_VERSION)
	$(CC) $(CC_FLAGS) -Oz -o $@ $< $(CC_INCLUDES)

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
