PREFIX_FULL = $(abspath ./prefix-full)
PREFIX_LITE = $(abspath ./prefix-lite)

VIZ_VERSION = $(shell node -p "require('./package.json').version")
EXPAT_VERSION = 2.2.9
GRAPHVIZ_VERSION = 2.43.20200109.0924
EMSCRIPTEN_VERSION = 1.38.44

EXPAT_SOURCE_URL = "https://github.com/libexpat/libexpat/releases/download/R_2_2_9/expat-2.2.9.tar.bz2"
GRAPHVIZ_SOURCE_URL = "https://gitlab.com/graphviz/graphviz/-/archive/f4e30e65c1b2f510412d62e81e30c27dd7665861/graphviz-f4e30e65c1b2f510412d62e81e30c27dd7665861.tar.gz"

.PHONY: all deps deps-full deps-lite clean clobber expat–full graphviz-full graphviz-lite


all: src/render.js src/render.wasm

debug:
	mkdir -p $@
	rm -rf $@/*
	$(MAKE) debug/out.js

debug/out.js: src/viz.cpp
	EMCC_DEBUG=1 emcc --bind -g4 -o $@ $< -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

deps: expat-full graphviz-full

clean:
	rm -f build-full/module.js build-full/pre.js full.render.js

clobber: | clean
	rm -rf build-main build-full build-lite $(PREFIX_FULL) $(PREFIX_LITE)

src/render.js: src/boilerplate/module-header.txt build-full/render.js
	sed -e s/{{VIZ_VERSION}}/$(VIZ_VERSION)/ -e s/{{EXPAT_VERSION}}/$(EXPAT_VERSION)/ -e s/{{GRAPHVIZ_VERSION}}/$(GRAPHVIZ_VERSION)/ -e s/{{EMSCRIPTEN_VERSION}}/$(EMSCRIPTEN_VERSION)/ $^ > $@
	mv build-full/render.wasm src/render.wasm

build-full/render.js: src/viz.cpp
	emcc --version | grep $(EMSCRIPTEN_VERSION)
	emcc --bind -Oz -o $@ $< -I$(PREFIX_FULL)/include -I$(PREFIX_FULL)/include/graphviz -L$(PREFIX_FULL)/lib -L$(PREFIX_FULL)/lib/graphviz -lgvplugin_core -lgvplugin_dot_layout -lgvplugin_neato_layout -lcgraph -lgvc -lgvpr -lpathplan -lexpat -lxdot -lcdt

$(PREFIX_FULL):
	mkdir -p $(PREFIX_FULL)

expat-full: | build-full/expat-$(EXPAT_VERSION) $(PREFIX_FULL)
	grep $(EXPAT_VERSION) build-full/expat-$(EXPAT_VERSION)/expat_config.h
	cd build-full/expat-$(EXPAT_VERSION) && emconfigure ./configure --quiet --disable-shared --prefix=$(PREFIX_FULL) --libdir=$(PREFIX_FULL)/lib CFLAGS="-Oz -w"
	cd build-full/expat-$(EXPAT_VERSION) && emmake make --quiet -C lib all install

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
