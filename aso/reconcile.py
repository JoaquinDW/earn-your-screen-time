# -*- coding: utf-8 -*-
import json, subprocess, sys, time
sys.path.insert(0, "aso")
import build as B, whatsnew

ASC = "/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
VERSION_ID = "67b1afb0-ec48-49a3-89a1-2bff6fe068a8"
APPINFO_ID = "7e699c16-00d6-4b90-af60-0f00458d5cb8"

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

def emap(path):
    c, p = asc("GET", path)
    return {d["attributes"]["locale"]: d["id"] for d in p.get("data", [])}

info_map = emap("/v1/appInfos/%s/appInfoLocalizations?limit=200" % APPINFO_ID)
ver_map  = emap("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID)
print("existing: %d appInfo locales, %d version locales\n" % (len(info_map), len(ver_map)))

bad = []
for loc in B.LOCALES:
    f = B.data[loc]
    row = [loc]
    attrs = {"name": f["name"], "subtitle": f["subtitle"], "privacyPolicyUrl": f["privacy_url"]}
    if loc in info_map:
        c, p = asc("PATCH", "/v1/appInfoLocalizations/%s" % info_map[loc],
                   {"data": {"type": "appInfoLocalizations", "id": info_map[loc], "attributes": attrs}})
    else:
        a = dict(attrs); a["locale"] = loc
        c, p = asc("POST", "/v1/appInfoLocalizations",
                   {"data": {"type": "appInfoLocalizations", "attributes": a,
                             "relationships": {"appInfo": {"data": {"type": "appInfos", "id": APPINFO_ID}}}}})
    row.append("info " + c)
    if c not in ("200", "201"): bad.append((loc, "info", json.dumps(p, ensure_ascii=False)[:300]))

    vattrs = {"description": f["description"], "keywords": f["keywords"],
              "promotionalText": f["promotional_text"], "whatsNew": whatsnew.W[loc],
              "supportUrl": f["support_url"]}
    if loc not in ver_map:
        ver_map = emap("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID)
    if loc in ver_map:
        c2, p2 = asc("PATCH", "/v1/appStoreVersionLocalizations/%s" % ver_map[loc],
                     {"data": {"type": "appStoreVersionLocalizations", "id": ver_map[loc], "attributes": vattrs}})
    else:
        a = dict(vattrs); a["locale"] = loc
        c2, p2 = asc("POST", "/v1/appStoreVersionLocalizations",
                     {"data": {"type": "appStoreVersionLocalizations", "attributes": a,
                               "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
    row.append("ver " + c2)
    if c2 not in ("200", "201"): bad.append((loc, "ver", json.dumps(p2, ensure_ascii=False)[:300]))
    print("  ".join(row))

print()
for loc, kind, err in bad: print("FAIL %s %s: %s" % (loc, kind, err))
print("\n%d write failures" % len(bad))
