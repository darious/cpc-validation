# Builds the CPCEC adapter from an unmodified CPCEC checkout.
#
#   make                      # expects ../../../cpcec (sibling of cpc-validation)
#   make CPCEC_DIR=/path/to/cpcec
#
# Output: build/cpc-runner-cpcec plus copies of CPCEC's firmware ROMs, which
# CPCEC loads from the directory containing its executable.

CPCEC_DIR ?= ../../../cpcec
CC ?= gcc
CFLAGS ?= -O2
SDL_CFLAGS := $(shell sdl2-config --cflags 2>/dev/null)
SDL_LIBS := $(shell sdl2-config --libs 2>/dev/null || echo -lSDL2)

ROMS := cpc464.rom cpc664.rom cpc6128.rom cpcplus.rom cpcados.rom

BIN := build/cpc-runner-cpcec

all: $(BIN) $(addprefix build/,$(ROMS))

$(BIN): runner.c $(wildcard $(CPCEC_DIR)/*.c) $(wildcard $(CPCEC_DIR)/*.h) | build
	$(CC) $(CFLAGS) -DSDL2 -w $(SDL_CFLAGS) -I$(CPCEC_DIR) runner.c -o $@ $(SDL_LIBS) -lm

build/%.rom: $(CPCEC_DIR)/%.rom | build
	cp $< $@

build:
	mkdir -p build

clean:
	rm -rf build

.PHONY: all clean
