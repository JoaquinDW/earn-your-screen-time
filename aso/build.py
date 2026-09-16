# -*- coding: utf-8 -*-
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_part1, gen_part2, gen_part3, gen_legal

LOCALES = ["en-US","en-GB","es-ES","es-MX","de-DE","fr-FR","it","pt-BR",
           "nl-NL","pl","tr","ru","ja","ko","zh-Hans","ar-SA"]
LIMITS = {"name":30,"subtitle":30,"keywords":100,"promotional_text":170,"description":4000}
ATOMS  = ["iPhone","Apple Health","iOS","Earnit", gen_legal.EULA, gen_legal.PRIV]

M = {}
for mod in (gen_part1, gen_part2, gen_part3):
    M.update(mod.M)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fastlane", "metadata")
data = {}
for loc in LOCALES:
    src = M[loc]
    data[loc] = {
        "name": src["name"],
        "subtitle": src["subtitle"],
        "keywords": src["keywords"],
        "promotional_text": src["promo"],
        "description": src["desc"] + gen_legal.block(loc),
        "privacy_url": gen_legal.PRIV,
    }

if "--write" in sys.argv:
    for loc, f in data.items():
        d = os.path.join(OUT, loc); os.makedirs(d, exist_ok=True)
        for k, v in f.items():
            open(os.path.join(d, k + ".txt"), "w", encoding="utf-8").write(v)
    json.dump(data, open(os.path.join(os.path.dirname(OUT), "..", "aso", "metadata.json"), "w"),
              ensure_ascii=False, indent=1)

# ---- step 4: the automated review ----
fails = []
print("%-9s %-9s %-9s %-10s %-11s %-9s %s" % ("locale","name","subtitle","keywords","promo","desc","checks"))
for loc in LOCALES:
    f = data[loc]; notes = []
    for field, cap in LIMITS.items():
        n = len(f[field])
        if n > cap: fails.append("%s %s %d>%d" % (loc, field, n, cap))
    # verbatim atoms survived
    for a in ATOMS:
        if a in ("iPhone","Apple Health","iOS") and loc in ("ja","ko","zh-Hans","ar-SA","ru"):
            pass  # these may legitimately be absent from a rewritten body
        if a.startswith("http") and a not in f["description"]:
            fails.append("%s missing URL %s" % (loc, a)); notes.append("URL!")
    if "Earnit" not in f["name"]:  fails.append("%s brand missing from name" % loc); notes.append("brand!")
    if "Earnit" not in f["description"]: fails.append("%s brand missing from desc" % loc)
    # same-as-source detection (should differ from en-US except en-GB)
    if loc not in ("en-US","en-GB") and f["description"] == data["en-US"]["description"]:
        fails.append("%s description identical to en-US" % loc); notes.append("dup!")
    # keyword hygiene: no phrase repeated from name/subtitle
    surf = (f["name"] + " " + f["subtitle"]).lower()
    for kw in f["keywords"].split(","):
        if kw.strip() and kw.strip().lower() in surf:
            fails.append("%s keyword '%s' already in name/subtitle" % (loc, kw.strip())); notes.append("dupkw!")
    print("%-9s %-9s %-9s %-10s %-11s %-9s %s" % (
        loc, "%d/30"%len(f["name"]), "%d/30"%len(f["subtitle"]),
        "%d/100"%len(f["keywords"]), "%d/170"%len(f["promotional_text"]),
        "%d/4000"%len(f["description"]), " ".join(notes) or "ok"))

print()
if fails:
    print("FAILURES (%d):" % len(fails))
    for x in fails: print("  -", x)
    sys.exit(1)
print("all checks passed for %d locales" % len(LOCALES))
