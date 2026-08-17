# PIRATE'S FOLLY — procedurally generated pirate exploration for the Game Boy

RGBDS  ?= tools/rgbds/bin/
RGBASM := $(RGBDS)rgbasm
RGBLINK := $(RGBDS)rgblink
RGBFIX := $(RGBDS)rgbfix

SRC := src/main.asm src/joypad.asm src/rng.asm src/tiles.asm src/sail.asm src/world.asm src/port.asm src/save.asm src/combat.asm src/isles.asm src/sound.asm src/sgb.asm
OBJ := $(SRC:src/%.asm=build/%.o)

pirates_folly.gb: $(OBJ)
	$(RGBLINK) -o $@ -n build/pirates_folly.sym -m build/pirates_folly.map -p 0xFF $(OBJ)
	$(RGBFIX) -v -p 0xFF -t "PIRATES FOLLY" -c -m MBC5+RAM+BATTERY -r 2 $@

build/%.o: src/%.asm | build
	$(RGBASM) -o $@ -I include/ -I src/ -Wall -Wextra -Werror=truncation -Werror=unmapped-char -M build/$*.d -MG -MP -MQ $@ $<

# Auto-generated header deps (-M -MG -MP) replace hand-listed prerequisites.

# Regenerate the SGB border data after editing the art (needs numpy):
src/sgb_day.inc: res/sgb_day.png tools/png2sgb.py
	python3 tools/png2sgb.py $< $@ sgb_day 1
src/sgb_night.inc: res/sgb_night.png tools/png2sgb.py
	python3 tools/png2sgb.py $< $@ sgb_night 2

build:
	mkdir -p build

clean:
	rm -rf build pirates_folly.gb

check: pirates_folly.gb
	for t in tests/test_*.py; do echo "== $$t"; python3 "$$t" || exit 1; done
	python3 tests/lint_worlds.py

.PHONY: clean check

-include build/*.d
