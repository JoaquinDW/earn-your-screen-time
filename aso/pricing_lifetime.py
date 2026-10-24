# -*- coding: utf-8 -*-
"""Purchasing-power price bands for the Lifetime in-app purchase.

`pricing.py` banded both subscriptions, but Lifetime shipped later at one US price, so Apple
equalized USD 30 everywhere: in Argentina it costs as much as in the US while the monthly plan
costs 60% of it there, and that is what a 1-star review called "como 50 lucas".

Same bands and GNI source as `pricing.py`, with Lifetime anchors at the same share of the US
price that the monthly band pays (20% … 100%). A non-consumable is priced differently from a
subscription: one price *schedule* per product, with a base territory Apple equalizes from and
manual prices that override it. This script rebuilds that schedule — the US base at today's
price, plus one manual price per discounted territory, taken from Apple's own equalization of
that band's US anchor. Top-band territories keep following the US base.

  python3 aso/pricing_lifetime.py            # dry run: what changes, and the live schedule
  python3 aso/pricing_lifetime.py --write    # replace the schedule (takes effect immediately)
"""
import json, sys, base64

from pricing import asc, cached, gni_table, band_for, BANDS, TOP_BAND, DRY

LIFETIME_IAP = "6824755138"
# Same position in the ladder as the monthly anchors in `pricing.BANDS`.
LIFETIME_ANCHORS = {
    BANDS[0][1]: "5.99",
    BANDS[1][1]: "11.99",
    BANDS[2][1]: "17.99",
    BANDS[3][1]: "23.99",
}


def territory_of(point):
    terr = ((point.get("relationships", {}).get("territory", {}) or {}).get("data") or {}).get("id")
    if terr:
        return terr
    padded = point["id"] + "=" * (-len(point["id"]) % 4)
    return json.loads(base64.b64decode(padded))["t"]


def us_points():
    page = cached("iap_pp_lifetime_USA",
                  "/v2/inAppPurchases/%s/pricePoints?filter%%5Bterritory%%5D=USA&limit=200" % LIFETIME_IAP)
    return {p["attributes"]["customerPrice"]: p["id"] for p in page["data"]}


def equalized(anchor_price, anchor_id):
    page = cached("iap_eq_lifetime_%s" % anchor_price.replace(".", "_"),
                  "/v1/inAppPurchasePricePoints/%s/equalizations?include=territory&limit=200" % anchor_id)
    return {territory_of(p): (p["id"], p["attributes"]["customerPrice"]) for p in page["data"]}


def live_schedule():
    """Manual prices on the current schedule, by territory. Never cached: it is what changes."""
    code, payload = asc("GET", "/v1/inAppPurchasePriceSchedules/%s/manualPrices"
                               "?include=inAppPurchasePricePoint,territory&limit=200" % LIFETIME_IAP)
    if code != "200":
        sys.exit("reading the live schedule failed (HTTP %s): %s" % (code, json.dumps(payload)[:300]))
    included = {i["id"]: i for i in payload.get("included", [])}
    out = {}
    for row in payload["data"]:
        rel = row["relationships"]
        terr = (rel.get("territory", {}).get("data") or {}).get("id")
        point = (rel.get("inAppPurchasePricePoint", {}).get("data") or {}).get("id")
        out[terr] = (point, included.get(point, {}).get("attributes", {}).get("customerPrice"))
    return out


def main():
    live = live_schedule()
    if "USA" not in live:
        sys.exit("the live schedule has no USA manual price; set the base in App Store Connect first")
    us_point, us_price = live["USA"]
    print("base: USA at US$%s (%d manual prices on the live schedule)\n" % (us_price, len(live)))

    points = us_points()
    tables = {}
    for anchor in LIFETIME_ANCHORS.values():
        if anchor not in points:
            sys.exit("Apple has no US Lifetime price point at %s" % anchor)
        tables[anchor] = equalized(anchor, points[anchor])

    gni = gni_table()
    manual = {"USA": (us_point, us_price)}
    territories = sorted(set().union(*[t.keys() for t in tables.values()]) | set(live))
    print("%-5s %-10s %-8s %s" % ("terr", "GNI/cap", "band", "new"))
    for terr in territories:
        band = band_for(gni.get(terr))
        if band is TOP_BAND or terr == "USA":
            continue
        anchor = LIFETIME_ANCHORS[band[1]]
        point = tables[anchor].get(terr)
        if not point:
            continue
        manual[terr] = point
        print("%-5s %-10s US$%-5s %s" % (terr, ("%d" % gni[terr]) if gni.get(terr) else "n/d", anchor, point[1]))

    dropped = sorted(t for t in live if t not in manual)
    if dropped:
        # A territory with a manual price today that no band claims goes back to following the US.
        print("\nmanual prices removed (return to the US equalization):", ", ".join(dropped))
    print("\n%d manual prices, the rest of the world follows USA" % len(manual))

    if DRY:
        print("MODE: DRY RUN — pass --write to apply")
        return 0

    refs, included = [], []
    for i, (terr, (point_id, _)) in enumerate(sorted(manual.items())):
        ref = "${price%d}" % i
        refs.append({"type": "inAppPurchasePrices", "id": ref})
        included.append({
            "type": "inAppPurchasePrices", "id": ref,
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": LIFETIME_IAP}},
                "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point_id}},
            },
        })
    code, payload = asc("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": LIFETIME_IAP}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": refs},
            },
        },
        "included": included,
    })
    print("MODE: WROTE — HTTP %s" % code)
    if code not in ("200", "201"):
        print(json.dumps(payload, ensure_ascii=False)[:500])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
