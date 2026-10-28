# -*- coding: utf-8 -*-
"""Finds the App Store Connect records that can still be edited.

Name and subtitle live on the app's editable appInfo, everything else on the editable
appStoreVersion. Both get new ids every release, so hard-coding them breaks as soon as a
version ships: push.py kept writing to 1.3.1 after it went live, its reads came back empty
and every locale ended in a 409. Look them up instead.
"""
import json, subprocess, sys, time

ASC = "/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
APP_ID = "6804905841"
EDITABLE_VERSION_STATES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")
LIVE_APPINFO_STATES = ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "REPLACED_WITH_NEW_INFO")


def asc(method, path, body=None, tries=4):
    """One API call, retried on the transient 401/429/5xx the token helper sometimes returns."""
    for i in range(tries):
        cmd = ["ruby", ASC, method, path] + ([json.dumps(body, ensure_ascii=False)] if body else [])
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        code = out.split("\n", 1)[0].replace("HTTP", "").strip()
        rest = out.split("\n", 1)[1] if "\n" in out else ""
        try: payload = json.loads(rest)
        except Exception: payload = {"raw": rest[:300]}
        if code in ("200", "201") or code not in ("401", "429", "500", "503"):
            return code, payload
        time.sleep(2 + 2 * i)
    return code, payload


def get(path):
    code, payload = asc("GET", path)
    if code != "200" or "data" not in payload:
        sys.exit("could not read %s (HTTP %s): %s" % (path, code, json.dumps(payload, ensure_ascii=False)[:300]))
    return payload["data"]


def editable_version():
    versions = get("/v1/apps/%s/appStoreVersions?filter[platform]=IOS&limit=50" % APP_ID)
    drafts = [v for v in versions if v["attributes"].get("appStoreState") in EDITABLE_VERSION_STATES]
    if not drafts:
        live = ", ".join("%s %s" % (v["attributes"]["versionString"], v["attributes"].get("appStoreState"))
                         for v in versions[:5])
        sys.exit("no editable version. Create the next version in App Store Connect first. Latest: " + live)
    return drafts[0]["id"], drafts[0]["attributes"]["versionString"]


def editable_app_info():
    infos = get("/v1/apps/%s/appInfos" % APP_ID)
    editable = [i for i in infos
                if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) not in LIVE_APPINFO_STATES]
    if not editable:
        sys.exit("no editable appInfo: name and subtitle only open up with a new version")
    return editable[0]["id"]


def locale_map(path):
    return {d["attributes"]["locale"]: d for d in get(path)}
