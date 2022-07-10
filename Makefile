DEPS_FOLDER = $(abspath ./build-deps)
DIST_FOLDER = $(abspath ./dist)
PREFIX_FULL = $(abspath ./prefix-full)

NODE ?= node

EMSCRIPTEN_VERSION = 3.1.12
EXPAT_VERSION = 2.4.8
GRAPHVIZ_VERSION = 5.0.0
VIZ_VERSION ?= $(shell $(NODE) -p "require('./package.json').version")+$(shell git rev-parse HEAD)

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_$(subst .,_,$(EXPAT_VERSION))/expat-$(EXPAT_VERSION).tar.xz"
GRAPHVIZ_SOURCE_URL = "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/$(GRAPHVIZ_VERSION)/graphviz-$(GRAPHVIZ_VERSION).tar.xz"

USE_CLOSURE ?= 1

EMCONFIGURE ?= emconfigure
CC_FLAGS = -c
CC_INCLUDES = -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz
LINK_FLAGS = --bind -s ALLOW_MEMORY_GROWTH=1 -s DYNAMIC_EXECUTION=$(USE_CLOSURE) --closure $(USE_CLOSURE) -g1
LINK_INCLUDES = -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

COREPACK ?= $(NODE) $(shell which corepack)
YARN ?= $(COREPACK) yarn

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
SEMVER ?= $(YARN) semver

DIST_FILES = $(shell $(NODE) -p 'require("./package.json").files.join(" ")')
.PHONY: all
all: $(DIST_FILES) | $(DEPS_FOLDER)

.PHONY: deps
deps: expat-full graphviz-full

.NOTPARALLEL: node_modules
node_modules: $(YARN_PATH) | yarn.lock
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

ifdef USE_TARBALL
$(DIST_FILES) $(DEPS_FOLDER): unpack
	$(warning Build is disabled when using tarball)

.PHONY: unpack
unpack: .unpack-stamp
.unpack-stamp:
	tar -xzf $(USE_TARBALL) --strip-components 1
else
$(DEPS_FOLDER):
	$(error You must run `emmake make deps` first.)

$(DEPS_FOLDER)/package.json:
	echo '{ "type": "commonjs" }' > $@

async/index.js sync/index.js: %/index.js: | %
	echo "module.exports=require('../dist/render_$(@D).cjs')" > $@
async/index.d.ts sync/index.d.ts: %/index.d.ts: dist/render_%.d.ts | %
	echo "export {default} from '../dist/render_$(@D)'" > $@

wasm worker:
	echo "throw new Error('The bundler you are using does not support package.json#exports.')" > $@


dist/index.d.ts dist/render_async.d.ts dist/render_sync.d.ts: dist/%.d.ts: src/%.ts node_modules/typescript | dist
	$(TSC) $(TS_FLAGS) --outDir $(@D) -d --emitDeclarationOnly $<

dist/types.d.ts: src/types.d.ts | dist
	cp $< $@

dist/index.mjs: build/index.js node_modules/terser | dist
	$(TERSER) --module $< > $@

dist/index.cjs: src/index.cjs node_modules/terser | dist
	$(TERSER) --toplevel $< > $@

dist/render.browser.js: DEFINES=\
		-d ENVIRONMENT_HAS_NODE=false -d ENVIRONMENT_IS_NODE=false \
		-d ENVIRONMENT_IS_WEB=true -d ENVIRONMENT_IS_WORKER=true \

dist/render.node.mjs: DEFINES=\
		-d ENVIRONMENT_HAS_NODE=true -d ENVIRONMENT_IS_NODE=true \
		-d ENVIRONMENT_IS_WEB=false -d ENVIRONMENT_IS_WORKER=false \

dist/render.browser.js dist/render.node.mjs: dist/%: build/% node_modules/terser | dist
	$(TERSER) --module $(DEFINES) $<> $@

dist/render.wasm: build/render.wasm | dist
	cp $< $@

dist/render_async.cjs: build/render_async.js node_modules/terser | dist
	sed 's/export default/module.exports=/' $< | $(TERSER) --toplevel > $@
dist/render_sync.cjs: build/render_sync.js build/asm build/viz_wrapper.js node_modules/rollup node_modules/terser | dist
	$(ROLLUP) -f commonjs --exports default $< | $(TERSER) --toplevel > $@
endif

build/viz_wrapper.js build/worker.js build/index.js build/render_async.js build/render_sync.js: build/%.js: src/%.ts node_modules/typescript | build
	$(TSC) $(TS_FLAGS) --outDir $(@D) -m es2020 --target esnext $<

test/deno-files/index.d.ts: dist/index.d.ts
	sed '\,^///, d;/as NodeJSWorker/ d;s#"./types";#"../../dist/types.d.ts";#' $< > $@
	echo "declare type NodeJSWorker=never;" >> $@

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

build/render.wasm: build/browser/render.wasm build/node/render.wasm
	@cmp $^ || (\
		echo "WASM files differ" && false \
	)
	cp $< $@

build/browser/render.wasm build/node/render.wasm: build/%/render.wasm: build/%/render.mjs
	[ -f '$@' ] || ($(RM) $^ && $(MAKE) $@)
	touch $@

build/render.o: src/viz.cpp | build
	@$(CC) --version | grep $(EMSCRIPTEN_VERSION) || (\
		echo "" && \
		echo "" && \
		echo "Required version of emcc not detected. Expected '$(EMSCRIPTEN_VERSION)', got:" && \
		echo "" && \
		$(CC) --version && \
		echo "" && \
		echo "\033[3mHint: make sure you are using use \033[0memmake make …\033[3m.\033[0m" && \
		echo "Install version $(EMSCRIPTEN_VERSION), or override the EMSCRIPTEN_VERSION variable in the Makefile." && \
		echo "Aborting." && false \
	)
	$(CC) $(CC_FLAGS) -o $@ $< $(CC_INCLUDES)

build/asm.js build/asm: USE_CLOSURE:=0
build/asm.js: LINK_FLAGS+= -s WASM=0 -s WASM_ASYNC_COMPILATION=0 -s TEXTDECODER=1 --memory-init-file 0
build/node/render.mjs: LINK_FLAGS+= -s USE_ES6_IMPORT_META=0
build/browser/render.mjs: | build/browser
build/node/render.mjs: | build/node
build/asm.js build/node/render.mjs: ENVIRONMENT:=node
build/browser/render.mjs: ENVIRONMENT:=worker
build/node/render.mjs build/browser/render.mjs build/asm.js: build/render.o
	@$(CC) --version | grep $(EMSCRIPTEN_VERSION) || (\
		echo "" && \
		echo "" && \
		echo "Required version of emcc not detected. Expected '$(EMSCRIPTEN_VERSION)', got:" && \
		echo "" && \
		$(CC) --version && \
		echo "" && \
		echo "\033[3mHint: make sure you are using use \033[0memmake make …\033[3m.\033[0m" && \
		echo "Install version $(EMSCRIPTEN_VERSION), or override the EMSCRIPTEN_VERSION variable in the Makefile." && \
		echo "Aborting." && false \
	)
	$(CC) $(LINK_FLAGS) -s ENVIRONMENT=$(ENVIRONMENT) -Oz -o $@ $< $(LINK_INCLUDES)

build/asm: CJS2ESM:= 's/(module.exports[[:space:]]*=/false;export default(/'
build/asm: build/asm.js
	# Creates an ES2015 module from emcc asm.js
	# Don't use any extension to match TS resolution
	$(if $(subst 0,,$(USE_CLOSURE)), \
		sed -e $(CJS2ESM) $<, \
		echo ";export default Module" | cat $< -\
	) > $@

async build build/node build/browser dist $(PREFIX_FULL) sources sync:
	mkdir -p $@

.PHONY: expat–full
expat-full: $(DEPS_FOLDER)/expat-$(EXPAT_VERSION) | $(PREFIX_FULL) $(DEPS_FOLDER)/package.json
	grep -q $(EXPAT_VERSION) $</expat_config.h
	cd $< && $(EMCONFIGURE) ./configure --quiet --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(MAKE) --quiet -C lib all install

.PHONY: graphviz-full
graphviz-full: $(DEPS_FOLDER)/graphviz-$(GRAPHVIZ_VERSION) | $(PREFIX_FULL) $(DEPS_FOLDER)/package.json
	grep -q $(GRAPHVIZ_VERSION) $</graphviz_version.h
	cd $< && $(EMCONFIGURE) ./configure --quiet --without-sfdp --disable-ltdl --enable-static --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd $< && $(MAKE) --quiet lib plugin
	cd $</lib && $(MAKE) --quiet install
	cd $</plugin && $(MAKE) --quiet install


$(DEPS_FOLDER)/expat-$(EXPAT_VERSION) $(DEPS_FOLDER)/graphviz-$(GRAPHVIZ_VERSION): $(DEPS_FOLDER)/%: sources/%.tar.xz
	mkdir -p $@
	tar -xJf $< --strip-components 1 -C $@

sources/graphviz-$(GRAPHVIZ_VERSION).tar.xz: SOURCE=$(GRAPHVIZ_SOURCE_URL)
sources/expat-$(EXPAT_VERSION).tar.xz: SOURCE=$(EXPAT_SOURCE_URL)
sources/expat-$(EXPAT_VERSION).tar.xz sources/graphviz-$(GRAPHVIZ_VERSION).tar.xz $(YARN_PATH):
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
	cp .yarnrc.yml $(TMP)/$@/.yarnrc.yml
	$(NODE) -p '({packageManager}=require("./package.json")),JSON.stringify({packageManager})' > $(TMP)/$@/package.json
	cp $< $(TMP)/viz.js.tar.gz
	cd $(TMP)/$@ && $(YARN) add $(TMP)/viz.js.tar.gz
	cp test/integration.ts $(TMP)/$@/
	$(TSC) --noEmit $(TMP)/$@/integration.ts

test/deno-files/render.wasm.arraybuffer.js: dist/render.wasm
	echo "export default Uint16Array.from([" > $@ && \
	hexdump -v -x $< | awk '$$1=" "' OFS=",0x" >> $@ && \
	echo "]).buffer.slice(2,$(shell wc -c $< | awk '{if (int($$1) % 2) print "-1"}'))" >> $@

.PHONY: test-deno
ifdef DENO
test-deno: test/deno-files/render.wasm.arraybuffer.js test/deno-files/index.d.ts | $(DIST_FILES)
	$(DENO) test \
		--unstable --importmap=test/deno-files/importmap.json --allow-read\
		-r test/deno.ts
else
test-deno:
	$(warning Deno tests are disabled by environment.)
endif

.PHONY: pack
pack: sources/viz.js-v$(VIZ_VERSION).tar.gz
sources/viz.js-v$(VIZ_VERSION).tar.gz: $(DIST_FILES) | $(YARN_PATH) sources
	$(YARN) pack -o $@

.PHONY: publish
publish: CURRENT_VIZ_VERSION=$(shell $(NODE) -p "require('./package.json').version")
publish: | $(YARN_PATH)
ifeq "$(origin VIZ_VERSION)" "file"
	$(error You must define a new version number.)
endif
	@echo "Checking for clean git stage..."
	@git diff --exit-code --quiet . || (\
		echo "Working directory contains unstaged changes:" && \
		git status --untracked-files=no --porcelain && \
		echo "Stage, commit, stash, or discard those changes before publishing a new version." && \
		false \
	)
	@echo "Checking for version number..."
	@$(NODE) -e \
		"require('semver/functions/gt')('$(VIZ_VERSION)', '$(CURRENT_VIZ_VERSION)') || process.exit(1)" || \
		(\
		echo "You must specify a valid version number. Aborting." && \
		echo "\033[3mHint: use \033[0mmake $@/patch\033[3m to create a patch release.\033[0m" >&2 && \
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
	git commit -S -m "v$(VIZ_VERSION)"
	git tag -s "v$(VIZ_VERSION)"
	@echo "Publishing new version to npm registery..."
	$(YARN) npm publish --access public
	@echo "Pushing new version to git repository..."
	git push && git push --tags

.PHONY: publish/%
publish/%: NEW_VIZ_VERSION=$(shell $(SEMVER) $(VIZ_VERSION) -i $(@F))
publish/%:
	$(info Publishing a new $(@F) release for @aduh95/viz.js…)
	$(info $(VIZ_VERSION) -> $(NEW_VIZ_VERSION))
	@VIZ_VERSION=$(NEW_VIZ_VERSION) $(MAKE) publish
