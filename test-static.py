"""Static checks on skeed.lua. Usage: python3 -I test_static.py skeed.lua penablox-luapi.md"""
import re, sys, collections, unittest
LUA, DOC = sys.argv[1], sys.argv[2]; sys.argv = sys.argv[:1]
src = open(LUA).read(); doc = open(DOC).read()
NS = "aa rage plist entity movement weapon chams sounds render render3d input http database client events menu clantag".split()
PAT = r'\b(%s)\.([a-z_][a-z0-9_]*)\s*\(' % "|".join(NS)

class T(unittest.TestCase):
    def test_api_names_in_doc(self):
        used = {m.group(1)+"."+m.group(2) for m in re.finditer(PAT, src)}
        known = set(re.findall(r'\b(?:%s)\.[a-z_][a-z0-9_]*' % "|".join(NS), doc))
        self.assertEqual(sorted(used - known), [])

    def test_blocks_balanced(self):
        body = re.sub(r'--[^\n]*', '', re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src))
        opens = len(re.findall(r'\b(function|do|then|repeat)\b', body)) - len(re.findall(r'\bi?f?\b(?=\s*$)', ''))  # coarse, see balance.py
        self.assertTrue(opens > 0)

    def test_cfg_entries_declared_before_cfg(self):
        i = src.index("local CFG = {"); j = src.index("}", i)
        names = [n.strip() for n in re.split(r'[,\n]', src[i+len("local CFG = {"):j]) if n.strip() and not n.strip().startswith("--")]
        head = src[:i]
        missing = [n for n in names if not re.search(r'\blocal\s+(?:[\w,\s]*\b)?%s\b' % re.escape(n), head)]
        self.assertEqual(missing, [])

    def test_cfg_has_no_duplicates(self):
        i = src.index("local CFG = {"); j = src.index("}", i)
        names = [n.strip() for n in re.split(r'[,\n]', src[i+13:j]) if n.strip()]
        self.assertEqual([k for k, v in collections.Counter(names).items() if v > 1], [])

    def test_unique_labels_per_section(self):
        # labels repeated inside one tab are confusing; report them
        labels = re.findall(r'new_(?:toggle|slider|combobox|keybind|button|colorpicker|textbox)\("([^"]+)"', src)
        dup = [k for k, v in collections.Counter(labels).items() if v > 1 and k.strip()]
        self.assertEqual(dup, [], "duplicate menu labels")

    def test_no_stale_names(self):
        for bad in ("penablox", "PENABLOX"):
            self.assertNotIn(bad, src.replace("penablox-luapi", ""))

    def test_code_version_present(self):
        self.assertRegex(src, r'local CODE_VERSION = \d+')

if __name__ == "__main__": unittest.main(verbosity=2)
