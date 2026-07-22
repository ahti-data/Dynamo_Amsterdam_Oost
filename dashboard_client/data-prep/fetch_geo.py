# -*- coding: utf-8 -*-
"""
Haalt wijk- en buurtgeometrieën op bij PDOK (CBS Gebiedsindelingen) voor de
gemeenten in build_data.GEMEENTEN, in de indeling die aansluit op de nieuwste
KWB-jaargang. Draaien vóór build_data.py wanneer een gemeente of jaargang wijzigt.
"""
import json
from pathlib import Path

import requests

from build_data import GEMEENTEN

JAAR = "2025"  # moet aansluiten op de nieuwste KWB-jaargang (regiocodes!)
WFS = f"https://service.pdok.nl/cbs/gebiedsindelingen/{JAAR}/wfs/v1_0"
OUT = Path(__file__).resolve().parent / "geo" / "gm"
OUT.mkdir(parents=True, exist_ok=True)


def fetch(typename: str, prefix: str) -> list:
    """Alle features waarvan statcode met prefix begint (paginerend)."""
    feats = []
    start = 0
    while True:
        r = requests.get(WFS, params={
            "service": "WFS", "version": "2.0.0", "request": "GetFeature",
            "typeNames": typename, "outputFormat": "json", "srsName": "EPSG:4326",
            "count": "1000", "startIndex": str(start),
            "filter": f"""<fes:Filter xmlns:fes="http://www.opengis.net/fes/2.0">
              <fes:PropertyIsLike wildCard="*" singleChar="." escapeChar="!">
                <fes:ValueReference>statcode</fes:ValueReference>
                <fes:Literal>{prefix}*</fes:Literal>
              </fes:PropertyIsLike></fes:Filter>""",
        }, timeout=120)
        r.raise_for_status()
        page = r.json()["features"]
        feats.extend(page)
        if len(page) < 1000:
            return feats
        start += 1000


def round_coords(c, nd=5):
    if isinstance(c, (int, float)):
        return round(c, nd)
    return [round_coords(x, nd) for x in c]


def main():
    for gm in GEMEENTEN:
        digits = gm[2:]
        for typename, kind, pre in [
            ("wijk_gegeneraliseerd", "wijken", "WK"),
            ("buurt_gegeneraliseerd", "buurten", "BU"),
        ]:
            feats = fetch(typename, f"{pre}{digits}")
            out = {"type": "FeatureCollection", "features": [{
                "type": "Feature",
                "properties": {"statcode": f["properties"]["statcode"],
                               "statnaam": f["properties"]["statnaam"]},
                "geometry": {"type": f["geometry"]["type"],
                             "coordinates": round_coords(f["geometry"]["coordinates"])},
            } for f in feats]}
            path = OUT / f"{gm}_{kind}.geojson"
            path.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
            print(f"OK {path.name}: {len(feats)} features ({path.stat().st_size/1024:.0f} kB)")


if __name__ == "__main__":
    main()
