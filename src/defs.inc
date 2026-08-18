; Shared constants for PIRATE'S FOLLY

; 16-bit pair shifts (pure assembly-time): SR16 logical right, SL16 left.
MACRO SR16            ; \1 = high-byte reg, \2 = low-byte reg, \3 = bits
    REPT \3
    srl \1
    rr \2
    ENDR
ENDM

MACRO SL16            ; \1 = high-byte reg, \2 = low-byte reg, \3 = bits
    REPT \3
    sla \2
    rl \1
    ENDR
ENDM

; CGB VRAM bank select (no-ops to write on DMG: the CGB guards gate these)
MACRO VBK1
    ld a, 1
    ldh [rVBK], a
ENDM

MACRO VBK0
    xor a
    ldh [rVBK], a
ENDM

; --- Game states ---
DEF STATE_EDIT EQU 0        ; seed editor screen
DEF STATE_MAP  EQU 1        ; generated island view (M0, superseded)
DEF STATE_SAIL EQU 2        ; sailing mode
DEF STATE_CHART EQU 3       ; sea chart (map screen)
DEF STATE_PORT EQU 4        ; port menu
DEF STATE_DIG  EQU 5        ; treasure dig scene
DEF STATE_WIN  EQU 6        ; victory screen
DEF STATE_TITLE EQU 7       ; title screen (M6)
DEF STATE_MERCH EQU 8       ; merchant hail: trade or plunder
DEF STATE_SHORE EQU 9       ; exploring land on foot (2x zoom)

; --- Joypad combined-byte masks (bit set = pressed) ---
; bit 7..0 = Down Up Left Right Start Select B A
DEF PADF_DOWN   EQU $80
DEF PADF_UP     EQU $40
DEF PADF_LEFT   EQU $20
DEF PADF_RIGHT  EQU $10
DEF PADF_START  EQU $08
DEF PADF_SELECT EQU $04
DEF PADF_B      EQU $02
DEF PADF_A      EQU $01
DEF DIR_MASK    EQU PADF_UP | PADF_DOWN | PADF_LEFT | PADF_RIGHT

; --- Auto-repeat tuning (frames) ---
DEF REPEAT_DELAY EQU 24
DEF REPEAT_RATE  EQU 6
DEF QUIT_CFM_T   EQU 150    ; B-at-sea quit: confirm window (~2.5 s)

; --- Tile IDs ---
DEF TILE_BLANK    EQU 0
DEF TILE_DEEP     EQU 1
DEF TILE_SHALLOW  EQU 2
DEF TILE_SAND     EQU 3
DEF TILE_GRASS    EQU 4
DEF TILE_FOREST   EQU 5
DEF TILE_MOUNTAIN EQU 6
DEF TILE_CURSOR   EQU 7
DEF TILE_PORT     EQU 13      ; chart port marker (house glyph)
DEF TILE_DOCK     EQU 14      ; in-world dock (planks), replaces sand in port districts
DEF TILE_HEX0     EQU 16      ; hex font occupies tiles 16-31

; --- Ship sprites (8x8, one tile per heading) ---
DEF TILE_SHIP_N   EQU 8
DEF TILE_SHIP_E   EQU 9
DEF TILE_SHIP_S   EQU 10
DEF TILE_SHIP_W   EQU 11

; --- Extra HUD letters (tiles 32+) ---
DEF TILE_LET_X    EQU 32
DEF TILE_LET_Y    EQU 33
DEF TILE_LET_S    EQU 34
DEF TILE_LET_P    EQU 35
DEF TILE_GT       EQU 36      ; '>'
DEF TILE_DOT      EQU 37      ; '.'
DEF TILE_COLON    EQU 38      ; ':'
DEF TILE_SPACE    EQU 39
DEF TILE_A        EQU 40      ; A-Z = 40-65
DEF TILE_SLASH    EQU 66      ; '/'
DEF TILE_BALL     EQU 12      ; cannonball
DEF TILE_SPLASH   EQU 15      ; water splash / powder smoke burst
DEF TILE_SKULL    EQU 68      ; chart: isle with a living guardian

; --- Shore mode tiles (land at 2x zoom) ---
DEF TILE_SH_GRASS  EQU 96
DEF TILE_SH_GRASS2 EQU 97
DEF TILE_SH_TREE   EQU 98
DEF TILE_SH_ROCK   EQU 99
DEF TILE_SH_FLOWER EQU 100
DEF TILE_SH_MTN    EQU 101
DEF TILE_SH_PLAYER EQU 104      ; 104-107: N/E/S/W
DEF TILE_DINGHY    EQU 108
DEF TILE_SITE_CHEST  EQU 109    ; shore site sprites (109-112)
DEF TILE_SITE_DEBRIS EQU 110
DEF TILE_SITE_GIBBET EQU 111
DEF TILE_SITE_SKULL  EQU 112
DEF TILE_DIGX        EQU 113    ; dig site: X marks the spot
DEF TILE_SNAKE       EQU 114    ; shore foes (S3)
DEF TILE_SKEL        EQU 115
DEF TILE_COIN        EQU 116    ; dropped by slain skeletons
DEF TILE_TAVERN      EQU 117    ; port-town buildings (S4)
DEF TILE_MARKET      EQU 118
DEF TILE_SHIPYARD    EQU 119
DEF TILE_HARBOR      EQU 120

; --- Sea-terrain visual variants (render-only) ---
; Picked by DecorateTile (world.asm) in the staging path; WorldTile still
; returns canonical IDs, so collision/chart/logic never see these.
DEF TILE_SHALLOW2 EQU 121     ; foam-flecked shallow (sand-approach band)
DEF TILE_SAND2    EQU 122     ; shells-and-pebbles sand
DEF TILE_GRASS2   EQU 123     ; flowered grass
DEF TILE_FOREST2  EQU 124     ; sparse canopy

; --- Synthesized transition tiles (tile mixing, LoadTiles) ---
; 4x4 Bayer-dither blends of parent pairs, built at boot by MixTile.
; 50/50 tiles are shared by both sides of their boundary.
DEF TILE_DEEP_SH25 EQU 125    ; deep 75 / shallow 25   (e 128-129)
DEF TILE_DEEP_SH50 EQU 126    ; deep/shallow 50/50     (e 130-131, 134-135)
DEF TILE_SH_DEEP25 EQU 127    ; shallow 75 / deep 25   (e 132-133)
DEF TILE_SH_SAND50 EQU 129    ; shallow/sand 50/50     (e 146-147, 150-151)
DEF TILE_SAND_SH25 EQU 130    ; sand 75 / shallow 25   (e 148-149)
DEF TILE_SAND_GR25 EQU 131    ; sand 75 / grass 25     (e 154-155)
DEF TILE_SAND_GR50 EQU 132    ; sand/grass 50/50       (e 156-157, 160-161)
DEF TILE_GR_SAND25 EQU 133    ; grass 75 / sand 25     (e 158-159)

; --- Screen-dressing glyphs (phase 7) ---
DEF TILE_COMPASS   EQU 134    ; compass rose (chart header)
DEF TILE_GULL      EQU 135    ; gull arcs (title screen)
DEF TILE_FRAME     EQU 136    ; thin rule (port screen frame)
DEF TILE_DEEP2     EQU 137    ; second animated deep-water variant
DEF TILE_SHALLOW3  EQU 138    ; second animated shallow-water variant
DEF TILE_EMBLEM    EQU 139    ; 139-154: title skull & crossbones (4x4)

; --- Port towns (S4) ---
; In a port district, four buildings spawn at hashed spots: tavern,
; market, shipyard, harbor. Each opens the matching port screen.
DEF BLDG_TAVERN  EQU 0
DEF BLDG_MARKET  EQU 1
DEF BLDG_SHIPYARD EQU 2
DEF BLDG_HARBOR  EQU 3
DEF BLDG_SALT    EQU $B17E

; --- Shore sites (hash-placed loot & lore landmarks) ---
; Two consumable slots per chart cell (dug bitmap: bit = cell*2+slot);
; landmarks are rarer and never consumed. Position/loot/type are pure
; functions of seed + cell + slot. Python mirrors: tests/test_shore.py.
DEF SITE_CHEST   EQU 1
DEF SITE_DEBRIS  EQU 2
DEF SITE_GIBBET  EQU 3
DEF SITE_SKULL   EQU 4
DEF SITE_DIG     EQU 5          ; isle dig site (X): guardian dead, fragment undug
DEF SITE_SALT0   EQU $3D09
DEF SITE_SALT1   EQU $A23E
DEF SITE_SALT2   EQU $5A3C
DEF LAND_SALT    EQU $7B1E
DEF DIG_SALT     EQU $D1C6      ; isle dig-site placement (xored with the isle index)

; --- Shore foes (S3) ---
; Two spawn slots per chart cell, hash-placed like the loot sites. Snakes
; slither in the meadows (1 HP), skeletons shamble on the sand (2 HP,
; drop a coin). Foes respawn when their cell re-enters the active set —
; the island restocks. Python mirror: tests/test_shore.py.
DEF FOE_SNAKE    EQU 1
DEF FOE_SKEL     EQU 2
DEF FOE_SALT0    EQU $6B1D
DEF FOE_SALT1    EQU $E492
DEF FOE_RANGE    EQU 80         ; foes approach inside this range (px)
DEF FOE_GONE     EQU 200        ; despawn beyond this (px)
DEF SH_HEARTS    EQU 3          ; hearts per landing
DEF COLLAPSE_TOLL EQU 15        ; gold the island takes when you drop

; --- Shore mode geometry (2x the ocean, same lattice) ---
DEF SHORE_W       EQU 640       ; tiles (2x WORLD_W)
DEF SHORE_H       EQU 576       ; tiles (2x WORLD_H)
DEF SH_CAM_MAX_X  EQU 4960      ; camera clamp: keeps tileX+20 <= 640
DEF SH_CAM_MAX_Y  EQU 4464      ; camera clamp: keeps tileY+18 <= 576

; --- Ports & economy (M3) ---
DEF PMAIN    EQU 0
DEF PTRADE   EQU 1
DEF PTAVERN  EQU 2
DEF PREPAIR  EQU 3
DEF PRECRUIT EQU 4
DEF PSAVED   EQU 5
DEF PSHIPYARD EQU 6
DEF PORT_SALT  EQU $7E55      ; district hash salt
DEF HULL_MAX   EQU 20
DEF CREW_MAX   EQU 20
DEF GOLD_START EQU 50
DEF CARGO_MAX  EQU 50         ; total cargo capacity
DEF REPAIR_COST EQU 2         ; gold per hull point
DEF RECRUIT_COST EQU 5        ; gold per crew

; --- Sound (sound.asm) ---
DEF SONG_NONE   EQU 0
DEF SONG_TITLE  EQU 1
DEF SONG_SAIL   EQU 2
DEF SONG_PORT   EQU 3
DEF SONG_BATTLE EQU 4
DEF JINGLE_DIG  EQU 5
DEF JINGLE_WIN  EQU 6
DEF JINGLE_WRECK EQU 7

DEF SFX_CANNON  EQU 1
DEF SFX_HIT     EQU 2
DEF SFX_SPLASH  EQU 3
DEF SFX_STORM   EQU 4
DEF SFX_WRECK   EQU 5
DEF SFX_SINK    EQU 6
DEF SFX_COIN    EQU 7
DEF SFX_BELL    EQU 8
DEF SFX_KNOCK   EQU 9

; --- Combat difficulty (tuned via tests/tune_balance.py duel data) ---
DEF PIRATE_HP       EQU 3
DEF PIRATE_FIRECOOL EQU 75      ; frames between pirate volleys
DEF GUARD_HP        EQU 5
DEF GUARD_FIRECOOL  EQU 50      ; guardians shoot ~1.5x faster

; --- Encounter rolls (combat.asm SpawnCheck / RevisitRoll) ---
; One 16-bit hash/RNG roll is split into lanes: l picks pirate/merchant,
; h picks storm/kraken. Revisit widths are ~1/4 of the new-cell rates
; (except the kraken, already vanishingly rare). The Python world models
; in tests/ mirror these exactly.
DEF ENC_SALT        EQU $C37A   ; encounter hash salt
DEF ENC_PIRATE_NEW  EQU 48      ; new cell: pirate ~19%
DEF ENC_MERCH_NEW   EQU 20      ; merchant lane width above the pirate lane
DEF ENC_STORM_NEW   EQU 13      ; storm ~5%
DEF ENC_KRAKEN_W    EQU 2       ; kraken lane width above the storm lane
DEF ENC_PIRATE_REV  EQU 12      ; revisited cell: pirate ~4.7%
DEF ENC_MERCH_REV   EQU 5       ; merchant ~2%
DEF ENC_STORM_REV   EQU 3       ; storm ~1.2%

; --- Enemy AI / merchant behavior ---
DEF ENEMY_HOLD_RANGE EQU 40     ; approach until Chebyshev range <= this
DEF ENEMY_FIRE_RANGE EQU 90     ; open fire inside this range
DEF ENEMY_GIVE_UP    EQU 121    ; despawn when farther than this (px, either axis)
DEF MERCH_HAIL_RANGE EQU 20     ; merchant hails inside this range
DEF MERCH_GONE_RANGE EQU 141    ; merchant leaves when farther than this
DEF MERCH_TIME       EQU 900    ; merchant despawn timer (~15 s)

; --- Final battle state (wFinal; 1-4 = wave to spawn) ---
DEF FINAL_NONE        EQU 0
DEF FINAL_ALL_SPAWNED EQU 5
DEF FINAL_DONE        EQU 6

; --- Sailing physics ---
DEF SAIL_MAX_VEL  EQU 40      ; velocity cap, 1/16 px/frame (= 2.5 px/frame)
DEF SAIL_CAM_MAX_X EQU 2392   ; camera clamp: keeps tileX+20 <= 319
DEF SAIL_CAM_MAX_Y EQU 2152   ; camera clamp: keeps tileY+18 <= 287

; --- World (M2: on-demand procedural ocean) ---
DEF WORLD_W      EQU 320      ; tiles (16 cells of 20)
DEF WORLD_H      EQU 288      ; tiles (16 cells of 18)
DEF SHIP_MAX_X   EQU 2559     ; px
DEF SHIP_MAX_Y   EQU 2303     ; px

; --- Terrain thresholds for elevation e in [0,255] (tune me!) ---
DEF E_DEEP_MAX    EQU 132     ; e < 132: deep water
DEF E_SHALLOW_MAX EQU 148     ; shallow water
DEF E_SAND_MAX    EQU 158     ; beach
DEF E_GRASS_MAX   EQU 205     ; grass; above: forest/mountain sprinkle

