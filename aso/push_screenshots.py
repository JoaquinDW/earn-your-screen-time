# -*- coding: utf-8 -*-
"""Upload the App Store screenshots to the editable version in App Store Connect.

Uploads the 6.3" PNGs (1206x2622) from marketing/app-store-screenshots/6.3-inch/<folder>/
into each locale's APP_IPHONE_61 set, in file-name order. That is the "iPhone with Dynamic
Island (medium)" slot App Store Connect asks this app for; it rejects 6.9" files. Any other
iPhone set on the locale (6.9", 6.5", 5.5"…) is deleted, because a leftover set would keep
showing old screenshots on those devices.
iPad sets are left alone.

    python3 aso/push_screenshots.py            # dry run: shows what would change
    python3 aso/push_screenshots.py --write    # deletes the old sets and uploads
    python3 aso/push_screenshots.py --write --locales en-US,es-MX

Never submits the version for review and never touches metadata.
"""
import hashlib, json, os, sys, time, urllib.request
sys.path.insert(0, "aso")
from asc_targets import asc, editable_version, get, locale_map

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "marketing", "app-store-screenshots", "6.3-inch")
DISPLAY_TYPE = "APP_IPHONE_61"
SIZE = (1206, 2622)
# Store locale -> screenshot folder. Locales without a folder of their own are skipped, so they
# keep falling back to the primary language until their set is rendered.
FOLDERS = {"en-US": "en-US", "en-GB": "en-US", "es-ES": "es", "es-MX": "es",
           "de-DE": "de", "fr-FR": "fr", "it": "it", "pt-BR": "pt-BR", "nl-NL": "nl", "pl": "pl",
           "tr": "tr", "ru": "ru", "ja": "ja", "ko": "ko", "zh-Hans": "zh-Hans", "ar-SA": "ar"}
WRITE = "--write" in sys.argv


def arg(name):
    for a in sys.argv:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    if name in sys.argv and sys.argv.index(name) + 1 < len(sys.argv):
        return sys.argv[sys.argv.index(name) + 1]
    return None


def check(code, payload, what):
    if code not in ("200", "201", "204"):
        sys.exit("%s failed (HTTP %s): %s" % (what, code, json.dumps(payload, ensure_ascii=False)[:400]))
    return payload


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def files_for(folder):
    d = os.path.join(ROOT, folder)
    if not os.path.isdir(d):
        return []
    names = sorted(n for n in os.listdir(d) if n.lower().endswith(".png"))
    paths = [os.path.join(d, n) for n in names]
    for p in paths:
        if png_size(p) != SIZE:
            sys.exit("%s is %dx%d, expected %dx%d" % (p, *png_size(p), *SIZE))
    if not 1 <= len(paths) <= 10:
        sys.exit("%s has %d PNGs; App Store Connect takes 1 to 10" % (d, len(paths)))
    return paths


def upload(set_id, path):
    data = open(path, "rb").read()
    created = check(*asc("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}}),
        "reserving " + os.path.basename(path))["data"]
    for op in created["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders") or []:
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req) as r:
            if r.status >= 300:
                sys.exit("uploading %s: HTTP %s" % (path, r.status))
    check(*asc("PATCH", "/v1/appScreenshots/%s" % created["id"], {"data": {
        "type": "appScreenshots", "id": created["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}),
        "committing " + os.path.basename(path))
    return created["id"]


def wait_until_processed(ids, timeout=600):
    states = {}
    deadline = time.time() + timeout
    while time.time() < deadline:
        for i in ids:
            if states.get(i) in ("COMPLETE", "FAILED"):
                continue
            code, p = asc("GET", "/v1/appScreenshots/%s" % i)
            delivery = (p.get("data", {}).get("attributes", {}).get("assetDeliveryState") or {})
            states[i] = delivery.get("state", "UNKNOWN")
            if states[i] == "FAILED":
                print("    processing failed: %s" % json.dumps(delivery.get("errors"), ensure_ascii=False))
        if all(s in ("COMPLETE", "FAILED") for s in states.values()):
            break
        time.sleep(5)
    return states


version_id, version = editable_version()
print("%s version %s (%s)\n" % ("WRITING TO" if WRITE else "DRY RUN against", version, version_id))
localizations = locale_map("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % version_id)
wanted = arg("--locales")
targets = [l for l in (wanted.split(",") if wanted else FOLDERS) if l in localizations]

report = []
for loc in targets:
    paths = files_for(FOLDERS.get(loc, ""))
    if not paths:
        print("%-8s skipped: no folder %s/ yet" % (loc, FOLDERS.get(loc)))
        report.append((loc, "-", "skipped, no screenshots rendered"))
        continue
    sets = get("/v1/appStoreVersionLocalizations/%s/appScreenshotSets?limit=50" % localizations[loc]["id"])
    iphone_sets = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in sets
                   if s["attributes"]["screenshotDisplayType"].startswith("APP_IPHONE")}
    old = {t: len(get("/v1/appScreenshotSets/%s/appScreenshots?limit=50" % i)) for t, i in iphone_sets.items()}
    print("%-8s delete %s -> new %s with %d from %s/" % (
        loc, ", ".join("%s (%d)" % kv for kv in sorted(old.items())) or "nothing",
        DISPLAY_TYPE, len(paths), FOLDERS[loc]))
    if not WRITE:
        continue

    for display_type, set_id in iphone_sets.items():
        check(*asc("DELETE", "/v1/appScreenshotSets/%s" % set_id), "deleting %s %s" % (loc, display_type))
    set_id = check(*asc("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
        "relationships": {"appStoreVersionLocalization": {"data": {
            "type": "appStoreVersionLocalizations", "id": localizations[loc]["id"]}}}}}),
        "creating %s set" % loc)["data"]["id"]
    ids = [upload(set_id, p) for p in paths]
    check(*asc("PATCH", "/v1/appScreenshotSets/%s/relationships/appScreenshots" % set_id,
               {"data": [{"type": "appScreenshots", "id": i} for i in ids]}), "ordering %s" % loc)
    states = wait_until_processed(ids)
    done = sum(s == "COMPLETE" for s in states.values())
    report.append((loc, DISPLAY_TYPE, "%d/%d complete" % (done, len(ids))))
    print("         uploaded, %d/%d processed" % (done, len(ids)))

if not WRITE:
    print("\nNothing changed. Run again with --write to apply.")
else:
    print("\n%-8s %-15s %s" % ("locale", "set", "result"))
    for row in report:
        print("%-8s %-15s %s" % row)
