#!/usr/bin/env python3
"""Check Korean coverage, translation state, and source formatting in string catalogs."""
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = (
    "App/Resources/Localizable.xcstrings",
    "App/Resources/PushupsLocalizable.xcstrings",
    "App/Resources/StudyLocalizable.xcstrings",
    "Extensions/ShieldConfiguration/Localizable.xcstrings",
    "Extensions/EarnLiveActivity/Localizable.xcstrings",
)
# Includes positional arguments, length modifiers, width/precision, and literal %%.
FORMAT = re.compile(r"%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]")
INFLECTION = re.compile(r"\^\[([^\]]*)\](\([^)]*\))?")


def signature(value):
    # The text inside inflection markup is translatable; its structure and attributes aren't.
    inflections = [(m[2] or "") for m in INFLECTION.finditer(value)]
    return Counter(FORMAT.findall(value)), value.count("\n"), Counter(inflections)


def main():
    failures = []
    total = 0
    for relative in CATALOGS:
        catalog = json.loads((ROOT / relative).read_text())
        checked = 0
        covered = 0
        additional = 0
        for key, entry in catalog["strings"].items():
            locales = entry.get("localizations", {})
            if "ja" not in locales and "ko" not in locales:
                continue
            if "ja" in locales:
                checked += 1
                covered += "ko" in locales
            else:
                additional += 1
            korean = locales.get("ko", {}).get("stringUnit", {})
            source = locales.get(catalog["sourceLanguage"], {}).get("stringUnit", {}).get("value", key)
            if "value" not in korean:
                failures.append(f"{relative}: {key}: missing Korean string")
                continue
            if korean.get("state") != "translated":
                failures.append(f"{relative}: {key}: state is not translated")
            if signature(source) != signature(korean["value"]):
                failures.append(f"{relative}: {key}: format/newline/inflection mismatch")
        total += checked + additional
        print(f"{relative}: {covered}/{checked} ja keys have ko; {additional} additional ko entries; formatting and state checked")
    info = ROOT / "App/Resources"
    plist_keys = lambda path: set(re.findall(r'^"([^"\n]+)"\s*=', path.read_text(), re.M))
    if plist_keys(info / "ko.lproj/InfoPlist.strings") != plist_keys(info / "ja.lproj/InfoPlist.strings"):
        failures.append("InfoPlist.strings: Korean and Japanese keys differ")
    def strings_file(path):
        pairs = re.findall(r'^("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");', path.read_text(), re.M)
        return {json.loads(key): json.loads(value) for key, value in pairs}

    progress_source = strings_file(info / "en.lproj/Progress.strings")
    progress_korean = strings_file(info / "ko.lproj/Progress.strings")
    if progress_source.keys() != progress_korean.keys():
        failures.append("Progress.strings: Korean and English keys differ")
    for key in progress_source.keys() & progress_korean.keys():
        if signature(progress_source[key]) != signature(progress_korean[key]):
            failures.append(f"Progress.strings: {key}: formatting mismatch")
    if failures:
        print("\n".join(failures))
        raise SystemExit(1)
    print(f"PASS: {total} Korean translations; 0 missing keys; 0 formatting mismatches; all translated.")
    print("PASS: Korean InfoPlist.strings keys match Japanese.")
    print(f"PASS: {len(progress_korean)} Korean Progress.strings entries match English keys and formatting.")


if __name__ == "__main__":
    main()
