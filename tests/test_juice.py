"""Tier 1 combat-juice tests: hit flash, sinking animation, splash, muzzle
smoke, screen shake + damage flash, and the harbor bell / port music.

J1  enemy blinks when hit (wEnemyFlash) and slides under when sunk (wSinkT)
J2  firing the cannon puffs smoke; a dying ball splashes
J3  taking a hit shakes the screen and flashes the palette
J4  docking rings the bell and plays the port music (was dead content)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_regress import (boot, new_game, w16, set16, seed16, syms, tile,
                          press3, teleport)

teleport_verified = lambda pb, mem, tx, ty: teleport(pb, tx, ty)


def open_sea_enemy_spot(mem, s16):
    """A water pixel 24 px from the ship (enemy holds at cheb <= 40)."""
    sx, sy = w16(mem, "wShipX"), w16(mem, "wShipY")
    for dx, dy in ((24, 0), (-24, 0), (0, 24), (0, -24), (24, 24), (-24, -24)):
        ex, ey = sx + dx, sy + dy
        if tile(ex >> 3, ey >> 3, s16) < 3:
            return ex, ey
    raise AssertionError("no open-sea enemy spot near spawn")


def place_enemy(mem, ex, ey, hp):
    set16(mem, "wEnemyX", ex << 4)
    set16(mem, "wEnemyY", ey << 4)
    mem[syms["wEnemyHP"]] = hp
    mem[syms["wEnemyFireCool"]] = 75
    mem[syms["wIsGuardian"]] = 0
    mem[syms["wLosT"]] = 16
    mem[syms["wNoLOS"]] = 0
    mem[syms["wEnemyActive"]] = 1


def place_ball_on_enemy(mem):
    mem[syms["wBallPX"]] = mem[syms["wBallPX"]]  # keep linters honest
    for dst, src in (("wBallPX", "wEnemyX"), ("wBallPY", "wEnemyY")):
        mem[syms[dst]] = mem[syms[src]]
        mem[syms[dst] + 1] = mem[syms[src] + 1]
    mem[syms["wBallPVX"]] = 0
    mem[syms["wBallPVY"]] = 0
    mem[syms["wBallPLife"]] = 30
    mem[syms["wBallPActive"]] = 1


def j1_hit_flash_and_sink():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    ex, ey = open_sea_enemy_spot(mem, s16)
    place_enemy(mem, ex, ey, 3)
    place_ball_on_enemy(mem)
    pb.tick()
    assert mem[syms["wEnemyHP"]] == 2, "ball didn't damage the enemy"
    assert mem[syms["wEnemyFlash"]] > 0, "no hit flash on a damaged enemy"
    # now sink her
    mem[syms["wEnemyHP"]] = 1
    place_ball_on_enemy(mem)
    pb.tick()
    assert not mem[syms["wEnemyActive"]], "enemy survived 0 HP"
    assert mem[syms["wSinkT"]] > 0, "sinking animation never started"
    for _ in range(30):
        pb.tick()
    assert mem[syms["wSinkT"]] == 0, "sinking animation never finished"
    pb.stop()
    print("J1 enemy hit flash + sinking animation: OK")


def j2_smoke_and_splash():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    press3(pb, "a")                 # fire ahead (open ocean: no dock)
    for _ in range(2):
        pb.tick()
    assert mem[syms["wBallPActive"]] == 1, "cannon didn't fire"
    assert mem[syms["wSmokeT"]] > 0, "no muzzle smoke on firing"
    # let the ball die in place two frames from now
    mem[syms["wBallPVX"]] = 0
    mem[syms["wBallPVY"]] = 0
    mem[syms["wBallPLife"]] = 2
    for _ in range(4):
        pb.tick()
    assert not mem[syms["wBallPActive"]], "ball never died"
    assert mem[syms["wSplashT"]] > 0, "no splash where the ball fell"
    pb.stop()
    print("J2 muzzle smoke + ball splash: OK")


def j3_shake_and_flash_on_hit():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    hull0 = mem[syms["wHull"]]
    # enemy ball parked on the ship
    mem[syms["wBallEX"]] = mem[syms["wPosX"]]
    mem[syms["wBallEX"] + 1] = mem[syms["wPosX"] + 1]
    mem[syms["wBallEY"]] = mem[syms["wPosY"]]
    mem[syms["wBallEY"] + 1] = mem[syms["wPosY"] + 1]
    mem[syms["wBallEVX"]] = 0
    mem[syms["wBallEVY"]] = 0
    mem[syms["wBallELife"]] = 30
    mem[syms["wDmgCool"]] = 0
    mem[syms["wBallEActive"]] = 1
    pb.tick()
    assert mem[syms["wHull"]] == hull0 - 1, "enemy ball didn't hit"
    assert mem[syms["wShakeT"]] > 0, "no screen shake on hull damage"
    assert mem[syms["wHitFlashT"]] > 0, "no palette flash on hull damage"
    pb.stop()
    print("J3 screen shake + damage flash: OK")


def j4_harbor_bell_and_port_music():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # find any port district with a dockable beach (the boot save's seed
    # varies, so don't hardcode one). A beach counts only if some water
    # tile's first land neighbor in TryDock's N,S,W,E order IS that beach
    # and the beach's district is this one.
    from test_regress import has_port

    def dock_from(dx, dy):
        for ty in range(dy * 4, dy * 4 + 4):
            for tx in range(dx * 4, dx * 4 + 4):
                if tile(tx, ty, s16) < 3:
                    continue
                for ddx, ddy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                    nx, ny = tx + ddx, ty + ddy
                    if not (0 <= nx < 320 and 0 <= ny < 288):
                        continue
                    if tile(nx, ny, s16) >= 3:
                        continue
                    for pdx, pdy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                        if tile(nx + pdx, ny + pdy, s16) >= 3:
                            if (nx + pdx, ny + pdy) == (tx, ty):
                                return (nx, ny)
                            break
        return None

    target = None
    for dy in range(72):
        for dx in range(80):
            if has_port(dx, dy, s16):
                spot = dock_from(dx, dy)
                if spot:
                    target = spot
                    break
        if target:
            break
    assert target, "no port district with a dockable beach in this sea"
    docked = False
    if teleport_verified(pb, mem, *target):
        set16(mem, "wStormT", 0)     # no storm may drift us off the beach
        mem[syms["wEnemyActive"]] = 0
        pb.tick()
        press3(pb, "a")             # dock, catching the bell mid-ring
        pb.tick()
        pb.tick()
        docked = mem[syms["wState"]] == 4
    assert docked, f"docking failed from {target}"
    assert mem[syms["wSfx1T"]] > 0, "harbor bell not ringing on dock"
    assert mem[syms["wSongID"]] == 3, \
        f"port music not playing (song {mem[syms['wSongID']]}, want 3)"
    pb.stop()
    print("J4 harbor bell + port music: OK")


if __name__ == "__main__":
    for fn in (j1_hit_flash_and_sink, j2_smoke_and_splash,
               j3_shake_and_flash_on_hit, j4_harbor_bell_and_port_music):
        fn()
    print("ALL JUICE CHECKS PASSED")
