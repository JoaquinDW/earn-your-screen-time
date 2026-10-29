# -*- coding: utf-8 -*-
import json, sys
sys.path.insert(0, "aso")
import build as B

from asc_targets import asc, editable_app_info, editable_version, locale_map

VERSION_ID, VERSION = editable_version()
APPINFO_ID = editable_app_info()
print("writing to version %s (%s), appInfo %s" % (VERSION, VERSION_ID, APPINFO_ID))

# A failed read must stop the run: an empty map would turn every PATCH into a POST.
info_map = {loc: d["id"] for loc, d in locale_map("/v1/appInfos/%s/appInfoLocalizations?limit=200" % APPINFO_ID).items()}
ver_map  = {loc: d["id"] for loc, d in locale_map("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID).items()}

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
        if c == "201" and loc not in ver_map:
            # Apple creates the matching version localization along with the appInfo one, so a
            # POST here would 409 as a duplicate. Look it up again and PATCH it instead.
            ver_map = {l: d["id"] for l, d in locale_map("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID).items()}
    err1 = "" if c in ("200", "201") else json.dumps(p, ensure_ascii=False)[:220]

    # ---- keywords / description / promo ----
    # Release notes belong to one version, so they stay with push_whatsnew.py: written from
    # here, 1.3.1's notes would land on whatever version is open now.
    vattrs = {"description": f["description"], "keywords": f["keywords"],
              "promotionalText": f["promotional_text"]}
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
