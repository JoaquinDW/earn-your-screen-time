# -*- coding: utf-8 -*-
"""Detector suite for the Earnit translation cascade. Read-only: reports, never writes."""
import json, os, re, sys, unicodedata

LOCALES = ["de","fr","it","pt-BR","nl","pl","tr","ru","ja","ko","zh-Hans","ar"]
NONLATIN = {"ru","ja","ko","zh-Hans","ar"}
KEPT = ["Earnit","Apple Health","Apple Account","App Store","iPhone","iOS","Face ID",
        "Live Activity","Dynamic Island","km","Pro","OK","HealthKit","Screen Time"]
SPEC = re.compile(r'%(?:(\d+)\$)?[-+ #0]*[\d*]*(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfeEgGcCsSpaAF])|%(%)')
COGNATE_OK = {"minutes","session","Holding the Hunger Games hostage at the gym",
              "Milkman, Minson & Volpp \u00b7 Management Science \u00b7 2014","System","%lld apps","%lld minutes",
              "OK","Pro","km","Earnit","Apple Health","Total","Start","Stop","Reset","Debug",
              "Test","Premium","Standard","Detox","Fitness","Timer","App","Apps","Live","min"}

def specs(s):
    """multiset of specifier types, ignoring positional index"""
    out=[]
    for m in SPEC.finditer(s):
        if m.group(4): out.append("%")
        else: out.append((m.group(2) or "")+m.group(3))
    return sorted(out)

def positions(s):
    return [int(m.group(1)) for m in SPEC.finditer(s) if m.group(1)]

def latin_runs(s):
    t=SPEC.sub(" ", s)          # strip %lld/%@ FIRST - "lld" is not a Latin word
    for k in KEPT: t=t.replace(k,"")
    return re.findall(r'[A-Za-z]{3,}', t)

TRAD = set("們這說時個來對開關實學國語與體發點總還經歷樣週遠邊進運過錢間電車專門題顯選擇確認設備記錄類單")

GROUPS = {
 "tabs": ["nav.home","nav.earn","nav.progress","nav.settings"],
}

def main():
    src = json.load(open("aso/l10n/work.json"))
    ext = json.load(open("aso/l10n/work_ext.json")) if os.path.exists("aso/l10n/work_ext.json") else {}
    allsrc = {("main",c):v for c,v in src.items()}
    allsrc.update({("ext",c):v for c,v in ext.items()})
    problems={}
    for loc in LOCALES:
        p=[]
        main_f="aso/l10n/out/%s.json"%loc; ext_f="aso/l10n/out_ext/%s.json"%loc
        if not os.path.exists(main_f):
            problems[loc]=["MISSING FILE %s"%main_f]; continue
        tr={("main",c):v for c,v in json.load(open(main_f)).items()}
        if os.path.exists(ext_f):
            tr.update({("ext",c):v for c,v in json.load(open(ext_f)).items()})
        elif ext: p.append("missing out_ext/%s.json (extensions + permission prompts)"%loc)
        for (scope,cat),keys in allsrc.items():
            got=tr.get((scope,cat),{})
            miss=[k for k in keys if k not in got or not str(got.get(k,"")).strip()]
            if miss: p.append("%s/%s: %d missing keys e.g. %s"%(scope,cat,len(miss),miss[:3]))
            for k,meta in keys.items():
                v=got.get(k)
                if not v: continue
                en=meta["en"]
                if specs(v)!=specs(en):
                    p.append("SPEC %s/%s %r: en=%s got=%s"%(scope,cat,k,specs(en),specs(v)))
                pos=positions(v)
                if pos and sorted(pos)!=list(range(1,len(pos)+1)):
                    p.append("POSITIONAL %s/%s %r: indices %s"%(scope,cat,k,pos))
                if v==en and en not in COGNATE_OK and len(en)>3 and re.search(r'[A-Za-z]{4,}',en):
                    p.append("SAME-AS-EN %s/%s %r = %r"%(scope,cat,k,en[:48]))
                if loc in NONLATIN:
                    lr=latin_runs(v)
                    if lr: p.append("LATIN-LEAK %s/%s %r: %s"%(scope,cat,k,lr[:4]))
                if loc=="zh-Hans":
                    bad=[ch for ch in v if ch in TRAD]
                    if bad: p.append("TRADITIONAL %s/%s %r: %s"%(scope,cat,k,bad))
        # enum group distinctness
        flat={}
        for (scope,cat),d in tr.items(): flat.update(d)
        for gname,keys in GROUPS.items():
            vals=[flat.get(k) for k in keys if flat.get(k)]
            if len(vals)>1 and len(set(vals))<len(vals):
                p.append("ENUM-COLLISION %s: %s"%(gname,vals))
        problems[loc]=p
    total=0
    for loc in LOCALES:
        p=problems.get(loc,["not run"]); total+=len(p)
        print("%-8s %s"%(loc, "clean" if not p else "%d issue(s)"%len(p)))
        for x in p[:12]: print("      -",x)
        if len(p)>12: print("      ... and %d more"%(len(p)-12))
    print("\nTOTAL ISSUES:",total)
    return 1 if total else 0

if __name__=="__main__": sys.exit(main())
