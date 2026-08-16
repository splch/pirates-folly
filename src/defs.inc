; Shared constants for PIRATE'S FOLLY

; --- Game states ---
DEF STATE_EDIT EQU 0        ; seed editor screen
DEF STATE_MAP  EQU 1        ; generated island view (M0, superseded)
DEF STATE_SAIL EQU 2        ; sailing mode
DEF STATE_CHART EQU 3       ; sea chart (map screen)
DEF STATE_PORT EQU 4        ; port menu
DEF STATE_DIG  EQU 5        ; treasure dig scene
DEF STATE_WIN  EQU 6        ; victory screen
DEF STATE_TITLE EQU 7       ; title screen (M6)

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

; --- Ports & economy (M3) ---
DEF PMAIN    EQU 0
DEF PTRADE   EQU 1
DEF PTAVERN  EQU 2
DEF PREPAIR  EQU 3
DEF PRECRUIT EQU 4
DEF PSAVED   EQU 5
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

