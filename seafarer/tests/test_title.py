from pyboy import PyBoy
pb = PyBoy("/home/spencer/Repositories/gb/seafarer/seafarer.gb", window="null")
pb.set_emulation_speed(0)
mem = pb.memory
for _ in range(120): pb.tick()
# title text "SEAFARER" = tiles 58,44,40,45,40,57,44,57 at row 4 col 6
row = [mem[0x9800 + 4*32 + 6 + i] for i in range(8)]
assert row == [58,44,40,45,40,57,44,57], f"title row {row}"
# ship tile on row 13 col 9
assert mem[0x9800 + 13*32 + 9] == 10, "no ship on title"
# press START -> seed editor (digits row 2 = D E A D B E E F)
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(30): pb.tick()
row2 = [mem[0x9800 + 2*32 + 6 + i] for i in range(8)]
assert row2 == [29,30,26,29,27,30,30,31], f"seed row {row2}"
print("TITLE SCREEN OK")
