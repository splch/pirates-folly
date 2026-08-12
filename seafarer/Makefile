# SEAFARER — procedurally generated pirate exploration (M0: generator demo)

RGBDS  ?= ../tools/rgbds/bin/
RGBASM := $(RGBDS)rgbasm
RGBLINK := $(RGBDS)rgblink
RGBFIX := $(RGBDS)rgbfix

SRC := src/main.asm src/joypad.asm src/rng.asm src/tiles.asm src/sail.asm src/world.asm src/port.asm src/combat.asm src/isles.asm src/sound.asm
OBJ := $(SRC:src/%.asm=build/%.o)

seafarer.gb: $(OBJ)
	$(RGBLINK) -o $@ -n build/seafarer.sym -m build/seafarer.map -p 0xFF $(OBJ)
	$(RGBFIX) -v -p 0xFF -t SEAFARER -c -m MBC5+RAM+BATTERY -r 3 $@

build/%.o: src/%.asm src/defs.inc src/testmap.inc include/hardware.inc | build
	$(RGBASM) -o $@ -I include/ -I src/ -Wall $<

build:
	mkdir -p build

clean:
	rm -rf build seafarer.gb

.PHONY: clean
