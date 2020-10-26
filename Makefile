DEPS_FOLDER = $(abspath ./build-deps)
DIST_FOLDER = $(abspath ./dist)
PREFIX_FULL = $(abspath ./prefix-full)

NODE ?= node

EMSCRIPTEN_VERSION = 2.0.7
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.44.1
VIZ_VERSION ?= $(shell $(NODE) -p "require('./package.json').version")-$(shell git rev-parse HEAD)

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_$(subst .,_,$(EXPAT_VERSION))/expat-$(EXPAT_VERSION).tar.gz"
GRAPHVIZ_SOURCE_URL = "https://www2.graphviz.org/Packages/stable/portable_source/graphviz-$(GRAPHVIZ_VERSION).tar.gz"
YARN_SOURCE_URL = "https://github.com/yarnpkg/berry/raw/master/packages/berry-cli/bin/berry.js"

USE_CLOSURE ?= 1

EMCONFIGURE ?= emconfigure
EMMAKE ?= emmake
EMCC ?= emcc
CC = $(EMCC)
CC_FLAGS = -c
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz
LINK_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=$(USE_CLOSURE) --closure $(USE_CLOSURE) -g1
LINK_INCLUDES = -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

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
	TERSER = $(YARN) terser -m -b beautify=$(BEAUTIFY),preamble='$(PREAMBLE)' --ecma 2020
else
	TERSER = $(YARN) terser -b
endif

ESLINT ?= $(YARN) eslint
MOCHA ?= $(YARN) mocha
ROLLUP ?= $(YARN) rollup

DIST_FILES = $(shell $(NODE) -p 'require("./package.json").files.join(" ")')
.PHONY: all
all: $(DIST_FILES) | $(DEPS_FOLDER)

.PHONY: deps
deps: expat-full graphviz-full

.NOTPARALLEL: node_modules
node_modules: $(YARN_PATH) yarn.lock
	$(YARN) install --immutable
	touch $@

node_modules/%: node_modules
	touch $@	

yarn.lock:
	@[ -f '$@' ] || (\
		echo "Missing lock file. Try running 'git checkout -- $@'." && \
		false \
	)
	touch $@

.PHONY: clean
.NOTPARALLEL: clean
clean:
	@echo "\033[3mHint: use \033[0mmake maintainer-clean\033[3m to start from a clean slate.\033[0m" >&2
	$(RM) -r async build dist sync
	$(RM) wasm worker
	$(RM) test/deno-files/render.wasm.uint8.js test/deno-files/index.d.ts

npm-clean:
	$(RM) -r $(YARN_DIR) node_modules

.PHONY: maintainer-clean
maintainer-clean: | clean npm-clean
	$(RM) -r build $(DEPS_FOLDER) $(PREFIX_FULL)

$(DEPS_FOLDER):
	$(error You must run `make deps` first.)

async/index.js sync/index.js: %/index.js: | %
	echo "module.exports=require('../dist/render_$(@D).js')" > $@
async/index.d.ts sync/index.d.ts: %/index.d.ts: dist/render_%.d.ts | %
	echo "export {default} from '../dist/render_$(@D)'" > $@

wasm worker:
	echo "throw new Error('The bundler you are using does not support package.json#exports.')" > $@

build/viz_wrapper.js build/worker.js build/index.js build/render_async.js build/render_sync.js: build/%.js: src/%.ts node_modules/typescript | build
	$(TSC) $(TS_FLAGS) --outDir $(@D) -m es2020 --target esnext $<

dist/index.d.ts dist/render_async.d.ts dist/render_sync.d.ts: dist/%.d.ts: src/%.ts node_modules/typescript | dist
	$(TSC) $(TS_FLAGS) --outDir $(@D) -d --emitDeclarationOnly $<

dist/types.d.ts: src/types.d.ts | dist
	cp $< $@

test/deno-files/index.d.ts: dist/index.d.ts
	sed '\,^///, d;/as NodeJSWorker/ d;s#"./types";#"../../dist/types.d.ts";#' $< > $@
	echo "declare type NodeJSWorker=never;" >> $@

dist/index.mjs: build/index.js node_modules/terser | dist
	$(TERSER) --module $< > $@

dist/index.cjs: src/index.cjs node_modules/terser | dist
	$(TERSER) --toplevel $< > $@

build/asm: build/asm.js
	# Creates an ES2015 module from emcc asm.js
	# Don't use any extension to match TS resolution
ifeq ($(USE_CLOSURE), 0)
	echo ";export default Module" |\
	cat $^ - > $@
else
	sed -e 's/(module.exports[[:space:]]*=/false;export default(/' $< > $@
endif

build/browser/worker.js build/browser/viz_wrapper.js: build/browser/%.js: build/%.js | build/browser
	cp $< $@
build/node/worker.js build/node/viz_wrapper.js: build/node/%.js: build/%.js | build/node
	cp $< $@

build/browser/render: build/browser/render.mjs
	sed \
		-e "s/import.meta.url/false/" \
		-e "s/new TextDecoder(.utf-16le.)/false/g" \
		$< > $@

build/render.browser.js build/render.node.js: build/render.%.js: build/%/worker.js build/%/render build/%/viz_wrapper.js node_modules/rollup
	$(ROLLUP) -f esm $< > $@

build/node/render: build/node/render.mjs | build/node
	cp $< $@

build/render.node.mjs: src/nodejs-module-interop.mjs build/render.node.js
	cat $^ > $@

dist/render.browser.js: DEFINES=\
		-d ENVIRONMENT_HAS_NODE=false -d ENVIRONMENT_IS_NODE=false \
		-d ENVIRONMENT_IS_WEB=true -d ENVIRONMENT_IS_WORKER=true \

dist/render.node.mjs: DEFINES=\
		-d ENVIRONMENT_HAS_NODE=true -d ENVIRONMENT_IS_NODE=true \
		-d ENVIRONMENT_IS_WEB=false -d ENVIRONMENT_IS_WORKER=false \

dist/render.browser.js dist/render.node.mjs: dist/%: build/% node_modules/terser | dist
	$(TERSER) --module $(DEFINES) $<> $@

build/render.wasm: build/browser/render.wasm build/node/render.wasm
	@cmp $^ || (\
		echo "WASM files differ" && false \
	)
	cp $< $@

build/browser/render.wasm build/node/render.wasm: build/%/render.wasm: build/%/render.mjs
	[ -f '$@' ] || ($(RM) $^ && $(MAKE) $@)
	touch $@

dist/render.wasm: build/render.wasm | dist
	cp $< $@

build/render.o: src/viz.cpp | build
	$(CC) --version | grep $(EMSCRIPTEN_VERSION)
	$(CC) $(CC_FLAGS) -o $@ $< $(CC_INCLUDES)

build/asm.js: LINK_FLAGS:=$(LINK_FLAGS) -s WASM=0 -s WASM_ASYNC_COMPILATION=0 --memory-init-file 0
build/browser/render.mjs: | build/browser
build/node/render.mjs: | build/node
build/asm.js build/node/render.mjs: ENVIRONMENT:=node
build/browser/render.mjs: ENVIRONMENT:=worker
build/node/render.mjs build/browser/render.mjs build/asm.js: build/render.o
	$(CC) --version | grep $(EMSCRIPTEN_VERSION)
	$(CC) $(LINK_FLAGS) -s ENVIRONMENT=$(ENVIRONMENT) -Oz -o $@ $< $(LINK_INCLUDES)

dist/render_async.js: build/render_async.js node_modules/terser | dist
	sed 's/export default/module.exports=/' $< | $(TERSER) --toplevel > $@
dist/render_sync.js: build/render_sync.js build/asm build/viz_wrapper.js node_modules/rollup node_modules/terser | dist
	$(ROLLUP) -f commonjs --exports default $< | $(TERSER) --toplevel > $@

async build build/node build/browser dist $(PREFIX_FULL) sync:
	mkdir -p $@

.PHONY: expat–full
expat-full: $(DEPS_FOLDER)/expat-$(EXPAT_VERSION) | $(PREFIX_FULL)
	grep $(EXPAT_VERSION) $</expat_config.h
	cd $< && $(EMCONFIGURE) ./configure --quiet --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(EMMAKE) $(MAKE) --quiet -C lib all install

.PHONY: graphviz-full
graphviz-full: $(DEPS_FOLDER)/graphviz-$(GRAPHVIZ_VERSION) | $(PREFIX_FULL)
	grep $(GRAPHVIZ_VERSION) $</graphviz_version.h
	cd $< && ./configure --quiet
	cd $</lib/gvpr && $(MAKE) --quiet mkdefs CFLAGS="-w"
	[ `uname` != 'Darwin' ] || [ -f $</configure.ac.old ] || (\
		cp $</configure.ac $</configure.ac.old && \
		sed '/-headerpad_max_install_names/d;' $</configure.ac.old > $</configure.ac &&\
		true \
	)
	cd $< && $(EMCONFIGURE) ./configure --quiet --without-sfdp --disable-ltdl --enable-static --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(EMMAKE) $(MAKE) --quiet lib plugin
	cd $</lib && $(EMMAKE) $(MAKE) --quiet install
	cd $</plugin && $(EMMAKE) $(MAKE) --quiet install


$(DEPS_FOLDER)/expat-$(EXPAT_VERSION) $(DEPS_FOLDER)/graphviz-$(GRAPHVIZ_VERSION): $(DEPS_FOLDER)/%: sources/%.tar.gz
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
lint-ts: | node_modules/eslint
	$(ESLINT) src --ext .ts

.PHONY: lint-test/eslint
lint-test: | node_modules/eslint
	$(ESLINT) test

.PHONY: test-node
test-node: | $(DIST_FILES) node_modules/mocha
ifdef REPORTER
	$(MOCHA) test --reporter=$(REPORTER)
else
	$(MOCHA) test
endif

.PHONY: test-ts-integration
test-ts-integration: sources/viz.js-v$(VIZ_VERSION).tar.gz | $(YARN_PATH) node_modules/typescript
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
	head -3 CHANGELOG.md | grep "### _unreleased_" || (\
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
	sed 's#_unreleased_#@aduh95/Viz.js v$(VIZ_VERSION) ($(shell date +"%Y-%m-%d"))#' \
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
