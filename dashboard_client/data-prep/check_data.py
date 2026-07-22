# -*- coding: utf-8 -*-
"""
Dataregressietests voor de gegenereerde bundels (review #21).
Draaien na iedere build: python data-prep/check_data.py
Faalt met exitcode 1 zodra een acceptatiecriterium wordt geschonden.
"""
import json
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "dashboard" / "public" / "data"
fouten: list[str] = []


def check(cond: bool, msg: str):
    if cond:
        print(f"  OK  {msg}")
    else:
        fouten.append(msg)
        print(f"  !!  FOUT: {msg}")


index = json.loads((OUT / "index.json").read_text(encoding="utf-8"))
print(f"index: {len(index['gemeenten'])} gemeenten, default {index['default']}")

for g in index["gemeenten"]:
    code = g["code"]
    b = json.loads((OUT / "gm" / f"{code}.json").read_text(encoding="utf-8"))
    n_ind = len(b["indicators"])
    wijken = [r for r in b["regions"] if r["level"] == "wijk"]
    print(f"\n{code} ({g['naam']}): {n_ind} indicatoren, {len(wijken)} wijken")
    # iedere gemeente heeft bruikbare indicatoren (review P0-1: Ouder-Amstel)
    check(n_ind > 0, f"{code}: minimaal 1 indicator")
    # geen indicator zonder jaargangen
    leeg = [i["id"] for i in b["indicators"] if not i["years"]]
    check(not leeg, f"{code}: geen indicator met lege jarenlijst {leeg}")
    # elke indicator heeft een richting
    zonder = [i["id"] for i in b["indicators"] if i.get("direction") not in ("hoog", "laag", "neutraal")]
    check(not zonder, f"{code}: elke indicator heeft een richting {zonder}")
    # geometrie sluit aan op de regiocodes
    for lvl, suffix in [("wijk", "_wijken"), ("buurt", "_buurten")]:
        gf = OUT / "gm" / f"{code}{suffix}.geojson"
        if gf.exists():
            geo = json.loads(gf.read_text(encoding="utf-8"))
            codes = {r["code"] for r in b["regions"] if r["level"] == lvl}
            geocodes = {f["properties"]["code"] for f in geo["features"]}
            check(geocodes <= codes, f"{code}: {suffix}-geometrie matcht regiocodes "
                                     f"({len(geocodes - codes)} onbekend)")

# Amsterdam-specifiek
ams = json.loads((OUT / "gm" / "GM0363.json").read_text(encoding="utf-8"))
years = ams["years"]
vals = ams["values"]
print("\nAmsterdam-acceptatiecriteria:")
yi16 = years.index(2016)
yi24 = years.index(2024)

# 2016 in Oost aanwezig (review P0-2)
check(vals["SD-M"]["a_inw"][yi16] is not None, "stadsdeel Oost heeft a_inw voor 2016")
oost_wijken = [r["code"] for r in ams["regions"] if r["level"] == "wijk" and r.get("sd") == "SD-M"]
filled16 = sum(1 for w in oost_wijken if vals[w].get("a_inw", [None] * len(years))[yi16] is not None)
check(filled16 == 15, f"alle 15 Oost-wijken hebben a_inw 2016 (nu {filled16})")

# één-wijkgebieden gevuld (review P0-4)
for c in ("GB-GF06", "GB-GT21"):
    cells = sum(1 for arr in vals.get(c, {}).values() for v in arr if v is not None)
    reg = next(r for r in ams["regions"] if r["code"] == c)
    check(cells > 0 and reg.get("members") == 1, f"{c}: gevuld aggregaat met dekking 1/1 wijk")

# mediaan niet op aggregaten (review #11)
agg = [r["code"] for r in ams["regions"] if r["level"] in ("stadsdeel", "gebied")]
lekken = [c for c in agg if any(v is not None for v in vals.get(c, {}).get("m_hh_ver", []))]
check(not lekken, f"mediaan vermogen ontbreekt bewust op aggregaten {lekken}")

# gebieden: 25 officiële + Westpoort
gebieden = [r for r in ams["regions"] if r["level"] == "gebied"]
check(len(gebieden) == 26 and any(r["code"] == "GB-westpoort" for r in gebieden),
      "25 GGW-gebieden + apart Westpoort aanwezig")

# consistentie: Oost-som wijken ~ aggregaat 2024
som = sum(vals[w]["a_inw"][yi24] for w in oost_wijken)
check(abs(som - vals["SD-M"]["a_inw"][yi24]) < 1, "som Oost-wijken == stadsdeelaggregaat (2024)")

# gentrificatie: config aanwezig + WOZ-reeks continu over de g_woz->g_wozbag breuk
check("gentrification" in ams and len(ams["gentrification"]["components"]) == 4,
      "gentrificatieconfig met 4 componenten aanwezig")
woz = vals["SD-M"].get("g_wozbag", [None] * len(years))
woz_years = [years[i] for i in range(len(years)) if woz[i] is not None]
check(2016 in woz_years and 2025 in woz_years,
      f"WOZ-reeks Oost loopt 2016–2025 (nu {len(woz_years)} jaren)")
# geen sprong bij de naamswijziging 2019->2020 (mag stijgen, niet halveren/verdubbelen)
if woz[years.index(2019)] and woz[years.index(2020)]:
    ratio = woz[years.index(2020)] / woz[years.index(2019)]
    check(1.0 < ratio < 1.4, f"WOZ continu over g_woz->g_wozbag breuk (ratio {ratio:.2f})")
# WOZ woning-gewogen op aggregaat, niet inwoner-gewogen: plausibele orde van grootte
check(300_000 < woz[yi24] < 900_000, f"WOZ Oost 2024 plausibel (€{woz[yi24]:,.0f})")

# DATA-1/2: codehergebruik bij herverkaveling mag geen spookbreuk geven.
# Controleer over ALLE gemeenten dat a_inw geen onmogelijke sprong maakt tussen
# opeenvolgende gevulde jaren (nieuwbouw uitgezonderd via ruime drempel), en
# specifiek Zoetermeer/Diemen op naam-continuïteit van de gekoppelde reeks.
import glob
def series_jumps(bundle):
    # echte miskoppeling door codehergebruik toont zich als een grote WIJK-sprong
    # (duizenden inwoners); kleine-buurt afronding (5-tallen) is legitieme ruis en
    # wordt uitgesloten via de absolute drempel.
    yy = bundle["years"]; bad = []
    for r in bundle["regions"]:
        if r["level"] != "wijk":
            continue
        s = bundle["values"].get(r["code"], {}).get("a_inw")
        if not s:
            continue
        prev = prev_i = None
        for i, v in enumerate(s):
            if v is None or v == 0:
                continue
            if prev is not None and min(v, prev) > 1000 and (v / prev > 2.5 or prev / v > 2.5):
                bad.append((r["code"], r["name"], yy[prev_i], prev, yy[i], v))
            prev, prev_i = v, i
    return bad

zj = series_jumps(json.loads((OUT / "gm" / "GM0637.json").read_text(encoding="utf-8")))
check(not zj, f"Zoetermeer: geen wijk-spookbreuken in a_inw (nu {zj})")
dj = series_jumps(json.loads((OUT / "gm" / "GM0384.json").read_text(encoding="utf-8")))
check(not dj, f"Diemen: geen wijk-spookbreuken in a_inw (nu {dj})")
total_jumps = []
for f in glob.glob(str(OUT / "gm" / "GM*.json")):
    total_jumps += series_jumps(json.loads(open(f, encoding="utf-8").read()))
# resterende grote wijk-sprongen zijn echte nieuwbouw (bijv. IJburg/Strandeiland)
check(len(total_jumps) <= 6, f"nauwelijks wijk-spookbreuken over 35 gemeenten (nu {len(total_jumps)}: {[(j[1],j[3],j[5]) for j in total_jumps][:6]})")

# RIVM-uitkomsten: aanwezig, gemodelleerd, meetjaren, plausibele percentages
outcome = [i for i in ams["indicators"] if i.get("isOutcome")]
check(len(outcome) >= 15, f"RIVM-uitkomstindicatoren aanwezig ({len(outcome)})")
check(all(i.get("estimateType") == "gemodelleerd" for i in outcome),
      "alle uitkomsten gemarkeerd als gemodelleerd")
ind_out = {i["id"]: i for i in outcome}
eenz = ind_out.get("o_eenzaam")
if eenz:
    check(set(eenz["years"]) >= {2016, 2020, 2022, 2024},
          f"eenzaamheid heeft de RIVM-meetjaren ({eenz['years']})")
    # waarde op een Oost-wijk plausibel (0-100)
    yi = years.index(2024)
    v = vals["WK0363ME"].get("o_eenzaam", [None] * len(years))[yi]
    check(v is not None and 0 <= v <= 100, f"eenzaamheid Dapperbuurt 2024 = {v} (0-100%)")
# correlatie-meta aanwezig
check("correlation" in ams and ams["correlation"]["rivmMeetjaren"],
      "correlatie-meta met RIVM-meetjaren aanwezig")
# buurtniveau heeft uitkomsten
bu_out = sum(1 for c in vals if c.startswith("BU0363") and vals[c].get("o_eenzaam"))
check(bu_out > 40, f"uitkomsten ook op buurtniveau ({bu_out} buurten met eenzaamheid)")

print(f"\n{'ALLE CHECKS GESLAAGD' if not fouten else f'{len(fouten)} FOUTEN'}")
sys.exit(1 if fouten else 0)
