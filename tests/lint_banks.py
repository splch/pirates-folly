"""Bank-discipline lint: shore.asm lives in ROMX bank 4 and must not make
DIRECT calls/jumps to bank-3 code (a wrong-bank call silently executes the
other bank's bytes). Bank-3 services must go through FarCall3.

Every external call/jp target in shore.asm must resolve to ROM0, HRAM, or
bank 4. Run after the build (make check runs it).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SYM = ROOT / "build" / "pirates_folly.sym"

banks = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2:
        banks[p[1]] = int(p[0].split(":")[0], 16)

bad = []
src = open(ROOT / "src" / "shore.asm").read()
for m in re.finditer(r"^\s*(?:call|jp)\s+([A-Za-z_][A-Za-z0-9_]*)", src, re.M):
    tgt = m.group(1)
    if tgt in banks and banks[tgt] not in (0, 4):  # ROM0 or our own bank only
        bad.append((tgt, banks[tgt]))
# HRAM labels live at $FF80+ (bank field 0); VRAM-addressed helpers too.
if bad:
    for t, b in bad:
        print(f"shore.asm calls bank-{b} code directly: {t} — use FarCall3", file=sys.stderr)
    sys.exit(1)
print("bank lint: shore.asm direct calls all land in ROM0/bank 4: OK")
