# -*- coding: utf-8 -*-
"""Merge translations into the String Catalogs. Additive only: never touches en/es,
never removes a key. Refuses to write if any assertion fails."""
import json, os, shutil, sys

# Backups live outside the source tree on purpose: XcodeGen globs App/Resources and
# Extensions, so a .bak sitting next to a catalog gets compiled into the project as a
# resource and the build then fails on a file that was cleaned up afterwards.
BACKUP_DIR = "aso/l10n/backup"

LOCALES = ["de","fr","it","pt-BR","nl","pl","tr","ru","ja","ko","zh-Hans","ar"]
CATS = {"Localizable":"App/Resources/Localizable.xcstrings",
        "Study":"App/Resources/StudyLocalizable.xcstrings",
        "Pushups":"App/Resources/PushupsLocalizable.xcstrings",
        "Shield":"Extensions/ShieldConfiguration/Localizable.xcstrings",
        "LiveActivity":"Extensions/EarnLiveActivity/Localizable.xcstrings"}
MAIN = {"Localizable","Study","Pushups"}
DRY = "--write" not in sys.argv

def load(loc, ext):
    f = "aso/l10n/out%s/%s.json" % ("_ext" if ext else "", loc)
    return json.load(open(f)) if os.path.exists(f) else {}

trans = {}                       # cat -> loc -> {key: value}
for loc in LOCALES:
    for cat, d in load(loc, False).items(): trans.setdefault(cat, {})[loc] = d
    for cat, d in load(loc, True).items():  trans.setdefault(cat, {})[loc] = d

report, wrote = [], 0
for cat, path in CATS.items():
    if cat not in trans: report.append("%-13s no translations found — skipped" % cat); continue
    doc = json.load(open(path))
    before = set(doc["strings"])
    added = 0
    for loc, pairs in trans[cat].items():
        for key, val in pairs.items():
            if key not in doc["strings"]:      # never invent keys
                continue
            if not str(val).strip():
                continue
            locs = doc["strings"][key].setdefault("localizations", {})
            if loc in ("en", "es"):            # never touch shipped languages
                continue
            locs[loc] = {"stringUnit": {"state": "translated", "value": val}}
            added += 1
    after = set(doc["strings"])
    assert before == after, "%s: key set changed!" % cat          # hard safety gate
    # en/es must be byte-identical to what was on disk
    orig = json.load(open(path))
    for k in before:
        for keep in ("en", "es"):
            a = orig["strings"][k].get("localizations", {}).get(keep)
            b = doc["strings"][k].get("localizations", {}).get(keep)
            assert a == b, "%s/%s: %s localization was modified!" % (cat, k, keep)
    covered = sorted({l for p in trans[cat].values() for l in [None]} ) # noop
    locs_done = sorted(trans[cat])
    report.append("%-13s %4d keys | +%5d translations | locales: %s"
                  % (cat, len(before), added, ",".join(locs_done)))
    if not DRY:
        os.makedirs(BACKUP_DIR, exist_ok=True)
        shutil.copy(path, os.path.join(BACKUP_DIR, os.path.basename(path) + ".bak"))
        json.dump(doc, open(path, "w"), ensure_ascii=False, indent=2)
        wrote += 1

print("\n".join(report))
print("\nMODE:", "WROTE %d catalogs (backups in %s)" % (wrote, BACKUP_DIR) if not DRY else "DRY RUN — pass --write to apply")
