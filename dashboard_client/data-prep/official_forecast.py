# -*- coding: utf-8 -*-
"""
Officiële externe puntprognoses voor stadsdeel Oost, los van de intern
getrokken trendprognose (dashboard/src/lib/forecast.ts). Twee bronnen, elk
voor wat ze uniek toevoegen (zie docs/AANNAMES.md §11):

- O&S-bevolkingsprognose 2026 (Excel, per wijk + stadsdeel Oost, 5-jaars
  leeftijdsklassen): external-data/raw/amsterdam_ois_bevolkingsprognose_oost/
  -> a_00_14 / a_15_24 / a_45_64 (klassen die niet 1-op-1 in BBGA bestaan).
- BBGA (al gedownload voor de catalogus, external-data/raw/amsterdam_bbga):
  -> a_inw (BEV_PROG) en a_65_oo (BEV65PLUS_PROG), jaarlijks 2027-2055.

Beide bronnen publiceren geen onzekerheidsinterval — er is dus bewust geen
band voor deze punten (zie Vooruitblik.tsx).

Dekking is beperkt tot stadsdeel M (Oost) en zijn 15 wijken (WK0363MA..MQ);
geen buurt- of gebiedsniveau (geen van beide bronnen publiceert dat, om
privacy-/betrouwbaarheidsredenen). Ontbrekende bronbestanden geven een lege
dict terug (met waarschuwing) zodat de build niet breekt voor wie deze
optionele bronnen niet lokaal heeft.

Retourneert: {regiocode: {indicatorId: {jaar: waarde}}}, te zetten onder
bundle["officialForecast"] in build_data.py (alleen voor GM0363).
"""
import re
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
OS_XLSX = (
    ROOT / "external-data" / "raw" / "amsterdam_ois_bevolkingsprognose_oost"
    / "2026_bevolkingsprognose_stadsdeel_wijken_M_Oost.xlsx"
)
BBGA_CSV = ROOT / "external-data" / "raw" / "amsterdam_bbga" / "bbga-latest-and-greatest.csv"

OOST_WIJK_LETTERS = "ABCDEFGHJKLMNPQ"  # WK0363MA..MQ (I ontbreekt, net als in build_data.py

# doelgroep (targetGroups.ts) -> (ondergrens, bovengrens) in hele jaren, inclusief
AGE_GROUP_RANGES = {
    "a_00_14": (0, 14),
    "a_15_24": (15, 24),
    "a_45_64": (45, 64),
}

BBGA_TO_REGIO = {"M": "SD-M", **{f"M{l}": f"WK0363M{l}" for l in OOST_WIJK_LETTERS}}
BBGA_VAR_TO_INDICATOR = {"BEV_PROG": "a_inw", "BEV65PLUS_PROG": "a_65_oo"}


def _band_range(label: str):
    """'0- 4 jaar' -> (0,4); '85 jaar of ouder' -> (85, None); 'totaal' -> None.
    Regex i.p.v. letterlijke stringmatch, want de O&S-cellen zijn onregelmatig
    gespatieerd ('0- 4 jaar', '5- 9 jaar') door rechts uitgelijnde brontabel."""
    nums = [int(n) for n in re.findall(r"\d+", label)]
    if len(nums) == 2:
        return nums[0], nums[1]
    if len(nums) == 1 and ("ouder" in label.lower() or "plus" in label.lower()):
        return nums[0], None
    return None


def _wijk_sheet_code(sheet_name: str):
    """'MA_Oostelijk Havengebied' -> 'WK0363MA'; None voor niet-Oost/onbekende sheets."""
    letter = sheet_name.split("_", 1)[0]
    if len(letter) == 2 and letter[0] == "M" and letter[1] in OOST_WIJK_LETTERS:
        return f"WK0363{letter}"
    return None


def _parse_sheet(df: pd.DataFrame, code: str, out: dict) -> None:
    """Eén sheet (stadsdeel- of wijkformaat) -> out[code][group][jaar] = som van
    de leeftijdsklassen die volledig binnen die doelgroep-range vallen. Stopt bij
    de eerste 'totaal'-rij, want de stadsdeel-sheet heeft daarna een tweede tabel
    met een andere (overlappende!) klasse-indeling die anders dubbel zou tellen."""
    label_row = None
    for i in range(min(6, len(df))):
        if str(df.iat[i, 0]).strip().lower() == "leeftijdscategorie":
            label_row = i
            break
    if label_row is None:
        return

    header = df.iloc[label_row]
    # de absolute-waarde-kolom per jaar staat op de oneven kolommen (1,3,5,...);
    # het jaar staat ofwel direct in die cel (stadsdeel-sheet: '2026') ofwel als
    # laatste woord van een label (wijk-sheet: 'aantal 2026').
    year_col: dict[int, int] = {}
    for j in range(1, len(header), 2):
        cell = str(header.iloc[j]).strip()
        token = cell if cell.isdigit() else cell.split()[-1]
        if token.isdigit():
            year_col[int(token)] = j

    for _, row in df.iloc[label_row + 1:].iterrows():
        label = str(row.iloc[0]).strip()
        if label.lower() == "totaal":
            break
        band = _band_range(label)
        if band is None or band[1] is None:
            continue  # open-ended band (85+) hoort niet bij a_00_14/15_24/45_64
        lo, hi = band
        for group, (glo, ghi) in AGE_GROUP_RANGES.items():
            if lo >= glo and hi <= ghi:
                for year, col in year_col.items():
                    try:
                        val = float(row.iloc[col])
                    except (ValueError, TypeError):
                        continue
                    d = out.setdefault(code, {}).setdefault(group, {})
                    d[year] = d.get(year, 0.0) + val


def load_os_xlsx() -> dict:
    if not OS_XLSX.exists():
        print(f"  !! {OS_XLSX.name} ontbreekt — Oost-leeftijdsprognose (0-14/15-24/45-64) overgeslagen")
        return {}
    out: dict = {}
    xls = pd.ExcelFile(OS_XLSX)
    for sheet in xls.sheet_names:
        code = "SD-M" if sheet.startswith("Stadsdeel") else _wijk_sheet_code(sheet)
        if code is None:
            continue
        _parse_sheet(xls.parse(sheet, header=None), code, out)
    return out


def load_bbga() -> dict:
    if not BBGA_CSV.exists():
        print(f"  !! {BBGA_CSV.name} ontbreekt — Oost-inwoners/65+-prognose (BBGA) overgeslagen")
        return {}
    out: dict = {}
    for chunk in pd.read_csv(
        BBGA_CSV, usecols=["jaar", "gebiedcode15", "variabele", "waarde"],
        iterator=True, chunksize=300_000,
    ):
        sel = chunk[
            chunk["variabele"].isin(BBGA_VAR_TO_INDICATOR)
            & chunk["gebiedcode15"].isin(BBGA_TO_REGIO)
            & chunk["waarde"].notna()
        ]
        for _, r in sel.iterrows():
            code = BBGA_TO_REGIO[r["gebiedcode15"]]
            group = BBGA_VAR_TO_INDICATOR[r["variabele"]]
            out.setdefault(code, {}).setdefault(group, {})[int(r["jaar"])] = float(r["waarde"])
    return out


def load_official_forecast() -> dict:
    """{regiocode: {indicatorId: {jaar: waarde}}} voor bundle['officialForecast']."""
    merged = load_os_xlsx()
    for code, groups in load_bbga().items():
        for group, years in groups.items():
            merged.setdefault(code, {}).setdefault(group, {}).update(years)
    return merged


if __name__ == "__main__":
    import json

    result = load_official_forecast()
    print(json.dumps(result, indent=2, ensure_ascii=False))
    n_points = sum(len(years) for groups in result.values() for years in groups.values())
    print(f"\n{len(result)} regio's, {n_points} (regio, groep, jaar)-punten")
