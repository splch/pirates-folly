#ifndef CONFIG
#define CONFIG

#include <gb/gb.h>

extern const UINT8 sprite_size = 8;
extern const UINT8 screen_x = 160;
extern const UINT8 screen_y = 144;

extern UINT8 SEED = 57;

// map[screen_x / sprite_size][screen_y / sprite_size]
extern unsigned char map[20][18];

extern struct player {
  UINT8 x[2], y[2];
  UINT8 steps;
  INT8 weapons[2];
  UINT8 gold, maps;
} p;

extern UINT16 start_time;
extern UINT8 start_position = 127;

extern const UINT8 scale = 2;

#endif