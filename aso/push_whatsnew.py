# -*- coding: utf-8 -*-
"""Push only the release notes to App Store Connect.

`reconcile.py` writes every field of the listing. When the only thing that changed is
`whatsnew.py` — the usual case once phases 1-2 are live and verified — this writes just
`whatsNew` on each appStoreVersionLocalization and leaves name, subtitle, keywords,
description and promotional text untouched. Run `python3 aso/verify.py` first to confirm
nothing else drifted, and again afterwards to read the result back.
"""
import json, subprocess, sys, time
sys.path.insert(0, "aso")
import build as B, whatsnew

ASC = "/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
VERSION_ID = "67b1afb0-ec48-49a3-89a1-2bff6fe068a8"
DRY = "--write" not in sys.argv

def asc(method, path, body=None, tries=4):
    for i in range(tries):
        cmd = ["ruby", ASC, method, path] + ([json.dumps(body, ensure_ascii=False)] if body else [])
        r = subprocess.run(cmd, capture_output=True, text=True)
        out = r.stdout
        code = out.split("\n", 1)[0].replace("HTTP ", "").strip()
        rest = out.split("\n", 1)[1] if "\n" in out else ""
        try: payload = json.loads(rest)
        except Exception: payload = {"raw": rest[:300]}
        if code in ("200", "201") or code not in ("401", "429", "500", "503"):
            return code, payload
        time.sleep(2 + 2 * i)
    return code, payload

code, page = asc("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID)
assert code == "200", "could not read the version's locales: %s %s" % (code, page)
live = {d["attributes"]["locale"]: d for d in page["data"]}

missing = [loc for loc in B.LOCALES if loc not in live]
assert not missing, "locale(s) absent from the version, run reconcile.py first: %s" % missing

bad, changed, same = [], 0, 0
for loc in B.LOCALES:
    want = whatsnew.W[loc]
    assert len(want) <= 4000, "%s: release notes are %d chars, over Apple's 4000" % (loc, len(want))
    if live[loc]["attributes"].get("whatsNew") == want:
        same += 1
        print("%-9s unchanged" % loc)
        continue
    changed += 1
    if DRY:
        print("%-9s would write %d chars" % (loc, len(want)))
        continue
    c, p = asc("PATCH", "/v1/appStoreVersionLocalizations/%s" % live[loc]["id"],
               {"data": {"type": "appStoreVersionLocalizations", "id": live[loc]["id"],
                         "attributes": {"whatsNew": want}}})
    print("%-9s %s" % (loc, c))
    if c not in ("200", "201"):
        bad.append((loc, json.dumps(p, ensure_ascii=False)[:300]))

print()
for loc, err in bad: print("FAIL %s: %s" % (loc, err))
print("%d to write, %d already current, %d failures" % (changed, same, len(bad)))
print("MODE:", "DRY RUN — pass --write to apply" if DRY else "WROTE")
sys.exit(1 if bad else 0)
