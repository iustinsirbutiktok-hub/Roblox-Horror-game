# The ward: iron bed with restraints, wheelchair, gurney, drip stand,
# privacy screen, bedside locker.
from kit import *  # noqa


@piece("BedsideCabinet", close=((1.6, -2.3, 2.2), (0, -0.3, 1.5), 50))
def bedside_cabinet():
    """a steel bedside locker: drawer, open niche, a door left ajar, on castors"""
    material("locker", "paint", base="#cfc6aa", chip=0.6, rust=0.6, under="#7f9a86", peel=0.55)
    material("locker_in", "paint", base="#b9b096", chip=0.3, rust=0.4, dirt=0.9)
    W, D, z0, z1 = 0.46, 0.40, 0.12, 0.80
    H = z1 - z0
    # the shell
    for s in (-1, 1):
        box((0.014, D, H), (s * (W / 2 - 0.007), 0, z0 + H / 2), m="locker", bevel=0.003)
    box((W, 0.012, H), (0, D / 2 - 0.006, z0 + H / 2), m="locker", bevel=0.002)
    box((W, D, 0.014), (0, 0, z0 + 0.007), m="locker_in")
    box((W + 0.03, D + 0.03, 0.022), (0, -0.005, z1 + 0.011), m="locker", bevel=0.006)
    box((W - 0.03, 0.014, 0.05), (0, -D / 2 + 0.03, z0 + 0.025), m="locker", bevel=0.002)      # kick plate
    # shelves: under the niche, over it, inside the cupboard
    for z in (0.505, 0.645, 0.31):
        box((W - 0.028, D - 0.02, 0.012), (0, 0.005, z), m="locker_in", bevel=0.002)
    # the drawer, pulled out a little
    with place(T((0, -0.035, 0))):
        box((W - 0.03, 0.02, 0.125), (0, -D / 2 + 0.01, 0.722), m="locker", bevel=0.004)
        for s in (-1, 1):
            box((0.01, D - 0.06, 0.09), (s * (W / 2 - 0.03), -0.01, 0.715), m="locker_in")
        sweep([(-0.07, -D / 2 - 0.001, 0.73), (-0.07, -D / 2 - 0.03, 0.73), (0.07, -D / 2 - 0.03, 0.73),
               (0.07, -D / 2 - 0.001, 0.73)], 0.006, "chrome", 6, bend=0.012)
        box((0.07, 0.004, 0.035), (0, -D / 2 - 0.001, 0.69), m="chrome", bevel=0.001)     # card holder
        box((0.06, 0.002, 0.026), (0, -D / 2 - 0.003, 0.69), m="paper")
    # the door, hanging open on its left hinge
    with place(T((-W / 2 + 0.012, -D / 2, 0), (0, 0, -28))):
        box((W - 0.03, 0.018, 0.37), ((W - 0.03) / 2, -0.009, 0.315), m="locker", bevel=0.004)
        box((W - 0.07, 0.006, 0.31), ((W - 0.03) / 2, 0.003, 0.315), m="locker_in")
        cyl(0.012, 0.022, (W - 0.075, -0.03, 0.40), (90, 0, 0), m="chrome", n=10)
        sphere(0.016, (W - 0.075, -0.045, 0.40), m="chrome", n=10, rings=5)
        for z in (0.17, 0.46):
            cyl(0.007, 0.05, (0, -0.012, z), m="chrome", n=6)
    # the niche: an enamel mug, a pill bottle on its side
    lathe([(0, 0.0), (0.04, 0.0), (0.042, 0.004), (0.04, 0.09), (0.036, 0.09), (0.034, 0.008), (0, 0.008)],
          (-0.09, -0.02, 0.511), m="porcelain", n=14)
    sweep([(-0.05, -0.02, 0.585), (-0.03, -0.02, 0.585), (-0.03, -0.02, 0.535), (-0.05, -0.02, 0.535)], 0.005,
          "porcelain", 6, bend=0.015)
    lathe([(0, 0), (0.022, 0), (0.022, 0.06), (0.012, 0.07), (0.012, 0.08), (0, 0.08)],
          (0.08, 0.0, 0.533), (0, 90, 30), m="amber", n=10)
    # inside the cupboard: an old bottle
    lathe([(0, 0), (0.035, 0), (0.035, 0.12), (0.014, 0.15), (0.014, 0.18), (0, 0.18)], (0.09, 0.05, 0.316),
          m="green_glass", n=12)
    # the towel rail down the side
    sweep([(W / 2, -0.12, 0.70), (W / 2 + 0.05, -0.12, 0.70), (W / 2 + 0.05, 0.12, 0.70), (W / 2, 0.12, 0.70)],
          0.008, "chrome", 8, bend=0.02)
    # castors
    for x in (-1, 1):
        for y in (-1, 1):
            caster((x * (W / 2 - 0.05), y * (D / 2 - 0.05), 0), 0.03, swivel=x * 15 + y * 40, stem=0.04)
