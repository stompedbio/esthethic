"""Python port of the Shadow logic in skeed.lua (same formulas), unit tested.
Keep in sync with the Shadow table in skeed.lua."""
import math, unittest

def wrap(d): return (d + 180) % 360 - 180

class Rec:
    def __init__(s):
        s.side=0; s.lastFlip=0; s.ints=[]; s.des=0; s.ema=0; s.api=0
        s.apiMin=1e9; s.apiMax=-1e9; s.n=0; s.apiOff=0; s.state="Stand"; s.flips=0

def update(r, eye, feet, api, now, state=None):
    des = wrap(feet - eye); r.des = des
    r.ema = r.ema*0.97 + abs(des)*0.03; r.n += 1
    r.state = state or r.state
    if api is not None:
        r.api = api; r.apiMin = min(r.apiMin, api); r.apiMax = max(r.apiMax, api)
        if abs(abs(api) - abs(des)) > 25: r.apiOff += 1
    side = 1 if des > 10 else (-1 if des < -10 else 0)
    if side != 0:
        if r.side == 0: r.lastFlip = now
        elif side != r.side:
            r.ints.append(now - r.lastFlip)
            if len(r.ints) > 12: r.ints.pop(0)
            r.flips += 1; r.lastFlip = now
        r.side = side

def pattern(r, now):
    n = len(r.ints)
    if n < 4: return "learning", None
    mean = sum(r.ints)/n
    std = math.sqrt(sum((i-mean)**2 for i in r.ints)/n)
    if mean <= 2.3: label = "per-tick jitter"
    elif std <= 1.2: label = "fixed ~%.0ft" % mean
    else: label = "variable %.0f+-%.0ft" % (mean, std)
    return label, max(0, math.floor(mean - (now - r.lastFlip) + 0.5))

def pick(r, now, lead, maxOff):
    if r.side == 0: return None
    label, nxt = pattern(r, now)
    side, src = r.side, "read"
    if nxt is not None and nxt <= lead: side, src = -r.side, "pred"
    mag = min(max(abs(r.des), r.ema), maxOff)
    return dict(side=side, off=math.floor(side*mag+0.5), src=src, pat=label)

def feed_flip(r, every, count, amount=58):
    """enemy flips side every `every` ticks"""
    t = 0; s = 1
    for _ in range(count):
        for _ in range(every):
            update(r, 0, s*amount, None, t); t += 1
        s = -s
    return t

class T(unittest.TestCase):
    def test_wrap(self):
        self.assertEqual(wrap(190), -170); self.assertEqual(wrap(-190), 170); self.assertEqual(wrap(0), 0)

    def test_side_read(self):
        r = Rec(); update(r, 10, 70, None, 0); self.assertEqual(r.side, 1)
        update(r, 10, -50, None, 1); self.assertEqual(r.side, -1)

    def test_small_delta_no_side(self):
        r = Rec(); update(r, 0, 5, None, 0); self.assertEqual(r.side, 0)
        self.assertIsNone(pick(r, 1, 1, 58))

    def test_wrap_around_feet(self):
        r = Rec(); update(r, 170, -150, None, 0)       # feet is 40 deg past eye across the seam
        self.assertEqual(round(r.des), 40); self.assertEqual(r.side, 1)

    def test_learning_needs_four_flips(self):
        r = Rec(); feed_flip(r, 4, 4); self.assertEqual(pattern(r, 20)[0], "learning")

    def test_fixed_pattern(self):
        r = Rec(); t = feed_flip(r, 8, 8)
        self.assertTrue(pattern(r, t)[0].startswith("fixed ~8t"))

    def test_per_tick_jitter(self):
        r = Rec(); t = feed_flip(r, 1, 20)
        self.assertEqual(pattern(r, t)[0], "per-tick jitter")

    def test_predicts_flip_before_shot(self):
        r = Rec(); t = feed_flip(r, 8, 8)               # flips every 8 ticks, 8 flips
        now = r.lastFlip + 7                            # one tick before the next flip
        p = pick(r, now, 2, 58)
        self.assertEqual(p["src"], "pred"); self.assertEqual(p["side"], -r.side)

    def test_keeps_read_side_when_flip_far(self):
        r = Rec(); feed_flip(r, 8, 8)
        p = pick(r, r.lastFlip + 1, 2, 58)
        self.assertEqual(p["src"], "read"); self.assertEqual(p["side"], r.side)

    def test_offset_clamped(self):
        r = Rec(); update(r, 0, 86, None, 0)
        self.assertEqual(pick(r, 1, 1, 40)["off"], 40)

    def test_api_constant_84_detected(self):
        r = Rec()
        for i in range(20): update(r, 0, (58 if i % 2 else -58), 84, i)
        self.assertEqual((r.apiMin, r.apiMax), (84, 84)); self.assertGreater(r.apiOff, 0)

if __name__ == "__main__": unittest.main()
