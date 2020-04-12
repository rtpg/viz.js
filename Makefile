PREFIX_FULL = $(abspath ./prefix-full)
PREFIX_LITE = $(abspath ./prefix-lite)
DIST_FOLDER = $(abspath ./dist)

VIZ_VERSION ?= $(shell node -p "require('./package.json').version")
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.45.20200410.2133
EMSCRIPTEN_VERSION = 1.39.11

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.bz2"
GRAPHVIZ_SOURCE_URL = "https://gitlab.com/graphviz/graphviz/-/archive/f4e30e65c1b2f510412d62e81e30c27dd7665861/graphviz-f4e30e65c1b2f510412d62e81e30c27dd7665861.tar.gz"
YARN_SOURCE_URL = "https://github.com/yarnpkg/berry/raw/master/packages/berry-cli/bin/berry.js"

EMCONFIGURE ?= emconfigure
EMMAKE ?= emmake
EMCC ?= emcc
CC = $(EMCC)
CC_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=0 -s ENVIRONMENT=node,worker --closure 0 -g1
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

YARN_PATH = $(shell awk '{ if($$1 == "yarnPath:") print $$2; }' .yarnrc.yml)
YARN_DIR = $(shell dirname $(YARN_PATH))
YARN ?= node $(YARN_PATH)

TSC ?= $(YARN) tsc
TS_FLAGS = --lib esnext,WebWorker

DENO ?= deno

PREAMBLE = "/**\n\
 * Viz.js $(VIZ_VERSION) (Graphviz $(GRAPHVIZ_VERSION), Expat $(EXPAT_VERSION), Emscripten $(EMSCRIPTEN_VERSION))\n\
 * @license magnet:?xt=urn:btih:d3d9a9a6595521f9666a5e94cc830dab83b65699&dn=expat.txt MIT licensed\n\
 *\n\
 * This distribution contains other software in object code form:\n\
 * - [Emscripten](https://github.com/emscripten-core/emscripten/blob/master/LICENSE)\n\
 * - [Expat](https://github.com/libexpat/libexpat/blob/master/expat/COPYING)\n\
 * - [Graphviz](https://graphviz.org/license/)\n\
 */"
BEAUTIFY?=false

ifeq ($(BEAUTIFY), false)
	TERSER = $(YARN) terser --warn -m -b beautify=$(BEAUTIFY),preamble='$(PREAMBLE)'
else
	TERSER = $(YARN) terser --warn -b
endif

MOCHA ?= $(YARN) mocha
ROLLUP ?= $(YARN) rollup

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
	$(MAKE) deno-test

.PHONY: deno-test
deno-test: test/deno-files/render.wasm.arraybuffer.js test/deno-files/index.d.ts
	$(DENO) --importmap test/deno-files/importmap.json test/deno.ts

.PHONY: publish
publish:
	npm version $(VIZ_VERSION)
	$(MAKE) clean
	$(MAKE) test -j4 || (git reset HEAD^ --hard && git tag -d v$(VIZ_VERSION) && exit 1)
	$(YARN) pack -o sources/viz.js-v$(VIZ_VERSION).tar.gz
	npm publish --access public
	git push && git push --tags

.PHONY: debug
debug:
	$(MAKE) clean
	EMCC_DEBUG=1 $(CC) $(CC_FLAGS) -s ASSERTIONS=2 -g4 -o build/render.js src/viz.cpp $(CC_INCLUDES)
	BEAUTIFY=true $(MAKE) all

.PHONY: deps
deps: $(YARN_PATH) | expat-full graphviz-full
	$(YARN) install

.PHONY: clean
clean:
	@echo "\033[1;33mHint: use \033[1;32mmake clobber\033[1;33m to start from a clean slate\033[0m" >&2
	rm -rf build dist
	rm -f wasm worker
	rm -f test/deno-files/render.wasm.uint8.js test/deno-files/index.d.ts
	mkdir build dist

.PHONY: clobber
clobber: | clean
	rm -rf build build-full $(PREFIX_FULL) $(PREFIX_LITE) $(YARN_DIR) node_modules

wasm worker:
	echo "throw new Error('The bundler you are using does not support package.json#exports.')" > $@

build/worker.js: src/worker.ts
	$(TSC) $(TS_FLAGS) --outDir build -m es6 --target esnext $^

build/index.js: src/index.ts
	$(TSC) $(TS_FLAGS) --outDir build -m es6 --target esnext $^

dist/index.d.ts: src/index.ts
	$(TSC) $(TS_FLAGS) --outDir $(DIST_FOLDER) -d --emitDeclarationOnly $^

test/deno-files/index.d.ts: dist/index.d.ts
	sed '\,^///, d;/^import type/ d' $< > $@
	echo "declare type NodeJSWorker=never;" >> $@

dist/index.mjs: build/index.js
	$(TERSER) --toplevel $^ > $@

dist/index.cjs: src/index.cjs
	$(TERSER) --toplevel $^ > $@

build/render: build/render.js
	# Creates an ES2015 module from emcc render.js
	# Don't use any extension to match TS resolution
	echo "export default function(Module){" |\
	cat - $^ |\
	sed \
		-e "s/ENVIRONMENT_[[:upper:]]*_[[:upper:]]*[[:space:]]*=[^=]/false\&\&/g" \
		-e "s/var false\&\&false;//g" \
		-e "s/new TextDecoder(.utf-16le.)/false/g" \
		> $@ &&\
	echo "return new Promise(done=>{\
			Module.onRuntimeInitialized = ()=>done(Module);\
	})}" >> $@

build/render.rollup.js: build/worker.js build/render 
	$(ROLLUP) -f esm $< > $@

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
	@if ! ([ -f '$@' ]);then \
		rm $^ && $(MAKE) $@; \
	fi

dist/render.wasm: build/render.wasm
	cp $< $@

build/render.js: src/viz.cpp
	$(CC) --version | grep $(EMSCRIPTEN_VERSION)
	$(CC) $(CC_FLAGS) -Oz -o $@ $< $(CC_INCLUDES)

test/deno-files/render.wasm.arraybuffer.js: dist/render.wasm
	echo "export default Uint16Array.from([" > $@ && \
	hexdump -v -x $< | awk '$$1=" "' OFS=",0x" >> $@ && \
	echo "]).buffer.slice(2$(shell stat -f%z $< | awk '{if (int($$1) % 2) print ",-1"}'))" >> $@

$(PREFIX_FULL) dist sources $(YARN_DIR):
	mkdir -p $@

.PHONY: expat–full
expat-full: build-full/expat-$(EXPAT_VERSION) | $(PREFIX_FULL)
	grep $(EXPAT_VERSION) $</expat_config.h
	cd $< && $(EMCONFIGURE) ./configure --quiet --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(EMMAKE) $(MAKE) --quiet -C lib all install

.PHONY: graphviz-full
graphviz-full: build-full/graphviz-$(GRAPHVIZ_VERSION) | $(PREFIX_FULL)
	grep $(GRAPHVIZ_VERSION) $</graphviz_version.h
	cd $< && ./configure --quiet
	cd $</lib/gvpr && $(MAKE) --quiet mkdefs CFLAGS="-w"
	mkdir -p $</FEATURE
	cp hacks/FEATURE/sfio hacks/FEATURE/vmalloc $</FEATURE
	cd $< && $(EMCONFIGURE) ./configure --quiet --without-sfdp --disable-ltdl --enable-static --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(EMMAKE) $(MAKE) --quiet lib plugin
	cd $</lib && $(EMMAKE) $(MAKE) --quiet install
	cd $</plugin && $(EMMAKE) $(MAKE) --quiet install


build-full/expat-$(EXPAT_VERSION): sources/expat-$(EXPAT_VERSION).tar.bz2
	mkdir -p $@
	tar -jxf $< --strip-components 1 -C $@

build-full/graphviz-$(GRAPHVIZ_VERSION): sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz
	mkdir -p $@
	tar -zxf $< --strip-components 1 -C $@

sources/expat-$(EXPAT_VERSION).tar.bz2: | sources
	curl --fail --location $(EXPAT_SOURCE_URL) -o $@

sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz: | sources
	curl --fail --location $(GRAPHVIZ_SOURCE_URL) -o $@

$(YARN_PATH): $(YARN_DIR)
	curl --fail --location $(YARN_SOURCE_URL) -o $@
