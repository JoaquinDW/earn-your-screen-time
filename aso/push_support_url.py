# -*- coding: utf-8 -*-
"""Fill in the per-locale support URL on the version's localizations.

App Store Connect requires a support URL on *every* localization before a version can be
submitted, and neither `push.py` nor `reconcile.py` writes the field — so the twelve
locales the ASO pass created were born without one and the submit fails with
"Support URL - This field is required".

The submit dialog only names a few of the offending locales at a time, so fixing the ones
it lists just moves the error. This copies en-US's URL onto every locale that is missing
one, in a single pass.

  python3 aso/push_support_url.py            # dry run
  python3 aso/push_support_url.py --write    # apply
"""
import json, subprocess, sys, time

ASC = "/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
VERSION_ID = "67b1afb0-ec48-49a3-89a1-2bff6fe068a8"
SOURCE_LOCALE = "en-US"
DRY = "--write" not in sys.argv


def asc(method, path, body=None, tries=4):
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


def main():
    code, page = asc("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VERSION_ID)
    if code != "200" or "data" not in page:
        sys.exit("could not read the version's locales (HTTP %s): %s" % (code, json.dumps(page)[:300]))

    rows = {r["attributes"]["locale"]: r for r in page["data"]}
    source = rows.get(SOURCE_LOCALE)
    if not source:
        sys.exit("%s localization not found" % SOURCE_LOCALE)
    url = source["attributes"].get("supportUrl")
    if not url:
        sys.exit("%s has no support URL to copy" % SOURCE_LOCALE)
    print("source: %s -> %s\n" % (SOURCE_LOCALE, url))

    missing = sorted(loc for loc, r in rows.items() if not r["attributes"].get("supportUrl"))
    if not missing:
        print("every locale already has a support URL")
        return 0

    failures = []
    for loc in missing:
        if DRY:
            print("  %-9s would set" % loc)
            continue
        row_id = rows[loc]["id"]
        code, payload = asc("PATCH", "/v1/appStoreVersionLocalizations/%s" % row_id,
                            {"data": {"type": "appStoreVersionLocalizations", "id": row_id,
                                      "attributes": {"supportUrl": url}}})
        print("  %-9s %s" % (loc, code))
        if code not in ("200", "201"):
            failures.append((loc, json.dumps(payload, ensure_ascii=False)[:200]))

    print()
    for loc, err in failures:
        print("FAIL %s: %s" % (loc, err))
    print("%d locale(s) missing, %d failure(s)" % (len(missing), len(failures)))
    print("MODE:", "DRY RUN — pass --write to apply" if DRY else "WROTE")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
