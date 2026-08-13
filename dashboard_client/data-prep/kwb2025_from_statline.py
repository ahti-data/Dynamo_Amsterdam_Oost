# -*- coding: utf-8 -*-
"""
Zet de CBS StatLine "onbewerkte dataset"-export van tabel 86165NED (Kerncijfers
wijken en buurten 2025) om naar hetzelfde platte, brede Excel-formaat als
kwb-2016.xls .. kwb2024.xlsx, zodat build_data.py's load_year() ONGEWIJZIGD
blijft werken.

Waarom nodig: CBS publiceert de 2025-editie niet (meer) als kant-en-klare Excel
op de KWB-reekspagina — "download volledige tabel" geeft dezelfde StatLine-
bundel terug (bevestigd). Die bundel is relationeel/lang: Observations.csv
heeft één rij per (regio, meting) met StatLine's eigen metingscodes (T001036,
3000, ...) i.p.v. de CBS-mnemonics (a_inw, a_man, ...) die de rest van dit
project gebruikt. Dit script pivotteert en hernoemt.

Crosswalk (StatLine-Identifier -> CBS-mnemonic) is opgesteld door de Title-tekst
van elke van de 121 metingen in MeasureCodes.csv te vergelijken met de
kolomnamen van kwb2024.xlsx — zie MEASURE_MAP. Alle 117 benodigde datakolommen
hebben een match; nul weesposten aan beide kanten (121 metingen − 4 structurele
regio-metingen = 117 = exact het aantal datakolommen in kwb2024.xlsx).

Gecontroleerd (aug. 2026, tegen kwb2024.xlsx): van de 117 gematchte metingen
hebben 80 daadwerkelijk waarnemingen in Observations.csv, met plausibele,
kleine YoY-veranderingen t.o.v. 2024 (bijv. Amsterdam a_inw 931.298 -> 934.526,
a_65_oo 126.480 -> 129.924) — dat bevestigt de crosswalk, geen toeval.

NOT_PUBLISHED_YET_2025 (37 kolommen) hebben AANTOONBAAR NUL waarnemingen in
Observations.csv (gecontroleerd door het volledige bestand te scannen op die
meting-codes) — geen mapping- of parsefout, maar CBS die deze thema's nog niet
heeft gepubliceerd voor verslagjaar 2025. Bevestigd door de tabel-metadata zelf
(Properties.csv): "De voorlopige cijfers over 2025 verschijnen eind 2026 in
deze tabel." Deze kolommen blijven daarom leeg (missing, geen 0) voor 2025 —
consistent met de bestaande aanname "KWB2025 voorlopig: beschikbare jaren per
indicator empirisch bepaald" (build_data.py). Opnieuw draaien zodra CBS deze
thema's aanvult (verwacht: eind 2026) zou ze automatisch laten meekomen.

Draai dit script vóór build_data.py — het overschrijft het lege
data-prep/kwb/kwb2025.xlsx-placeholderbestand. build_data.py zelf verandert niet.
"""
import re
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "external-data" / "raw" / "86165NED-202606250000"
OUT = ROOT / "data-prep" / "kwb" / "kwb2025.xlsx"

# StatLine measure-Identifier -> CBS KWB-mnemonic (kolomnaam in kwb2024.xlsx)
MEASURE_MAP = {
    "T001036": "a_inw", "3000": "a_man", "4000": "a_vrouw",
    "10680": "a_00_14", "53050": "a_15_24", "53310": "a_25_44",
    "53715": "a_45_64", "80200": "a_65_oo",
    "1010": "a_ongeh", "1020": "a_gehuwd", "1080": "a_gesch", "1050": "a_verwed",
    "1012600_1": "a_nl_all", "H007933_1": "a_eur_al", "H008859_1": "a_neu_al",
    "1012600_2": "a_geb_nl", "H007933_2": "a_geb_eu", "H008859_2": "a_geb_ne",
    "H007933_3": "a_gbl_eu", "H008859_3": "a_gbl_ne",
    "M000173_1": "a_geb", "M000173_2": "p_geb",
    "M000179_1": "a_ste", "M000179_2": "p_ste",
    "1050010_2": "a_hh", "1050015": "a_1p_hh", "1016040": "a_hh_z_k", "1016030": "a_hh_m_k",
    "M000114": "g_hhgro", "M000100": "bev_dich",
    "M000297": "a_woning", "M003003": "a_nb_won", "M008258": "a_vastg", "M008211": "a_nb_vastg",
    "M001642": "g_wozbag",
    "ZW10290": "p_1gezw", "ZW25805": "p_1gezw_tw", "ZW25806": "p_1gezw_hw",
    "ZW10300": "p_1gezw_2w", "ZW10320": "p_1gezw_hvw", "ZW10340": "p_mgezw",
    "M008208": "p_leegsw", "1014800": "p_koopw", "1014850_2": "p_huurw",
    "A047047": "p_wcorpw", "A047048": "p_ov_hw",
    "M008209": "p_bj_me10", "M008210": "p_bj_mi10",
    "M000221_2": "g_ele", "M008294": "g_ele_tr", "M000219_2": "g_gas",
    "M000369": "p_stadsv", "M008295": "p_won_z", "M008296": "p_won_m",
    "M008297": "p_won_zs", "M008298": "p_won_ev", "M008299": "a_lp_pub",
    "A025301": "a_ons_po", "T001345": "a_ons_vovavo", "A041867": "a_ons_mbo",
    "A025294": "a_ons_hbo", "A025297": "a_ons_wo",
    "2018700": "a_opl_bvm", "2018740": "a_opl_hvm", "2018790": "a_opl_hw",
    "M008300": "a_arb_wz", "M001796_2": "p_arb_pp",
    "2021320": "p_arb_wn", "2021330": "p_arb_wv", "2021340": "p_arb_wf", "2021380": "p_arb_zs",
    "M000232": "a_inkont", "M000223": "g_ink_po", "M000224": "g_ink_pi",
    "D000187": "p_ink_li", "D000185": "p_ink_hi", "M008349": "p_ink_ar", "M008348": "p_ink_ba",
    "M000222": "g_hh_sti", "D000186": "p_hh_li", "D000184": "p_hh_hi", "M000939": "m_hh_ver",
    "D006842": "a_soz_wb", "D006837": "a_soz_ao", "D001827": "a_soz_ww", "D000193": "a_soz_ow",
    "T001203": "a_jz_tn", "A045561": "p_jz_tn",
    "M001342_1": "a_wmo_t", "M001342_2": "p_wmo_t",
    "M000200_2": "a_bedv", "301000": "a_bed_a", "300003": "a_bed_bf", "300005": "a_bed_gi",
    "383105": "a_bed_hj", "300009": "a_bed_kl", "300010": "a_bed_mn",
    "300012": "a_bed_oq", "300014": "a_bed_ru",
    "A018943_2": "a_pau", "A019276": "a_bst_b", "D001045": "a_bst_nb",
    "M000368": "g_pau_hh", "A018943_4": "g_pau_km", "A018944": "a_m2w",
    "D000028": "g_afs_hp", "D000025": "g_afs_gs", "D000029": "g_afs_kv",
    "D000045": "g_afs_sc", "D000263": "g_3km_sc",
    "T001455_2": "a_opp_ha", "A047044": "a_lan_ha", "A047040": "a_wat_ha",
    "PC000C": "pst_mvp", "M000217": "pst_dekp",
    "ST0001": "ste_mvs", "ST0003": "ste_oad",
}

# Bevestigd nul waarnemingen in Observations.csv (aug. 2026) — zie docstring.
# CBS publiceert deze thema's later in 2025 nog niet; PASJaar heropvoeren zodra
# CBS aanvult. Niet aanwezig hierin = niet gemapt (geen weesposten in MEASURE_MAP
# voor deze mnemonics uitsluiten — ze staan er wél in, maar leveren simpelweg
# geen kolom op na de pivot, wat build_kwb2025() automatisch afhandelt).
NOT_PUBLISHED_YET_2025 = {
    "a_geb", "p_geb", "a_ste", "p_ste",
    "a_opl_bvm", "a_opl_hvm", "a_opl_hw",
    "a_arb_wz", "p_arb_pp", "p_arb_wn", "p_arb_wv", "p_arb_wf", "p_arb_zs",
    "a_inkont", "g_ink_po", "g_ink_pi", "p_ink_li", "p_ink_hi", "p_ink_ar", "p_ink_ba",
    "g_hh_sti", "p_hh_li", "p_hh_hi", "m_hh_ver",
    "a_wmo_t", "p_wmo_t", "a_jz_tn", "p_jz_tn",
    "g_ele", "g_ele_tr", "g_gas", "p_stadsv",
    "p_won_z", "p_won_m", "p_won_zs", "p_won_ev", "a_lp_pub",
}

_RECS_BY_PREFIX = {"GM": "Gemeente", "WK": "Wijk", "BU": "Buurt"}
_WIJKNUM_PREFIX = re.compile(r"^Wijk \d+\s+")


def _recs_for(code: str) -> str:
    return "Land" if code == "NL00" else _RECS_BY_PREFIX.get(code[:2], "Onbekend")


def build_kwb2025() -> pd.DataFrame:
    obs = pd.read_csv(SRC / "Observations.csv", sep=";", dtype=str)
    codes = pd.read_csv(SRC / "WijkenEnBuurtenCodes.csv", sep=";", dtype=str)
    measures = pd.read_csv(SRC / "MeasureCodes.csv", sep=";", dtype=str)

    string_measures = set(measures.loc[measures["DataType"] == "String", "Identifier"])
    obs = obs[obs["Measure"].isin(MEASURE_MAP)].copy()
    obs["mnemonic"] = obs["Measure"].map(MEASURE_MAP)
    obs["val"] = obs.apply(
        lambda r: r["StringValue"].strip()
        if r["Measure"] in string_measures and pd.notna(r["StringValue"])
        else r["Value"],
        axis=1,
    )

    wide = obs.pivot_table(index="WijkenEnBuurten", columns="mnemonic", values="val", aggfunc="first")
    wide = wide.reset_index().rename(columns={"WijkenEnBuurten": "gwb_code_10"})

    title_by_code = dict(zip(codes["Identifier"], codes["Title"]))
    parent_by_code = dict(zip(codes["Identifier"], codes["DimensionGroupId"]))

    def resolve_gm_naam(code: str) -> str:
        if code == "NL00":
            return "Nederland"
        if code.startswith("GM"):
            return title_by_code.get(code, "")
        return title_by_code.get(parent_by_code.get(code, ""), "")  # WK/BU: parent IS de gemeente

    wide["recs"] = wide["gwb_code_10"].map(_recs_for)
    wide["regio"] = wide["gwb_code_10"].map(
        lambda c: _WIJKNUM_PREFIX.sub("", str(title_by_code.get(c, "")).strip())
    )
    wide["gm_naam"] = wide["gwb_code_10"].map(resolve_gm_naam)
    wide["gwb_code"] = wide["gwb_code_10"]
    wide["gwb_code_8"] = wide["gwb_code_10"].map(lambda c: "0000" if c == "NL00" else c[2:])
    wide["ind_wbi"] = wide["recs"].map(lambda r: "." if r == "Land" else "1")

    struct_cols = ["gwb_code_10", "gwb_code_8", "regio", "gm_naam", "recs", "gwb_code", "ind_wbi"]
    data_cols = [c for c in MEASURE_MAP.values() if c in wide.columns]
    return wide[struct_cols + data_cols]


if __name__ == "__main__":
    df = build_kwb2025()
    print(f"{len(df)} regio's, {len(df.columns)} kolommen")
    missing = set(MEASURE_MAP.values()) - set(df.columns)
    expected = missing & NOT_PUBLISHED_YET_2025
    unexpected = missing - NOT_PUBLISHED_YET_2025
    if expected:
        print(f"·· {len(expected)} kolommen nog niet gepubliceerd door CBS voor 2025 (verwacht, zie docstring):", sorted(expected))
    if unexpected:
        print(f"!! ONVERWACHT ontbrekend (nieuwe crosswalk-controle nodig):", sorted(unexpected))
    print("recs-verdeling:", df["recs"].value_counts().to_dict())
    df.to_excel(OUT, index=False)
    print(f"geschreven: {OUT}")
