# -*- coding: utf-8 -*-
import json, os, subprocess, sys
sys.path.insert(0, "aso")
import build as B, whatsnew

ASC = "/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
VERSION_ID = "67b1afb0-ec48-49a3-89a1-2bff6fe068a8"
APPINFO_ID = "7e699c16-00d6-4b90-af60-0f00458d5cb8"

def asc(method, path, body=None):
    cmd = ["ruby", ASC, method, path] + ([json.dumps(body, ensure_ascii=False)] if body else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout
    code = out.split("\n", 1)[0].replace("HTTP ", "").strip()
    rest = out.split("\n", 1)[1] if "\n" in out else ""
    try: payload = json.loads(rest)
    except Exception: payload = {"raw": rest[:400]}
    return code, payload

def existing(path, key="locale"):
    code, p = asc("GET", path)
    return {d["attributes"][key]: d["id"] for d in p.get("data", [])}

info_map = existing("/v1/appInfos/%s/appInfoLocalizations?limit=200" % APPINFO_ID)
ver_map  = existing("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID)

for loc in B.LOCALES:
    f = B.data[loc]
    # ---- name / subtitle / privacy URL ----
    attrs = {"name": f["name"], "subtitle": f["subtitle"], "privacyPolicyUrl": f["privacy_url"]}
    if loc in info_map:
        c, p = asc("PATCH", "/v1/appInfoLocalizations/%s" % info_map[loc],
                   {"data": {"type": "appInfoLocalizations", "id": info_map[loc], "attributes": attrs}})
        act = "PATCH info"
    else:
        a = dict(attrs); a["locale"] = loc
        c, p = asc("POST", "/v1/appInfoLocalizations",
                   {"data": {"type": "appInfoLocalizations", "attributes": a,
                             "relationships": {"appInfo": {"data": {"type": "appInfos", "id": APPINFO_ID}}}}})
        act = "POST  info"
    err1 = "" if c in ("200", "201") else json.dumps(p, ensure_ascii=False)[:220]

    # ---- keywords / description / promo / release notes ----
    vattrs = {"description": f["description"], "keywords": f["keywords"],
              "promotionalText": f["promotional_text"], "whatsNew": whatsnew.W[loc]}
    if loc in ver_map:
        c2, p2 = asc("PATCH", "/v1/appStoreVersionLocalizations/%s" % ver_map[loc],
                     {"data": {"type": "appStoreVersionLocalizations", "id": ver_map[loc], "attributes": vattrs}})
        act2 = "PATCH ver"
    else:
        a = dict(vattrs); a["locale"] = loc
        c2, p2 = asc("POST", "/v1/appStoreVersionLocalizations",
                     {"data": {"type": "appStoreVersionLocalizations", "attributes": a,
                               "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}})
        act2 = "POST  ver"
    err2 = "" if c2 in ("200", "201") else json.dumps(p2, ensure_ascii=False)[:220]
    print("%-9s %s %-3s  %s %-3s  %s%s" % (loc, act, c, act2, c2, err1, err2))
