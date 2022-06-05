#include "main.h"
#include "map.h"

// check if save data exists
static bool *has_save = (bool *)0xa000;    // pointer to memory address
static uint16_t *vals = (int16_t *)0xa001; // 16 bit for p.steps

void load_save_data()
{
  if (has_save[0])
  {
    // starting position for map generation
    p.x[0] = p.x[1] = (uint8_t)vals[0];
    p.y[0] = p.y[1] = (uint8_t)vals[1];

    // player item initialization
    p.steps = vals[2];
    p.hearts = vals[3];
    p.weapons[0] = (int8_t)vals[4];
    p.weapons[1] = (int8_t)vals[5];
    p.gold = (uint8_t)vals[6];
    p.maps = (uint8_t)vals[7];

    // item history data
    for (uint8_t i = 0; i < 255; i++)
      arr_4kb[i] = vals[i + 8];
  }
  else
  {
    // starting position for map generation
    p.x[0] = p.x[1] = p.y[0] = p.y[1] = START_POSITION;

    // player item initialization
    p.steps = p.gold = p.maps = 0;
    p.hearts = 3;
    p.weapons[0] = p.weapons[1] = -1;
  }
}

void save_data()
{
  // save position
  vals[0] = p.x[0];
  vals[1] = p.y[0];

  // save items
  vals[2] = p.steps;
  vals[3] = p.hearts;
  vals[4] = p.weapons[0];
  vals[5] = p.weapons[1];
  vals[6] = p.gold;
  vals[7] = p.maps;

  // save item history
  for (uint8_t i = 8; i < 255; i++)
    vals[i] = arr_4kb[i - 8];

  // save is now true
  has_save[0] = true;
}
