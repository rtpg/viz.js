PREFIX_FULL = $(abspath ./prefix-full)
PREFIX_LITE = $(abspath ./prefix-lite)
DIST_FOLDER = $(abspath ./dist)

NODE ?= node

VIZ_VERSION ?= $(shell $(NODE) -p "require('./package.json').version")-$(shell git rev-parse HEAD)
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.44.0
EMSCRIPTEN_VERSION = 1.39.16

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.gz"
GRAPHVIZ_SOURCE_URL = "https://www2.graphviz.org/Packages/stable/portable_source/graphviz-$(GRAPHVIZ_VERSION).tar.gz"
YARN_SOURCE_URL = "https://github.com/yarnpkg/berry/raw/master/packages/berry-cli/bin/berry.js"

EMCONFIGURE ?= emconfigure
EMMAKE ?= emmake
EMCC ?= emcc
CC = $(EMCC)
CC_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=0 -s ENVIRONMENT=node,worker --closure 0 -g1
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

YARN_PATH = $(abspath $(shell awk '{ if($$1 == "yarnPath:") print $$2; }' .yarnrc.yml))
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
all: $(shell $(NODE) -p 'require("./package.json").files.join(" ")')

.PHONY: deps
deps: expat-full graphviz-full $(YARN_PATH)
	$(YARN) install

.PHONY: clean
.NOTPARALLEL: clean
clean:
	@echo "\033[3mHint: use \033[0mmake maintainer-clean\033[3m to start from a clean slate.\033[0m" >&2
	$(RM) -r async build dist sync
	$(RM) wasm worker
	$(RM) test/deno-files/render.wasm.uint8.js test/deno-files/index.d.ts

.PHONY: maintainer-clean
maintainer-clean: | clean
	$(RM) -r build build-full $(PREFIX_FULL) $(PREFIX_LITE) $(YARN_DIR) node_modules

async/index.js sync/index.js: %/index.js: | %
	echo "module.exports=require('../dist/render_$(@D).js')" > $@
async/index.d.ts sync/index.d.ts: %/index.d.ts: dist/render_%.d.ts | %
	echo "export {default} from '../dist/render_$(@D)'" > $@

wasm worker:
	echo "throw new Error('The bundler you are using does not support package.json#exports.')" > $@

build/viz_wrapper.js build/worker.js build/index.js build/render_async.js build/render_sync.js: build/%.js: src/%.ts | build
	$(TSC) $(TS_FLAGS) --outDir $(@D) -m es2020 --target esnext $<

dist/index.d.ts dist/render_async.d.ts dist/render_sync.d.ts: dist/%.d.ts: src/%.ts | dist
	$(TSC) $(TS_FLAGS) --outDir $(@D) -d --emitDeclarationOnly $^

dist/types.d.ts: src/types.d.ts | dist
	cp $< $@

test/deno-files/index.d.ts: dist/index.d.ts
	sed '\,^///, d;/as NodeJSWorker/ d;s#"./types";#"../../dist/types.d.ts";#' $< > $@
	echo "declare type NodeJSWorker=never;" >> $@

dist/index.mjs: build/index.js | dist
	$(TERSER) --toplevel $^ > $@

dist/index.cjs: src/index.cjs | dist
	$(TERSER) --toplevel $^ > $@

build/render: build/render.mjs
	# Remove env detection mechanism
	# Don't use any extension to match TS resolution
	sed \
		-e "s/import.meta.url/false/" \
		-e "s/ENVIRONMENT_[[:upper:]]*_[[:upper:]]*[[:space:]]*=[^=]/false\&\&/g" \
		-e "s/var false\&\&false;//g" \
		-e "s/new TextDecoder(.utf-16le.)/false/g" \
		$^ > $@

build/asm: build/asm.js
	# Creates an ES2015 module from emcc asm.js
	# Don't use any extension to match TS resolution
	echo ";export default Module" |\
	cat $^ - > $@

build/render.browser.js: build/worker.js build/render 
	$(ROLLUP) -f esm $< > $@

build/render.node.mjs: src/nodejs-module-interop.mjs build/render.browser.js
	cat $^ > $@

dist/render.browser.js: DEFINES=\
		-d ENVIRONMENT_HAS_NODE=false -d ENVIRONMENT_IS_NODE=false \
		-d ENVIRONMENT_IS_WEB=true -d ENVIRONMENT_IS_WORKER=true \

dist/render.node.mjs: DEFINES=\
		-d ENVIRONMENT_HAS_NODE=true -d ENVIRONMENT_IS_NODE=true \
		-d ENVIRONMENT_IS_WEB=false -d ENVIRONMENT_IS_WORKER=false \

dist/render.browser.js dist/render.node.mjs: dist/%: build/% | dist
	$(TERSER) --toplevel $(DEFINES) $<> $@

build/render.wasm: build/render.mjs
	[ -f '$@' ] || ($(RM) $^ && $(MAKE) $@)

dist/render.wasm: build/render.wasm | dist
	cp $< $@

build/asm.js: CC_FLAGS:=$(CC_FLAGS) -s WASM=0 -s WASM_ASYNC_COMPILATION=0 --memory-init-file 0
build/render.mjs build/asm.js: src/viz.cpp | build
	$(CC) --version | grep $(EMSCRIPTEN_VERSION)
	$(CC) $(CC_FLAGS) -Oz -o $@ $< $(CC_INCLUDES)

dist/render_async.js: build/render_async.js | dist
	sed 's/export default/module.exports=/' $< | $(TERSER) --toplevel > $@
dist/render_sync.js: build/render_sync.js build/asm build/viz_wrapper.js | dist
	$(ROLLUP) -f commonjs $< | $(TERSER) --toplevel > $@

async build dist $(PREFIX_FULL) sync:
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
	[ `uname` != 'Darwin' ] || [ -f $</configure.ac.old ] || (\
		cp $</configure.ac $</configure.ac.old && \
		sed '/-headerpad_max_install_names/d' $</configure.ac.old > $</configure.ac \
	)
	cd $< && $(EMCONFIGURE) ./configure --quiet --without-sfdp --disable-ltdl --enable-static --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(EMMAKE) $(MAKE) --quiet lib plugin
	cd $</lib && $(EMMAKE) $(MAKE) --quiet install
	cd $</plugin && $(EMMAKE) $(MAKE) --quiet install


build-full/expat-$(EXPAT_VERSION) build-full/graphviz-$(GRAPHVIZ_VERSION): build-full/%: sources/%.tar.gz
	mkdir -p $@
	tar -zxf $< --strip-components 1 -C $@

$(YARN_PATH): SOURCE=$(YARN_SOURCE_URL)
sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz: SOURCE=$(GRAPHVIZ_SOURCE_URL)
sources/expat-$(EXPAT_VERSION).tar.gz: SOURCE=$(EXPAT_SOURCE_URL)
sources/expat-$(EXPAT_VERSION).tar.gz sources/graphviz-$(GRAPHVIZ_VERSION).tar.gz $(YARN_PATH):
	curl --fail --create-dirs --location $(SOURCE) -o $@

.PHONY: test
test: lint test-deno test-node test-ts-integration

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
ifdef REPORTER
	$(MOCHA) test --reporter=$(REPORTER)
else
	$(MOCHA) test
endif

.PHONY: test-ts-integration
test-ts-integration: pack
	$(eval TMP := $(shell mktemp -d))
	mkdir -p $(TMP)/$@
	awk '{ if($$1 != "yarnPath:") print $$0; }' .yarnrc.yml > $(TMP)/$@/.yarnrc.yml
	touch $(TMP)/$@/package.json
	cp sources/viz.js-v$(VIZ_VERSION).tar.gz $(TMP)
	cd $(TMP)/$@ && $(YARN) add $(TMP)/viz.js-v$(VIZ_VERSION).tar.gz
	cp test/integration.ts $(TMP)/$@/
	$(TSC) --noEmit $(TMP)/$@/integration.ts

test/deno-files/render.wasm.arraybuffer.js: dist/render.wasm
	echo "export default Uint16Array.from([" > $@ && \
	hexdump -v -x $< | awk '$$1=" "' OFS=",0x" >> $@ && \
	echo "]).buffer.slice(2,$(shell wc -c $< | awk '{if (int($$1) % 2) print "-1"}'))" >> $@

.PHONY: test-deno
ifdef DENO
test-deno: all test/deno-files/render.wasm.arraybuffer.js test/deno-files/index.d.ts
	$(DENO) test \
		--unstable --importmap=test/deno-files/importmap.json --allow-read\
		-r test/deno.ts
else
test-deno:
	$(warning Deno tests are disabled by environment.)
endif

.PHONY: pack
pack: all
	$(YARN) pack -o sources/viz.js-v$(VIZ_VERSION).tar.gz

.PHONY: publish
publish: CURRENT_VIZ_VERSION=$(shell $(NODE) -p "require('./package.json').version")
publish:
	@echo "Checking for clean git stage..."
	@git diff --exit-code --quiet . || (\
		echo "Working directory contains unstaged changes:" && \
		git status --untracked-files=no --porcelain && \
		echo "Stage, commit, stash, or discard those changes before publishing a new version." && \
		false \
	)
	@echo "Checking for version number formatting..."
	@$(NODE) -e \
		"/^\d+\.\d+\.\d+(-(alpha|beta|rc)(\.\d+)?)?$$/.test('$(VIZ_VERSION)')||\
		process.exit(1)" || \
		(\
		echo "You must specify a valid version number. Aborting." && \
		echo "\033[3mHint: use \033[0mVIZ_VERSION=<newversion> make $@\033[3m to specify the new version number.\033[0m" >&2 && \
		echo "\033[3mHint: current Viz version is \033[0m$(CURRENT_VIZ_VERSION)\033[3m, received \033[0m$(VIZ_VERSION)\033[3m.\033[0m" >&2 &&\
		false \
	)
ifndef SKIP_CHANGELOG_VERIF
	grep "### @aduh95/Viz.js v$(VIZ_VERSION) (unreleased)" CHANGELOG.md || (\
		echo "Missing or ill-formed CHANGELOG entry. Aborting." && \
		false \
	)
	@echo "Checking for updated CHANGELOG..."
	@(! git diff --exit-code v$(CURRENT_VIZ_VERSION) CHANGELOG.md) || (\
		echo "No changes to CHANGELOG since previous release. Aborting." && \
		echo "\033[3mHint: use \033[0mSKIP_CHANGELOG_VERIF=true make $@\033[3m to publish anyway.\033[0m" >&2 && \
		false \
	)
	@echo "Updating CHANGELOG version release date..."
	sed 's/(unreleased)/($(shell date +"%Y-%m-%d"))/' \
	  < CHANGELOG.md > CHANGELOG.md.tmp
else
	$(warning CHANGELOG check is disabled by environment.)
	$(RM) CHANGELOG.md.tmp
endif
	@echo "Updating package.json version number..."
	@$(NODE) -e 'fs.writeFileSync(\
		"./package.json",\
		JSON.stringify(\
			require("./package.json"),\
			(k,v)=>k==="version"?"$(VIZ_VERSION)":v,\
			2\
		)+"\n")' && \
	! git diff --exit-code --quiet package.json || (\
		echo "You must specify a new version. Aborting." && \
		echo "\033[3mHint: use \033[0mVIZ_VERSION=<newversion> make $@\033[3m to specify the new version number.\033[0m" >&2 && \
		echo "\033[3mHint: current Viz version is \033[0m$(CURRENT_VIZ_VERSION)\033[3m, received \033[0m$(VIZ_VERSION)\033[3m.\033[0m" >&2 && \
		false \
	)
	$(MAKE) clean
	@echo "Running tests..."
	$(MAKE) test
	@echo "Commiting new version..."
	[ -f CHANGELOG.md.tmp ] && \
		mv CHANGELOG.md.tmp CHANGELOG.md && \
		git add CHANGELOG.md
	git add package.json
	git commit -m "v$(VIZ_VERSION)"
	git tag "v$(VIZ_VERSION)"
	@echo "Publishing new version..."
	$(YARN) npm publish --access public
	@echo "Pushing new version..."
	git push && git push --tags
