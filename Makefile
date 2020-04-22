PREFIX_FULL = $(abspath ./prefix-full)
PREFIX_LITE = $(abspath ./prefix-lite)
DIST_FOLDER = $(abspath ./dist)

NODE ?= node

VIZ_VERSION ?= $(shell $(NODE) -p "require('./package.json').version")-$(shell git rev-parse HEAD)
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.44.0
EMSCRIPTEN_VERSION = 1.39.13

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.bz2"
GRAPHVIZ_SOURCE_URL = "https://www2.graphviz.org/Packages/stable/portable_source/graphviz-$(GRAPHVIZ_VERSION).tar.gz"
YARN_SOURCE_URL = "https://github.com/yarnpkg/berry/raw/master/packages/berry-cli/bin/berry.js"

EMCONFIGURE ?= emconfigure
EMMAKE ?= emmake
EMCC ?= emcc
CC = $(EMCC)
CC_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=0 -s ENVIRONMENT=node,worker --closure 0 -g1
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

YARN_PATH = $(abspath $(shell awk '{ if($$1 == "yarnPath:") print $$2; }' .yarnrc.yml))
YARN_DIR = $(dir $(YARN_PATH))
YARN ?= $(NODE) $(YARN_PATH)

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

ESLINT ?= $(YARN) eslint
MOCHA ?= $(YARN) mocha
ROLLUP ?= $(YARN) rollup

.PHONY: all
all: \
		dist \
			dist/index.cjs dist/index.mjs dist/index.d.ts dist/types.d.ts \
			dist/render.node.mjs dist/render.browser.js dist/render.wasm \
	 	wasm \
		worker \


.PHONY: test
test: lint test-deno test-node ts-test-integration

.PHONY: lint
lint: lint-ts lint-test

.PHONY: lint-ts
lint-ts:
	$(ESLINT) src --ext .ts

.PHONY: lint-test
lint-test:
	$(ESLINT) test

.PHONY: test-node
test-node: all
	$(MOCHA) test

.PHONY: ts-test-integration
ts-test-integration: pack
	$(eval TMP := $(shell mktemp -d))
	mkdir -p $(TMP)/$@
	awk '{ if($$1 != "yarnPath:") print $$0; }' .yarnrc.yml > $(TMP)/$@/.yarnrc.yml
	touch $(TMP)/$@/package.json
	cp sources/viz.js-v$(VIZ_VERSION).tar.gz $(TMP)
	cd $(TMP)/$@ && $(YARN) add $(TMP)/viz.js-v$(VIZ_VERSION).tar.gz
	cp test/integration.ts $(TMP)/$@/
	$(TSC) --noEmit $(TMP)/$@/integration.ts

.PHONY: test-deno
ifdef DENO
test-deno: all test/deno-files/render.wasm.arraybuffer.js test/deno-files/index.d.ts
	$(DENO) --importmap test/deno-files/importmap.json -r test/deno.ts
else
test-deno:
	@echo "Deno tests are disabled by environment."
endif

.PHONY: pack
pack: all
	$(YARN) pack -o sources/viz.js-v$(VIZ_VERSION).tar.gz

.PHONY: publish
publish: CURRENT_VIZ_VERSION=$(shell $(NODE) -p "require('./package.json').version")
publish:
	@git diff --exit-code --quiet . || (\
		echo "Working directory contains unstaged changes:" && \
		git status --untracked-files=no --porcelain && \
		echo "Stage, commit, stash, or discard those changes before publishing a new version." && \
		exit 1 \
	)
	@(! git diff --exit-code v$(CURRENT_VIZ_VERSION) CHANGELOG.md) || (\
		echo "No changes to CHANGELOG since previous release. Aborting." && \
		exit 1 \
	)
	@[ "$(VIZ_VERSION)" != "$(CURRENT_VIZ_VERSION)-$(shell git rev-parse HEAD)" ] || (\
		echo "\033[1;31mYou must specify a new version: \033[1;32mVIZ_VERSION=<newversion> make $@\033[0m" && \
		exit 1 \
	)
	$(NODE) -e 'fs.writeFileSync("./package.json",JSON.stringify(require("./package.json"),(k,v)=>k==="version"?"$(VIZ_VERSION)":v,2)+"\n")'
	git diff package.json
	$(MAKE) clean
	$(MAKE) test -j4
	git add package.json
	git commit -m "v$(VIZ_VERSION)"
	git tag "v$(VIZ_VERSION)"
	$(YARN) npm publish --access public
	git push && git push --tags

.PHONY: debug
debug:
	$(MAKE) clean
	EMCC_DEBUG=1 $(CC) $(CC_FLAGS) -s ASSERTIONS=2 -g4 -o build/render.js src/viz.cpp $(CC_INCLUDES)
	BEAUTIFY=true $(MAKE) all

.PHONY: deps
deps: expat-full graphviz-full $(YARN_PATH)
	$(YARN) install

.PHONY: clean
.NOTPARALLEL: clean
clean:
	@echo "\033[1;33mHint: use \033[1;32mmake clobber\033[1;33m to start from a clean slate\033[0m" >&2
	rm -rf build dist
	rm -f wasm worker
	rm -f test/deno-files/render.wasm.uint8.js test/deno-files/index.d.ts

.PHONY: clobber
clobber: | clean
	rm -rf build build-full $(PREFIX_FULL) $(PREFIX_LITE) $(YARN_DIR) node_modules

wasm worker:
	echo "throw new Error('The bundler you are using does not support package.json#exports.')" > $@

build/worker.js: src/worker.ts | build
	$(TSC) $(TS_FLAGS) --outDir build -m es6 --target esnext $<

build/index.js: src/index.ts | build
	$(TSC) $(TS_FLAGS) --outDir build -m es6 --target esnext $<

dist/index.d.ts: src/index.ts
	$(TSC) $(TS_FLAGS) --outDir $(DIST_FOLDER) -d --emitDeclarationOnly $^

dist/types.d.ts: src/types.d.ts | dist
	cp $< $@

test/deno-files/index.d.ts: dist/index.d.ts
	sed '\,^///, d;/as NodeJSWorker/ d;s#"./types";#"../../dist/types.d.ts";#' $< > $@
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

build/render.js: src/viz.cpp | build
	$(CC) --version | grep $(EMSCRIPTEN_VERSION)
	$(CC) $(CC_FLAGS) -Oz -o $@ $< $(CC_INCLUDES)

test/deno-files/render.wasm.arraybuffer.js: dist/render.wasm
	echo "export default Uint16Array.from([" > $@ && \
	hexdump -v -x $< | awk '$$1=" "' OFS=",0x" >> $@ && \
	echo "]).buffer.slice(2$(shell stat -f%z $< | awk '{if (int($$1) % 2) print ",-1"}'))" >> $@

$(PREFIX_FULL) build dist sources $(YARN_DIR):
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
	[ `uname` != 'Darwin' ] || [ -f $</configure.ac.old ] || (\
		cp $</configure.ac $</configure.ac.old && \
		sed '/-headerpad_max_install_names/d' $</configure.ac.old > $</configure.ac \
	)
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

$(YARN_PATH): | $(YARN_DIR)
	curl --fail --location $(YARN_SOURCE_URL) -o $@
