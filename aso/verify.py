# -*- coding: utf-8 -*-
import json, subprocess, sys, time
sys.path.insert(0, "aso")
import build as B, whatsnew
ASC="/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
V="67b1afb0-ec48-49a3-89a1-2bff6fe068a8"; A="7e699c16-00d6-4b90-af60-0f00458d5cb8"
def get(p, tries=4):
    # A verify run straight after a write run gets rate-limited; a bare read used to
    # blow up on the missing "data" key and look like a failed push.
    for i in range(tries):
        o=subprocess.run(["ruby",ASC,"GET",p],capture_output=True,text=True).stdout
        code=o.split("\n",1)[0].replace("HTTP","").strip()
        body=json.loads(o.split("\n",1)[1]) if "\n" in o else {}
        if "data" in body: return body
        if code not in ("401","429","500","503"): break
        time.sleep(2+2*i)
    sys.exit("could not read %s (HTTP %s): %s" % (p, code, json.dumps(body, ensure_ascii=False)[:300]))
info={d["attributes"]["locale"]:d["attributes"] for d in get("/v1/appInfos/%s/appInfoLocalizations?limit=200"%A)["data"]}
ver ={d["attributes"]["locale"]:d["attributes"] for d in get("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200"%V)["data"]}
bad=[]
print("%-9s %-30s %-30s %s"%("locale","LIVE name","LIVE subtitle","desc/kw/promo/notes"))
for loc in B.LOCALES:
    e=B.data[loc]; i=info.get(loc,{}); v=ver.get(loc,{})
    checks=[]
    for field,got,want in (("name",i.get("name"),e["name"]),("subtitle",i.get("subtitle"),e["subtitle"]),
                           ("privacy",i.get("privacyPolicyUrl"),e["privacy_url"]),
                           # Missing on any locale, this blocks the whole submission.
                           ("support",v.get("supportUrl"),e["support_url"]),
                           ("keywords",v.get("keywords"),e["keywords"]),
                           ("description",v.get("description"),e["description"]),
                           ("promo",v.get("promotionalText"),e["promotional_text"]),
                           ("whatsNew",v.get("whatsNew"),whatsnew.W[loc])):
        if got!=want: bad.append("%s %s mismatch"%(loc,field)); checks.append(field+"!")
    # non-English sanity: description must not be the en-US one
    if loc not in ("en-US","en-GB") and v.get("description")==ver["en-US"]["description"]:
        bad.append("%s description fell back to en-US"%loc); checks.append("FALLBACK!")
    print("%-9s %-30s %-30s %s"%(loc,i.get("name"),i.get("subtitle"),
          "%d/%d/%d/%d %s"%(len(v.get("description") or ""),len(v.get("keywords") or ""),
                            len(v.get("promotionalText") or ""),len(v.get("whatsNew") or ""),
                            " ".join(checks) or "verified")))
print()
print(("VERIFICATION FAILURES:\n  "+"\n  ".join(bad)) if bad else "All 16 locales verified against a read-back.")
