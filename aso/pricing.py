# -*- coding: utf-8 -*-
"""Purchasing-power price bands for the two Earnit subscriptions.

There is no published "Netflix index"; what Netflix does observably is band its price by
purchasing power. This reproduces that with a citable source — World Bank GNI per capita,
Atlas method (`aso/gni-worldbank.json`, refreshed from the World Bank API) — and a spread
calibrated to Netflix's own: the poorest band pays 20% of the US price, the richest 100%.

Prices are never invented. For each band a US anchor price point is resolved, and Apple's
own `equalizations` endpoint supplies that anchor's counterpart in every other territory,
so every price written is one Apple already offers there, in local currency, VAT handled.

  python3 aso/pricing.py            # dry run: the full 175-territory table
  python3 aso/pricing.py --write    # apply
"""
import datetime, json, os, subprocess, sys, time, base64

ASC = "/Users/balthasardeweert/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb"
CACHE = "/private/tmp/claude-501/-Users-balthasardeweert-Documents-Projects-earn-your-screen-time/fe4abbf9-da62-48ed-a7be-bcc23a4978f0/scratchpad/asc-cache"
DRY = "--write" not in sys.argv

SUBSCRIPTIONS = {
    "monthly": "6805245250",
    "yearly": "6805245525",
}
# (GNI per capita ceiling, monthly US anchor, yearly US anchor). The yearly anchor keeps
# the current 8x monthly ratio, so the annual discount is identical in every band.
BANDS = [
    (2000,           "0.99",  "7.99"),
    (6000,           "1.99", "15.99"),
    (15000,          "2.99", "23.99"),
    (30000,          "3.99", "31.99"),
    (float("inf"),   "4.99", "39.99"),
]
TOP_BAND = BANDS[-1]
# Territories the World Bank does not publish GNI for. Anything absent here keeps the top
# band, so a market we cannot classify is never silently discounted.
MANUAL_GNI = {
    "XKS": 6_200,   # Kosovo — World Bank reports it under a non-ISO3 code.
}


def asc(method, path, body=None, tries=5):
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


def cached(name, path):
    """GETs are cached: an equalization table is large, static, and re-fetching it on every
    dry run is what trips Apple's rate limiter mid-plan. Pages are followed to the end —
    a price point list stops at 200 an item well short of the top of the ladder."""
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, name + ".json")
    if os.path.exists(f):
        return json.load(open(f))
    data, included, next_path, pages = [], [], path, 0
    while next_path and pages < 25:
        code, payload = asc("GET", next_path)
        if code != "200" or "data" not in payload:
            sys.exit("GET %s failed (HTTP %s): %s" % (next_path, code, json.dumps(payload)[:300]))
        data += payload["data"]
        included += payload.get("included", [])
        nxt = payload.get("links", {}).get("next")
        next_path = nxt.split("api.appstoreconnect.apple.com", 1)[-1] if nxt else None
        pages += 1
    payload = {"data": data, "included": included}
    json.dump(payload, open(f, "w"))
    return payload


def territory_of(price_point_id):
    """The price point id is base64 of {s: subscription, t: territory, p: tier}."""
    padded = price_point_id + "=" * (-len(price_point_id) % 4)
    return json.loads(base64.b64decode(padded))["t"]


def gni_table():
    out = {}
    for row in json.load(open("aso/gni-worldbank.json"))[1]:
        if row["value"] and row["countryiso3code"]:
            out[row["countryiso3code"]] = row["value"]
    out.update(MANUAL_GNI)
    return out


def band_for(gni):
    if gni is None:
        return TOP_BAND
    for band in BANDS:
        if gni < band[0]:
            return band
    return TOP_BAND


def anchor_points(sub_id, kind):
    """US price point ids for every band anchor, for one subscription."""
    page = cached("pp_%s_USA" % kind,
                  "/v1/subscriptions/%s/pricePoints?filter%%5Bterritory%%5D=USA&limit=200" % sub_id)
    by_price = {p["attributes"]["customerPrice"]: p["id"] for p in page["data"]}
    index = 1 if kind == "monthly" else 2
    out = {}
    for band in BANDS:
        price = band[index]
        if price not in by_price:
            sys.exit("%s: Apple has no US price point at %s" % (kind, price))
        out[price] = by_price[price]
    return out


def equalized(kind, anchor_price, anchor_id):
    """Apple's own counterpart of a US anchor in every other territory."""
    page = cached("eq_%s_%s" % (kind, anchor_price.replace(".", "_")),
                  "/v1/subscriptionPricePoints/%s/equalizations?limit=200" % anchor_id)
    return {territory_of(p["id"]): (p["id"], p["attributes"]["customerPrice"])
            for p in page["data"]}


def live_prices(sub_id, kind):
    page = cached("live_%s" % kind,
                  "/v1/subscriptions/%s/prices?include=subscriptionPricePoint,territory&limit=200" % sub_id)
    included = {i["id"]: i for i in page.get("included", [])}
    out = {}
    for row in page["data"]:
        rel = row["relationships"]
        point = rel.get("subscriptionPricePoint", {}).get("data") or {}
        terr = (rel.get("territory", {}).get("data") or {}).get("id")
        attrs = included.get(point.get("id"), {}).get("attributes", {})
        out[terr] = {"price_id": row["id"], "point_id": point.get("id"),
                     "customer_price": attrs.get("customerPrice")}
    return out


def plan(kind):
    """One row per territory: (territory, gni, anchor, live price, target price, point id, changes)."""
    sub_id = SUBSCRIPTIONS[kind]
    index = 1 if kind == "monthly" else 2
    gni = gni_table()
    anchors = anchor_points(sub_id, kind)
    tables = {price: equalized(kind, price, anchors[price]) for price in anchors}
    live = live_prices(sub_id, kind)

    rows = []
    for terr in sorted(live):
        band = band_for(gni.get(terr))
        anchor = band[index]
        current = live[terr]["customer_price"]
        keep = (terr, gni.get(terr), anchor, current, current, None, False)

        # The top band is today's price, and the US is the anchor itself: leave both alone
        # rather than rewrite them to the value they already hold.
        if band is TOP_BAND or terr == "USA":
            rows.append(keep)
            continue
        point = tables[anchor].get(terr)
        if not point:
            # Apple does not equalize this anchor here; leaving the price as is beats guessing.
            rows.append(keep)
            continue
        point_id, target = point
        rows.append((terr, gni.get(terr), anchor, current, target,
                     point_id, point_id != live[terr]["point_id"]))
    return rows


def apply(kind, rows, start_date):
    """Schedule one price change per changed territory.

    `startDate` is not optional here. Omitting it asks Apple to create the subscription's
    *initial* price, which an approved subscription already has — that is the 409
    "Initial price cannot be created again after subscription is approved".

    `preserveCurrentPrice: False` passes the new price to existing subscribers as well.
    Every change in this plan is a reduction, so that hands current subscribers the lower
    price rather than grandfathering them onto the higher one.
    """
    sub_id = SUBSCRIPTIONS[kind]
    failures = []
    changing = [r for r in rows if r[6]]
    for i, (terr, _, _, current, target, point_id, _) in enumerate(changing, 1):
        code, payload = asc("POST", "/v1/subscriptionPrices", {
            "data": {
                "type": "subscriptionPrices",
                "attributes": {"preserveCurrentPrice": False, "startDate": start_date},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point_id}},
                },
            }
        })
        ok = code in ("200", "201")
        print("  %-4s %-3d/%-3d %s->%s  %s" % (terr, i, len(changing), current, target, code))
        if not ok:
            failures.append((terr, json.dumps(payload, ensure_ascii=False)[:200]))
    return failures


def main():
    # Apple schedules a price change from a date, and will not accept today's.
    start_date = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
    total_failures = []
    print("scheduled start date:", start_date, "\n")
    for kind in ("monthly", "yearly"):
        rows = plan(kind)
        changing = [r for r in rows if r[6]]
        print("=" * 72)
        print("%s — %d of %d territories change" % (kind.upper(), len(changing), len(rows)))
        print("=" * 72)
        print("%-5s %-10s %-8s %-12s %s" % ("terr", "GNI/cap", "band", "live", "new"))
        for terr, gni, anchor, current, target, _, changes in rows:
            if not changes:
                continue
            print("%-5s %-10s US$%-5s %-12s %s" % (
                terr, ("%d" % gni) if gni else "n/d", anchor, current, target))
        by_band = {}
        for _, _, anchor, _, _, _, changes in rows:
            if changes:
                by_band[anchor] = by_band.get(anchor, 0) + 1
        print("\nper band:", ", ".join("US$%s x%d" % (a, n) for a, n in sorted(by_band.items())))
        print("unchanged:", len(rows) - len(changing))
        if not DRY:
            print("\nwriting %d prices..." % len(changing))
            total_failures += [(kind,) + f for f in apply(kind, rows, start_date)]
        print()

    for f in total_failures:
        print("FAIL", f)
    print("MODE:", "DRY RUN — pass --write to apply" if DRY else
          "WROTE (%d failures)" % len(total_failures))
    return 1 if total_failures else 0


if __name__ == "__main__":
    sys.exit(main())
