# -*- coding: utf-8 -*-
"""
Bouwt per gemeente een databundel uit de CBS KWB-bestanden 2016-2025:
  dashboard/public/data/index.json           — beschikbare gemeenten
  dashboard/public/data/gm/<GM>.json         — regio's, indicatoren, waarden
  dashboard/public/data/gm/<GM>_*.geojson    — wijk-/buurt-/gebiedsgeometrieën

Verwerkt de bevindingen van het specialistenteam:
- regiokoppeling over jaargangen: eerst op code, dan op genormaliseerde naam
  (Amsterdam wisselde in 2023 van wijkcodes; Oost-mapping expliciet geverifieerd)
- Amsterdamse gebiedsindeling (25 gebieden) uit data-prep/gebieden_amsterdam.json
- parseerregels CBS: '.' = missing, decimaalkomma, voorloopspaties, trailing spaces
- hernoeming opleiding: a_opl_lg/md/hg (t/m 2022) == a_opl_bvm/hvm/hw (2023+)
- KWB2025 voorlopig: beschikbare jaren per indicator empirisch bepaald
- aggregatie stadsdeel/gebied: sommen + gewogen gemiddelden, >=80% gevuld
"""
import json
import math
import re
import shutil
from datetime import date
from pathlib import Path

import pandas as pd

from official_forecast import load_official_forecast

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dashboard" / "public" / "data"
GEO_SRC = ROOT / "data-prep" / "geo" / "gm"
KWB = ROOT / "data-prep" / "kwb"
(OUT / "gm").mkdir(parents=True, exist_ok=True)

FILES = {
    2016: KWB / "kwb-2016.xls",
    2017: KWB / "kwb-2017.xls",
    2018: KWB / "kwb-2018.xls",
    2019: KWB / "kwb-2019.xlsx",
    2020: KWB / "kwb-2020.xlsx",
    2021: KWB / "kwb-2021.xlsx",
    2022: KWB / "kwb-2022.xlsx",
    2023: KWB / "kwb2023.xlsx",
    2024: KWB / "kwb2024.xlsx",
    2025: KWB / "kwb2025.xlsx",
}
YEARS = sorted(FILES)
NL = "NL00"

# gemeenten in de tool; uitbreiden = code+naam toevoegen en script draaien
# (geometrie komt uit data-prep/geo/gm/, zie geo-specialist / README)
GEMEENTEN = {
    # alle gemeenten met >= 100.000 inwoners (KWB 2025), 32 stuks
    "GM0363": "Amsterdam", "GM0599": "Rotterdam", "GM0518": "'s-Gravenhage",
    "GM0344": "Utrecht", "GM0772": "Eindhoven", "GM0014": "Groningen",
    "GM0855": "Tilburg", "GM0034": "Almere", "GM0268": "Nijmegen",
    "GM0758": "Breda", "GM0202": "Arnhem", "GM0392": "Haarlem",
    "GM0200": "Apeldoorn", "GM0394": "Haarlemmermeer", "GM0307": "Amersfoort",
    "GM0479": "Zaanstad", "GM0153": "Enschede", "GM0796": "'s-Hertogenbosch",
    "GM0193": "Zwolle", "GM0546": "Leiden", "GM0080": "Leeuwarden",
    "GM0637": "Zoetermeer", "GM0935": "Maastricht", "GM0228": "Ede",
    "GM0505": "Dordrecht", "GM1783": "Westland", "GM0484": "Alphen aan den Rijn",
    "GM0361": "Alkmaar", "GM0503": "Delft", "GM0114": "Emmen",
    "GM0150": "Deventer", "GM0983": "Venlo",
    # kleine Amsterdamse buurgemeenten als regiocontext (<100k, bewust behouden)
    "GM0362": "Amstelveen", "GM0384": "Diemen", "GM0437": "Ouder-Amstel",
}
DEFAULT_GM = "GM0363"

# expliciet geverifieerde koppeling oude->nieuwe wijkcodes Amsterdam-Oost
# (data-analist; volgorde kruist bij Dapperbuurt/Transvaalbuurt)
WIJK_MAP_OOST = {
    "WK036327": "WK0363MB", "WK036328": "WK0363MC", "WK036329": "WK0363ME",
    "WK036330": "WK0363MD", "WK036331": "WK0363MF", "WK036332": "WK0363MG",
    "WK036333": "WK0363MA", "WK036334": "WK0363MH", "WK036335": "WK0363MJ",
    "WK036350": "WK0363MK", "WK036351": "WK0363ML", "WK036355": "WK0363MM",
    "WK036356": "WK0363MN", "WK036357": "WK0363MP", "WK036358": "WK0363MQ",
}

_OPL = {"a_opl_lg": "a_opl_bvm", "a_opl_md": "a_opl_hvm", "a_opl_hg": "a_opl_hw"}
# g_woz (t/m 2019) == g_wozbag (vanaf 2020); reeks loopt continu door (geverifieerd
# op Amsterdam: 2019=375, 2020=416 ×€1.000), dus als één WOZ-reeks behandeld
_WOZ = {"g_woz": "g_wozbag"}
# Opleiding: CBS wisselt tussen a_opl_lg/md/hg (2016-2022 én weer 2025) en
# a_opl_bvm/hvm/hw (2023-2024). We passen de _OPL-hernoeming op ELKE jaargang toe
# (no-op waar de bvm-kolommen al bestaan) zodat een toekomstige levering met de
# oude kolomnamen niet stil wordt genegeerd (DATA-4). WOZ alleen t/m 2019.
RENAMES = {y: dict(_OPL) for y in YEARS}
for y in (2016, 2017, 2018, 2019):
    RENAMES[y] = {**_OPL, **_WOZ}

# ---------------------------------------------------------------- indicatoren
BASE_INDICATORS = [
    ("a_inw",    "Aantal inwoners", "Inwoners", "aantal", "hoog",
     "Totaal aantal inwoners. Draagvlak en potentieel bereik van een buurtvoorziening."),
    ("a_hh",     "Huishoudens totaal", "Huishoudens", "aantal", "hoog",
     "Aantal particuliere huishoudens; noemer voor huishoudensaandelen."),
    ("g_hhgro",  "Gemiddelde huishoudensgrootte", "Huishoudensgrootte", "personen", "neutraal",
     "Gemiddeld aantal personen per huishouden; onderscheidt gezinsbuurten van alleenwonenden-buurten."),
    ("bev_dich", "Bevolkingsdichtheid", "Dichtheid", "per_km2", "neutraal",
     "Inwoners per km² land. Hoge dichtheid = groot loopafstand-bereik van een locatie."),
    ("p_geb",    "Geboorten per 1.000 inwoners", "Geboorten", "per_1000", "hoog",
     "Levendgeborenen per 1.000 inwoners; signaal van jonge, groeiende buurten."),
    ("p_ste",    "Sterfte per 1.000 inwoners", "Sterfte", "per_1000", "hoog",
     "Overledenen per 1.000 inwoners; signaal van sterk vergrijsde buurten."),
    ("a_00_14",  "Inwoners 0 t/m 14 jaar", "0–14 jaar", "aantal", "hoog",
     "Doelgroep kinderwerk; absoluut volume bepaalt capaciteitsbehoefte."),
    ("a_15_24",  "Inwoners 15 t/m 24 jaar", "15–24 jaar", "aantal", "hoog",
     "Doelgroep jongerenwerk (jongerencentra, ambulant jongerenwerk)."),
    ("a_hh_m_k", "Huishoudens met kinderen", "Hh. met kinderen", "aantal", "hoog",
     "Gezinsdichtheid; ouders zijn ingang voor opvoedondersteuning en kinderactiviteiten."),
    ("p_jz_tn",  "Jongeren met jeugdzorg in natura", "Jeugdzorg", "pct", "hoog",
     "Percentage van personen tot 23 jaar met jeugdzorg in natura; proxy voor jeugdproblematiek."),
    ("a_65_oo",  "Inwoners 65 jaar en ouder", "65-plussers", "aantal", "hoog",
     "Doelgroep ouderenwerk; absoluut volume bepaalt waar seniorenactiviteiten renderen."),
    ("a_45_64",  "Inwoners 45 t/m 64 jaar", "45–64 jaar", "aantal", "hoog",
     "Aankomende vergrijzing: de ouderen van over 10–20 jaar; lange-termijn locatieperspectief."),
    ("a_soz_ow", "Personen met AOW-uitkering", "AOW-ontvangers", "aantal", "hoog",
     "Feitelijke pensioenpopulatie op registerbasis."),
    ("a_verwed", "Verweduwde inwoners", "Verweduwd", "aantal", "hoog",
     "Verlies van partner is een sterke voorspeller van eenzaamheid; doelgroep ontmoeting."),
    ("g_afs_hp", "Afstand tot huisartsenpraktijk", "Afstand huisarts", "km", "hoog",
     "Gemiddelde afstand tot de huisarts; nabijheid eerstelijnszorg voor minder mobiele ouderen."),
    ("a_soz_wb", "Personen met bijstandsuitkering", "Bijstand", "aantal", "hoog",
     "Kerndoelgroep schuldhulp en sociaal raadslieden (Participatiewet, tot AOW-leeftijd)."),
    ("a_soz_ww", "Personen met WW-uitkering", "WW", "aantal", "hoog",
     "Recente werkloosheid; doelgroep preventieve budgetondersteuning."),
    ("a_soz_ao", "Personen met AO-uitkering", "Arbeidsongeschikt", "aantal", "hoog",
     "Arbeidsongeschiktheid; chronische gezondheidsproblemen onder de beroepsbevolking."),
    ("p_hh_li",  "Huishoudens in laagste 40% inkomens", "Lage inkomens", "pct", "hoog",
     "Aandeel huishoudens in de landelijk laagste 40% inkomens (landelijk gemiddelde = 40%)."),
    ("p_ink_ar", "Personen in armoede", "Armoede", "pct", "hoog",
     "Nieuwe CBS/Nibud/SCP-armoededefinitie, beschikbaar vanaf verslagjaar 2024."),
    ("p_ink_ba", "Personen tot 25% boven armoedegrens", "Rond armoedegrens", "pct", "hoog",
     "Kwetsbare groep net boven de armoedegrens; doelgroep vroegsignalering (vanaf 2024)."),
    ("g_ink_pi", "Gemiddeld inkomen per inwoner", "Inkomen p.p.", "euro", "laag",
     "Gemiddeld persoonlijk inkomen per inwoner (×€1.000 in bron, hier in euro's)."),
    ("m_hh_ver", "Mediaan vermogen huishoudens", "Mediaan vermogen", "euro", "laag",
     "Mediaan vermogen van particuliere huishoudens; lage buffer = snel escalerende schulden."),
    ("p_arb_pp", "Nettoarbeidsparticipatie", "Arbeidsparticipatie", "pct", "laag",
     "Werkzame beroepsbevolking als % van 15–75-jarigen; laag = activeringsopgave."),
    ("a_1p_hh",  "Eenpersoonshuishoudens", "Alleenwonend", "aantal", "hoog",
     "Alleenwonen is de sterkste demografische risicofactor voor eenzaamheid."),
    ("a_hh_z_k", "Meerpersoonshuishoudens zonder kinderen", "Hh. zonder kinderen", "aantal", "neutraal",
     "Completeert het huishoudensbeeld per wijk."),
    ("a_gesch",  "Gescheiden inwoners", "Gescheiden", "aantal", "hoog",
     "Gescheiden alleenstaanden (vaak 45+) zijn een groeiende eenzaamheidsgroep."),
    ("a_nl_all", "Inwoners met herkomst Nederland", "Herkomst NL", "aantal", "neutraal",
     "Herkomstindeling vanaf 2023 (geboren in NL/Europa/buiten Europa); geen trend vóór 2023."),
    ("a_eur_al", "Herkomst Europa (excl. NL)", "Herkomst Europa", "aantal", "hoog",
     "O.a. EU-arbeidsmigranten; vragen rond taal, werk en rechten."),
    ("a_neu_al", "Herkomst buiten Europa", "Herkomst buiten Europa", "aantal", "hoog",
     "Gemiddeld grootste afstand tot voorzieningen; prioriteit cultuursensitief buurtwerk."),
    ("a_gbl_ne", "Geboren buiten NL, herkomst buiten Europa", "1e generatie (buiten Eur.)", "aantal", "hoog",
     "Eerste generatie migranten: meest directe doelgroep taal- en wegwijsondersteuning."),
    ("a_opl_bvm", "Opleidingsniveau laag (15–75 jr)", "Laag opgeleid", "aantal", "hoog",
     "Hoogst behaald: basisonderwijs/vmbo/mbo1. Proxy voor laaggeletterdheid en formulierenhulp. T/m 2022 kolom a_opl_lg."),
    ("a_wmo_t",  "Wmo-cliënten totaal", "Wmo-cliënten", "aantal", "hoog",
     "Personen met Wmo-maatwerkarrangement; volume voor mantelzorgondersteuning."),
    # — wonen & gentrificatie —
    ("g_wozbag", "Gemiddelde WOZ-waarde woningen", "WOZ-waarde", "euro", "neutraal",
     "Gemiddelde WOZ-waarde (×€1.000 in bron). Sterke stijging t.o.v. de stad is een gentrificatiesignaal."),
    ("p_koopw",  "Aandeel koopwoningen", "Koopwoningen", "pct", "neutraal",
     "Percentage koopwoningen in de woningvoorraad; stijging duidt op verkoop van huurwoningen."),
    ("p_wcorpw", "Aandeel corporatiewoningen", "Corporatiewoningen", "pct", "hoog",
     "Percentage woningen van woningcorporaties; concentratie van de sociale huursector en daarmee van de welzijnsdoelgroep."),
    ("p_wmo_t",  "Wmo-cliënten per 1.000 inwoners", "Wmo-dichtheid", "per_1000", "hoog",
     "Concentratie van beperkingen en dus mantelzorgdruk."),
]

# minimale noemer voor een betrouwbaar berekend aandeel (M11): mini-buurten van
# een handvol inwoners geven anders schijnexacte 100%-profielen ("100% verweduwd")
# die de ranglijsten aanvoeren zonder enige statistische betekenis
MIN_DENOM_FOR_PCT = 50

DERIVED = [
    ("p_00_14", "a_00_14", "a_inw", "Aandeel 0 t/m 14 jaar", "% 0–14",
     "Berekend: a_00_14 / a_inw × 100."),
    ("p_15_24", "a_15_24", "a_inw", "Aandeel 15 t/m 24 jaar", "% 15–24",
     "Berekend: a_15_24 / a_inw × 100."),
    ("p_65_oo", "a_65_oo", "a_inw", "Aandeel 65-plus", "% 65+",
     "Berekend: a_65_oo / a_inw × 100."),
    ("p_1p_hh", "a_1p_hh", "a_hh", "Aandeel eenpersoonshuishoudens", "% alleenwonend",
     "Berekend: a_1p_hh / a_hh × 100."),
    ("p_hh_m_k", "a_hh_m_k", "a_hh", "Aandeel huishoudens met kinderen", "% hh. met kinderen",
     "Berekend: a_hh_m_k / a_hh × 100."),
    ("p_neu_al", "a_neu_al", "a_inw", "Aandeel herkomst buiten Europa", "% buiten Europa",
     "Berekend: a_neu_al / a_inw × 100 (vanaf 2023)."),
    ("p_verwed", "a_verwed", "a_inw", "Aandeel verweduwde inwoners", "% verweduwd",
     "Berekend: a_verwed / a_inw × 100. Verweduwing concentreert bij ouderen en voorspelt eenzaamheid."),
    ("p_gesch", "a_gesch", "a_inw", "Aandeel gescheiden inwoners", "% gescheiden",
     "Berekend: a_gesch / a_inw × 100. Scheiding (vaak midlife) is een eenzaamheidsrisico."),
]

THEMES = [
    ("basis_demografie", "Basisdemografie", "Buurtwerk, Huizen van de Wijk en participatie",
     "Draagvlak en wijkprofiel: hoeveel mensen en huishoudens, hoe dicht bebouwd, groeit of vergrijst de buurt.",
     ["a_inw", "a_hh", "g_hhgro", "bev_dich", "p_geb", "p_ste"],
     ["a_inw", "a_hh", "g_hhgro", "bev_dich"]),
    ("jeugd_jongeren", "Jeugd & jongeren", "Jeugd- en jongerenwerk en kinderwerk",
     "Waar wonen kinderen en jongeren, waar zijn gezinnen geconcentreerd en waar is jeugdproblematiek zichtbaar.",
     ["a_00_14", "p_00_14", "a_15_24", "p_15_24", "a_hh_m_k", "p_hh_m_k", "p_jz_tn"],
     ["a_00_14", "a_15_24", "p_00_14", "p_jz_tn"]),
    ("ouderen_vergrijzing", "Ouderen & vergrijzing", "Ouderenwerk en activiteiten voor senioren",
     "Huidige én aankomende vergrijzing per wijk, plus signalen van kwetsbaarheid (verweduwing, sterfte).",
     ["a_65_oo", "p_65_oo", "a_45_64", "a_soz_ow", "a_verwed", "p_ste", "g_afs_hp"],
     ["a_65_oo", "p_65_oo", "a_45_64", "a_verwed"]),
    ("bestaanszekerheid", "Bestaanszekerheid & schuldhulp",
     "Maatschappelijke dienstverlening: schuldhulp, financieel advies, sociaal raadslieden",
     "Waar wonen mensen met laag inkomen, uitkeringen of armoede — de kern-doelgroep van financiële hulpverlening.",
     ["a_soz_wb", "p_hh_li", "p_ink_ar", "p_ink_ba", "g_ink_pi", "m_hh_ver", "p_arb_pp", "a_soz_ww", "a_soz_ao"],
     ["a_soz_wb", "p_hh_li", "p_ink_ar", "g_ink_pi"]),
    ("eenzaamheid", "Eenzaamheid & huishoudens",
     "Buurtwerk en ouderenwerk gericht op ontmoeting en eenzaamheidsbestrijding",
     "Alleenwonen, verweduwing en scheiding als demografische risicofactoren voor eenzaamheid.",
     ["a_1p_hh", "p_1p_hh", "a_verwed", "p_verwed", "a_gesch", "p_gesch", "a_hh_z_k", "g_hhgro", "a_65_oo"],
     ["a_1p_hh", "p_1p_hh", "p_verwed", "p_gesch"]),
    ("diversiteit", "Diversiteit & herkomst",
     "Taal- en inburgeringsondersteuning, cultuursensitief buurtwerk, sociaal raadslieden",
     "Herkomstsamenstelling en opleidingsniveau als indicatie voor taal-, wegwijs- en formulierenhulp (indeling vanaf 2023).",
     ["a_neu_al", "p_neu_al", "a_eur_al", "a_gbl_ne", "a_nl_all", "a_opl_bvm"],
     ["a_neu_al", "p_neu_al", "a_gbl_ne", "a_opl_bvm"]),
    ("zorg_mantelzorg", "Zorg & mantelzorg",
     "Mantelzorgondersteuning en aansluiting welzijn–zorg (o.a. welzijn op recept)",
     "Waar zorggebruik zich concentreert, wonen ook de mantelzorgers die ondersteuning nodig hebben.",
     ["a_wmo_t", "p_wmo_t", "a_soz_ao", "p_jz_tn", "g_afs_hp", "a_65_oo"],
     ["a_wmo_t", "p_wmo_t", "a_soz_ao", "a_65_oo"]),
    ("wonen", "Wonen & woningmarkt",
     "Buurtwerk en signalering rond wonen, verdringing en betaalbaarheid",
     "Woningwaarde, eigendom en de sociale huursector — de bouwstenen achter de gentrificatie-analyse.",
     ["g_wozbag", "p_koopw", "p_wcorpw", "g_ink_pi", "p_hh_li"],
     ["g_wozbag", "p_wcorpw", "p_koopw", "p_hh_li"]),
]

# ---------------------------------------------------------- gentrificatie-index
# Vier CBS-signalen van gentrificatie, elk over een instelbare periode gemeten en
# gestandaardiseerd t.o.v. de overige gebieden op hetzelfde niveau. `sign` = +1 als
# een STIJGING op gentrificatie wijst, -1 als een DALING erop wijst. `mode` bepaalt
# hoe de verandering wordt gemeten: pct (relatief) of pp (procentpunt-verschil).
# Onderbouwing: klassieke gentrificatiemaat = stijgende woningwaarde + stijgend
# inkomen + krimpende sociale huur + krimpend aandeel lage inkomens (verdringing).
GENTRIFICATION = {
    "components": [
        {"id": "g_wozbag", "label": "Woningwaarde (WOZ)", "mode": "pct", "sign": 1,
         "why": "Stijgende WOZ-waarde is de sterkste marktindicator van gentrificatie."},
        {"id": "g_ink_pi", "label": "Inkomen per inwoner", "mode": "pct", "sign": 1,
         "why": "Stijgend gemiddeld inkomen duidt op instroom van kapitaalkrachtiger bewoners."},
        {"id": "p_wcorpw", "label": "Corporatiewoningen", "mode": "pp", "sign": -1,
         "why": "Krimp van de sociale huursector verkleint de betaalbare voorraad (verdringing)."},
        {"id": "p_hh_li", "label": "Aandeel lage inkomens", "mode": "pp", "sign": -1,
         "why": "Dalend aandeel lage-inkomenshuishoudens wijst op verdringing van de doelgroep."},
    ],
    "note": ("Index = gemiddelde van de beschikbare gestandaardiseerde componenten (z-scores) "
             "over de gekozen periode; positief = gebied gentrificeert sneller dan de andere "
             "gebieden op dit niveau. Signalerend, geen bewijs van individuele verdringing."),
}

# ---------------------------------------------------------- RIVM-uitkomsten
# Gezondheids-/welzijnsuitkomsten uit RIVM 50150NED (kleine-gebiedsschattingen,
# percentages) als aparte laag. Selectie + definities in data-prep/rivm_outcome_spec.json
# (opgesteld door het gezondheidsdomein-specialistteam). Zie docs/AANNAMES.md §9.
RIVM_SPEC_FILE = ROOT / "data-prep" / "rivm_outcome_spec.json"
RIVM_CSV = ROOT / "external-data" / "raw" / "rivm_gezondheid_wijk_buurt_50150NED" / "data.csv"
OUTCOME_THEME = (
    "gezondheid_welzijn", "Gezondheid & welzijn (uitkomsten)",
    "Signalering voor alle Dynamo-diensten; verklarende uitkomstmaten",
    "Gemodelleerde RIVM-uitkomsten (2016–2024) voor ervaren gezondheid, mentaal welzijn, "
    "eenzaamheid, mantelzorg, bestaanszekerheid en leefstijl. Kern van de samenhang-analyse.",
    # indicatorIds + headline worden gevuld uit de spec (zie load_rivm)
)

EURO_X1000 = {"g_ink_pi", "m_hh_ver", "g_wozbag"}
WEIGHT_BY_HH = {"p_hh_li", "m_hh_ver"}
# woningmarkt-indicatoren wegen we naar de woningvoorraad i.p.v. inwoners
WEIGHT_BY_WON = {"p_koopw", "p_wcorpw", "g_wozbag"}
# buurtniveau: alleen demografie is voldoende gevuld (advies data-analist)
BUURT_INDICATOREN = {
    "a_inw", "a_hh", "g_hhgro", "bev_dich", "a_00_14", "a_15_24", "a_45_64",
    "a_65_oo", "a_hh_m_k", "a_1p_hh", "a_hh_z_k", "a_verwed", "a_gesch",
    "a_nl_all", "a_eur_al", "a_neu_al", "a_gbl_ne",
    "p_00_14", "p_15_24", "p_65_oo", "p_1p_hh", "p_hh_m_k", "p_neu_al",
    "p_verwed", "p_gesch",
    # woningmarkt is registerdata en op buurtniveau redelijk gevuld (~78%);
    # nodig voor de gentrificatie-analyse op buurtniveau. Inkomen (g_ink_pi) is
    # op buurtniveau sterk onderdrukt maar wordt meegenomen waar aanwezig — de
    # ≥60%-drempel in de views verbergt het waar te schaars.
    "g_wozbag", "p_koopw", "p_wcorpw", "g_ink_pi", "p_hh_li",
}

ALL_COLS = {c for c, *_ in BASE_INDICATORS} | {d for _, _, d, *_ in DERIVED} | {"a_inw", "a_hh", "a_woning"}


def parse_cell(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    if s in ("", ".", ",", "x", "-"):
        return None
    try:
        return float(s.replace(",", "."))
    except ValueError:
        return None


def norm_name(s: str) -> str:
    # strip een leidend 'wijk NN ' / 'buurt NN '-voorvoegsel (CBS wisselt dit per
    # jaargang) zodat naamvergelijking over jaren robuust is
    t = re.sub(r"^\s*(wijk|buurt)\s*\d*\s*", "", str(s).lower())
    return re.sub(r"[^a-z0-9]", "", t)


def load_year(year: int) -> pd.DataFrame:
    df = pd.read_excel(FILES[year], dtype=str)
    df.columns = [c.strip() for c in df.columns]
    df = df.rename(columns=RENAMES.get(year, {}))
    df["gwb_code_10"] = df["gwb_code_10"].astype(str).str.strip()
    return df


def load_gebieden():
    f = ROOT / "data-prep" / "gebieden_amsterdam.json"
    if not f.exists():
        print("  !! gebieden_amsterdam.json ontbreekt — Amsterdam zonder gebieden/stadsdelen")
        return None
    return json.loads(f.read_text(encoding="utf-8"))


def load_rivm():
    """RIVM 50150NED-uitkomsten -> {code: {oid: {jaar: waarde}}} + indicatormetadata.
       Alleen meetjaren die op de tool-jaaras vallen (2016-2024; 2012 vervalt)."""
    if not RIVM_SPEC_FILE.exists() or not RIVM_CSV.exists():
        print("  !! RIVM-spec of -data ontbreekt — gezondheidsuitkomsten overgeslagen")
        return {"indicators": [], "values": {}, "ids": [], "spec": None}
    spec = json.loads(RIVM_SPEC_FILE.read_text(encoding="utf-8"))
    period_map = {k: int(v) for k, v in spec["periodMap"].items()}
    code_col, period_col = spec["codeColumn"], spec["periodColumn"]
    inds = spec["outcomeIndicators"]
    years_set = set(YEARS)
    want = {code_col, period_col} | {i["rivmColumn"] for i in inds}
    df = pd.read_csv(RIVM_CSV, dtype=str, usecols=lambda c: c in want)
    df[code_col] = df[code_col].astype(str).str.strip()
    values = {}
    for _, row in df.iterrows():
        yr = period_map.get(str(row[period_col]).strip())
        if yr not in years_set:
            continue
        code = row[code_col]
        for i in inds:
            v = parse_cell(row.get(i["rivmColumn"]))
            if v is not None:
                values.setdefault(code, {}).setdefault(i["id"], {})[yr] = v
    # mantelzorg-aandeel is niet eenduidig 'meer/minder behoefte' (hoge waarde =
    # veel informele zorg én mogelijk overbelasting) -> neutraal (INH-4)
    NEUTRAL = {"o_mantelzorger"}
    meta = [{
        "id": i["id"], "label": i["label"], "shortLabel": i["shortLabel"],
        "unit": i["unit"], "theme": OUTCOME_THEME[0], "description": i["why"],
        "direction": "neutraal" if i["id"] in NEUTRAL else ("hoog" if i["higherIsWorse"] else "laag"),
        "isOutcome": True, "estimateType": "gemodelleerd", "domain": i["domain"],
    } for i in inds]
    return {"indicators": meta, "values": values, "ids": [i["id"] for i in inds], "spec": spec}


def build_gemeente(gm_code, gm_name, frames, gebieden_cfg, rivm):
    digits = gm_code[2:]
    n_years = len(YEARS)
    is_ams = gm_code == "GM0363"

    # -------- regiolijst uit nieuwste jaargang met deze gemeente
    newest = frames[YEARS[-1]]
    rows_new = newest[newest["gwb_code_10"].str.contains(f"(?:WK|BU){digits}", regex=True, na=False)
                      | (newest["gwb_code_10"] == gm_code)]
    wijk_rows = rows_new[rows_new["recs"] == "Wijk"]
    buurt_rows = rows_new[rows_new["recs"] == "Buurt"]

    sd_letter = {}
    gb_of_wijk = {}
    stadsdelen = []
    gebieden = []
    if is_ams and gebieden_cfg:
        raw_sd = gebieden_cfg["stadsdelen"]
        sd_names = raw_sd if isinstance(raw_sd, dict) else {s["letter"]: s["naam"] for s in raw_sd}
        for _, r in wijk_rows.iterrows():
            sd_letter[r["gwb_code_10"]] = r["gwb_code_10"][6]
        for g in gebieden_cfg["gebieden"]:
            for wk in g["wijkcodes"]:
                gb_of_wijk[wk] = f"GB-{g['code']}"
        letters = sorted({v for v in sd_letter.values()})
        wijken_per_sd = {}
        for wk, l in sd_letter.items():
            wijken_per_sd[l] = wijken_per_sd.get(l, 0) + 1
        # Weesp is formeel een stadsgebied, geen stadsdeel (review #10)
        stadsdelen = [{"code": f"SD-{l}",
                       "name": ("Stadsgebied " if l == "S" else "Stadsdeel ") + sd_names.get(l, l),
                       "level": "stadsdeel", "members": wijken_per_sd.get(l, 0)}
                      for l in letters]
        gebieden = [{"code": f"GB-{g['code']}", "name": g["naam"], "level": "gebied",
                     "sd": f"SD-{g['stadsdeelLetter']}", "members": len(g["wijkcodes"])}
                    for g in gebieden_cfg["gebieden"]]

    regions = (
        [{"code": gm_code, "name": gm_name, "level": "gemeente"},
         {"code": NL, "name": "Nederland", "level": "land"}]
        + stadsdelen + gebieden
        + [{"code": r["gwb_code_10"], "name": r["regio"].strip(), "level": "wijk",
            **({"sd": f"SD-{sd_letter[r['gwb_code_10']]}"} if r["gwb_code_10"] in sd_letter else {}),
            **({"gb": gb_of_wijk[r["gwb_code_10"]]} if r["gwb_code_10"] in gb_of_wijk else {})}
           for _, r in wijk_rows.iterrows()]
        + [{"code": r["gwb_code_10"], "name": r["regio"].strip(), "level": "buurt",
            "wk": "WK" + r["gwb_code_10"][2:8],
            **({"sd": f"SD-{r['gwb_code_10'][6]}"} if is_ams and gebieden_cfg else {}),
            **({"gb": gb_of_wijk.get("WK" + r["gwb_code_10"][2:8], "")} if gb_of_wijk else {})}
           for _, r in buurt_rows.iterrows()]
    )
    for r in regions:
        if r.get("gb") == "":
            del r["gb"]

    wijk_codes = [r["code"] for r in regions if r["level"] == "wijk"]
    buurt_codes = [r["code"] for r in regions if r["level"] == "buurt"]
    values = {r["code"]: {} for r in regions}

    def setval(rc, ind, yi, v):
        values[rc].setdefault(ind, [None] * n_years)[yi] = v

    # -------- waarden per jaar (code-match, dan naam-match)
    for yi, year in enumerate(YEARS):
        df = frames[year]
        sub = df[df["gwb_code_10"].str.contains(f"(?:WK|BU){digits}", regex=True, na=False)
                 | df["gwb_code_10"].isin([gm_code, NL])]
        by_code = {r["gwb_code_10"]: r for _, r in sub.iterrows()}
        by_name_wijk = {norm_name(r["regio"]): r for _, r in sub.iterrows() if r["recs"] == "Wijk"}
        by_name_buurt = {norm_name(r["regio"]): r for _, r in sub.iterrows() if r["recs"] == "Buurt"}

        def find_row(reg):
            code = reg["code"]
            want = norm_name(reg["name"])
            if code in by_code:
                row = by_code[code]
                # codematch alleen vertrouwen als het OM HETZELFDE GEBIED gaat:
                # sommige gemeenten (Zoetermeer, Diemen) hebben na herverkaveling
                # dezelfde code voor een ander gebied hergebruikt. Bij naamverschil
                # vallen we terug op naamkoppeling (DATA-1/2).
                if norm_name(row["regio"]) == want:
                    return row
            if is_ams:  # geverifieerde Oost-mapping eerst
                for old, new in WIJK_MAP_OOST.items():
                    if new == code and old in by_code:
                        return by_code[old]
            if reg["level"] == "wijk":
                return by_name_wijk.get(want)
            if reg["level"] == "buurt":
                return by_name_buurt.get(want)
            return None

        present = set(df.columns)
        for reg in regions:
            if reg["level"] in ("stadsdeel", "gebied"):
                continue
            row = find_row(reg)
            if row is None:
                continue
            for col in ALL_COLS:
                if col not in present:
                    continue
                v = parse_cell(row.get(col))
                if v is not None and col in EURO_X1000:
                    v *= 1000.0
                if v is not None:
                    setval(reg["code"], col, yi, v)

    # -------- afgeleide percentages (mini-buurten met een te kleine noemer
    # overgeslagen, anders schijnexacte 100%-profielen, M11)
    for did, num, den, *_ in DERIVED:
        for rc in list(values):
            for yi in range(n_years):
                nv = values[rc].get(num, [None] * n_years)[yi]
                dv = values[rc].get(den, [None] * n_years)[yi]
                if nv is not None and dv and dv >= MIN_DENOM_FOR_PCT:
                    setval(rc, did, yi, round(nv / dv * 100, 1))

    # -------- codes waarvan de RIVM-indeling (2024) een ANDER gebied betreft dan
    # de tool-indeling (2025): dan matcht RIVM op code met de verkeerde geografie
    # (Zoetermeer WK063705 = Rokkeveen in 2024, Meerzicht in 2025) -> niet mergen
    # (DATA-3). Een legitieme her-codering met stabiele naam (Leeuwarden 2023+,
    # Amsterdam) wordt hierdoor NIET geblokkeerd, want naam 2024 == naam 2025.
    RIVM_YEAR = 2024
    def names_for(year):
        df = frames.get(year)
        out = {}
        if df is None:
            return out
        for _, r in df.iterrows():
            c = r["gwb_code_10"]
            if c.startswith(("WK", "BU")) and c[2:6] == digits:
                out[c] = norm_name(r["regio"])
        return out
    n2024, n2025 = names_for(RIVM_YEAR), names_for(YEARS[-1])
    unstable_codes = {c for c, nm in n2025.items() if c in n2024 and n2024[c] != nm}

    # -------- RIVM-uitkomsten mergen (op code; alleen echte, code-stabiele gebieden)
    for reg in regions:
        if reg["level"] in ("stadsdeel", "gebied"):
            continue
        if reg["code"] in unstable_codes:
            continue  # code hergebruikt -> RIVM-2024 verwijst naar ander gebied
        rv = rivm["values"].get(reg["code"])
        if not rv:
            continue
        for oid, yearvals in rv.items():
            arr = values[reg["code"]].setdefault(oid, [None] * n_years)
            for yr, v in yearvals.items():
                arr[YEARS.index(yr)] = v

    # -------- aggregaten stadsdeel/gebied (uit wijken, >=80% gevuld)
    groups = {}
    for r in regions:
        if r["level"] != "wijk":
            continue
        for key in ("sd", "gb"):
            if key in r:
                groups.setdefault(r[key], []).append(r["code"])

    base_cols = [c for c, *_ in BASE_INDICATORS]
    # per-jaar dekkingsgraad (H1): welk deel van de wijken van dit aggregaat
    # daadwerkelijk een waarde heeft. Bij herindelingen (bijv. Amsterdam-West,
    # 2022->2023) kunnen wijken door naam-mismatches tijdelijk niet koppelen;
    # de 80%-vuldrempel verbergt dat een aggregaat in vroege jaren op minder
    # wijken steunt dan in latere jaren, wat een nepsprong in de tijdreeks geeft.
    # covFrac laat de frontend die knik detecteren en waarschuwen i.p.v. verbergen.
    coverage = {}
    for agg_code, members in groups.items():
        coverage[agg_code] = [None] * n_years
        for yi in range(n_years):
            inw = {w: values[w].get("a_inw", [None] * n_years)[yi] for w in members}
            inw = {w: v for w, v in inw.items() if v is not None}
            if members:
                coverage[agg_code][yi] = round(len(inw) / len(members), 3)
            hh = {w: values[w].get("a_hh", [None] * n_years)[yi] for w in members}
            hh = {w: v for w, v in hh.items() if v is not None}
            won = {w: values[w].get("a_woning", [None] * n_years)[yi] for w in members}
            won = {w: v for w, v in won.items() if v is not None}
            for col in base_cols:
                if col == 'm_hh_ver':
                    continue  # medianen zijn niet optelbaar; geen schijnmediaan op aggregaatniveau
                vals = [(w, values[w].get(col, [None] * n_years)[yi]) for w in members]
                vals = [(w, v) for w, v in vals if v is not None]
                if len(vals) < max(1, math.ceil(0.8 * len(members))):
                    continue
                if col.startswith("a_"):
                    setval(agg_code, col, yi, float(sum(v for _, v in vals)))
                elif col == "g_hhgro":
                    if inw and hh:
                        setval(agg_code, col, yi, round(sum(inw.values()) / sum(hh.values()), 2))
                elif col == "bev_dich":
                    area = [(w, inw[w] / v) for w, v in vals if w in inw and v > 0]
                    if area:
                        setval(agg_code, col, yi,
                               round(sum(inw[w] for w, _ in area) / sum(a for _, a in area)))
                else:
                    wsrc = won if col in WEIGHT_BY_WON else hh if col in WEIGHT_BY_HH else inw
                    pairs = [(v, wsrc.get(w)) for w, v in vals if wsrc.get(w)]
                    if pairs:
                        tw = sum(w for _, w in pairs)
                        setval(agg_code, col, yi, round(sum(v * w for v, w in pairs) / tw, 1))
            for did, num, den, *_ in DERIVED:
                nv = values[agg_code].get(num, [None] * n_years)[yi]
                dv = values[agg_code].get(den, [None] * n_years)[yi]
                if nv is not None and dv and dv >= MIN_DENOM_FOR_PCT:
                    setval(agg_code, did, yi, round(nv / dv * 100, 1))
            # RIVM-uitkomsten: inwoner-gewogen gemiddelde over de wijken (benadering:
            # percentages van 18+, gewogen naar totale inwoners; zie AANNAMES §9)
            for oid in rivm["ids"]:
                vals = [(w, values[w].get(oid, [None] * n_years)[yi]) for w in members]
                vals = [(w, v) for w, v in vals if v is not None]
                if len(vals) < max(1, math.ceil(0.8 * len(members))):
                    continue
                pairs = [(v, inw.get(w)) for w, v in vals if inw.get(w)]
                if pairs:
                    tw = sum(w for _, w in pairs)
                    setval(agg_code, oid, yi, round(sum(v * w for v, w in pairs) / tw, 1))

    # -------- indicator-metadata: jaren met >=50% van de wijken gevuld. Was 80%,
    # maar bij Amsterdam zakt kern-demografie (a_hh, a_65_oo, ...) door de
    # West-herindeling (naamkoppeling faalt voor enkele tientallen wijken vóór
    # 2023, zie H1) net onder die drempel (86/110 = 78%) - het hele jaar werd dan
    # tool-breed als "niet beschikbaar" gemeld terwijl de reeks vrijwel compleet
    # is (L9). 50% matcht de drempel die availableYears() al scope-aware gebruikt.
    def years_available(ind):
        out = []
        for yi, year in enumerate(YEARS):
            filled = sum(1 for w in wijk_codes
                         if values[w].get(ind, [None] * n_years)[yi] is not None)
            if wijk_codes and filled >= max(1, math.ceil(0.5 * len(wijk_codes))):
                out.append(year)
        return out

    theme_of = {}
    for tid, _, _, _, inds, _ in THEMES:
        for i in inds:
            theme_of.setdefault(i, tid)

    indicators = []
    for col, label, short, unit, direction, desc in BASE_INDICATORS:
        yrs = years_available(col)
        if yrs:
            indicators.append({"id": col, "label": label, "shortLabel": short, "unit": unit,
                               "theme": theme_of.get(col, "basis_demografie"), "description": desc,
                               "direction": direction, "years": yrs})
    for did, num, den, label, short, desc in DERIVED:
        yrs = years_available(did)
        if yrs:
            indicators.append({"id": did, "label": label, "shortLabel": short, "unit": "pct",
                               "theme": theme_of.get(did, "basis_demografie"), "description": desc,
                               "direction": "hoog", "years": yrs,
                               "derived": f"{num}/{den}×100"})

    # -------- RIVM-uitkomstindicatoren toevoegen (jaren met >=50% wijken gevuld;
    # sommige gemeenten hertekenden wijken tussen RIVM-indeling 2024 en KWB 2025,
    # waardoor niet alle codes matchen — partiële dekking blijft bruikbaar, de
    # minimum-N in de samenhang-analyse bewaakt de betrouwbaarheid)
    def years_available_soft(ind):
        out = []
        for yi, year in enumerate(YEARS):
            filled = sum(1 for w in wijk_codes
                         if values[w].get(ind, [None] * n_years)[yi] is not None)
            if wijk_codes and filled >= max(1, math.ceil(0.5 * len(wijk_codes))):
                out.append(year)
        return out

    outcome_ids_present = []
    for m in rivm["indicators"]:
        yrs = years_available_soft(m["id"])
        if not yrs:
            continue
        indicators.append({**m, "years": yrs})
        outcome_ids_present.append(m["id"])

    known = {i["id"] for i in indicators}
    # geen thema's met 0 indicatoren emitteren (CRASH-1); headline valt terug op
    # de eerste beschikbare indicator als de voorkeurs-headline ontbreekt
    themes = []
    for tid, title, svc, desc, inds, head in THEMES:
        ids = [i for i in inds if i in known]
        if not ids:
            continue
        hd = [i for i in head if i in known] or ids[:1]
        themes.append({"id": tid, "title": title, "dynamoService": svc, "description": desc,
                       "indicatorIds": ids, "headline": hd})
    # uitkomstthema toevoegen (indicatorvolgorde = spec-volgorde, gegroepeerd per domein)
    if outcome_ids_present:
        tid, title, svc, desc = OUTCOME_THEME
        head = [i for i in ("o_ervaren_gezondheid", "o_eenzaam", "o_moeite_rondkomen",
                            "o_hoog_risico_angst_depressie") if i in known] or outcome_ids_present[:1]
        themes.append({"id": tid, "title": title, "dynamoService": svc, "description": desc,
                       "indicatorIds": outcome_ids_present, "headline": head})

    # dekkingsgraad per jaar aan het aggregaat-regio-object hangen (H1)
    for reg in regions:
        if reg["code"] in coverage:
            reg["covFrac"] = coverage[reg["code"]]

    # -------- buurtwaarden beperken tot demografie + uitkomsten (RIVM is wijk/buurt-native)
    buurt_keep = BUURT_INDICATOREN | set(outcome_ids_present)
    for b in buurt_codes:
        values[b] = {k: v for k, v in values[b].items() if k in buurt_keep}

    src = f"CBS Kerncijfers Wijken en Buurten {YEARS[0]}–{YEARS[-1]}"
    if outcome_ids_present:
        src += " · RIVM Gezondheid per wijk en buurt (50150NED, gemodelleerd 2016–2024)"
    bundle = {
        "meta": {
            "title": f"Monitor {gm_name}",
            "source": src,
            "generated": date.today().isoformat(),
            "yearsCovered": YEARS,
            "gemeente": gm_code,
        },
        "years": YEARS,
        "regions": regions,
        "themes": themes,
        "indicators": indicators,
        "values": values,
        "gentrification": GENTRIFICATION,
        "outcomeIds": outcome_ids_present,
        "correlation": {
            "rivmMeetjaren": [y for y in (2016, 2020, 2022, 2024) if y in YEARS],
            "note": "Uitkomsten zijn gemodelleerde RIVM-schattingen; samenhang is ecologisch "
                    "(over gebieden), geen individueel of causaal verband.",
        },
    }
    if is_ams:
        # officiële puntprognoses (O&S/BBGA), alleen stadsdeel Oost + wijken —
        # zie data-prep/official_forecast.py en AANNAMES.md §11
        official = load_official_forecast()
        if official:
            bundle["officialForecast"] = official
    out_file = OUT / "gm" / f"{gm_code}.json"
    out_file.write_text(json.dumps(bundle, ensure_ascii=False), encoding="utf-8")
    print(f"OK {gm_code} ({gm_name}): {out_file.stat().st_size/1024:.0f} kB — "
          f"{len(wijk_codes)} wijken, {len(buurt_codes)} buurten, "
          f"{len(stadsdelen)} stadsdelen, {len(gebieden)} gebieden, "
          f"{len(outcome_ids_present)} uitkomsten")
    return bundle


def copy_geo():
    if not GEO_SRC.exists():
        print("  !! geen geo-bestanden in data-prep/geo/gm — kaarten blijven leeg")
        return
    for f in GEO_SRC.glob("*.geojson"):
        g = json.loads(f.read_text(encoding="utf-8"))
        for ft in g["features"]:
            p = ft["properties"]
            code = p.get("statcode") or p.get("code")
            name = p.get("statnaam") or p.get("naam") or p.get("name") or ""
            # gebieden krijgen GB-prefix zodat codes matchen met de aggregaten
            if "_gebieden" in f.name and not str(code).startswith("GB-"):
                code = f"GB-{code}"
            ft["properties"] = {"code": code, "name": re.sub(r"\s+", " ", str(name)).strip()}
        (OUT / "gm" / f.name).write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
        print(f"OK geo {f.name}: {len(g['features'])} features")


def main():
    gebieden_cfg = load_gebieden()
    print("RIVM-uitkomsten laden…")
    rivm = load_rivm()
    print(f"  RIVM: {len(rivm['ids'])} uitkomstindicatoren, {len(rivm['values'])} gebieden met data")
    print("KWB-bestanden laden…")
    frames = {y: load_year(y) for y in YEARS}

    index = {"default": DEFAULT_GM, "gemeenten": []}
    for gm_code, gm_name in GEMEENTEN.items():
        b = build_gemeente(gm_code, gm_name, frames, gebieden_cfg, rivm)
        levels = sorted({r["level"] for r in b["regions"]
                         if r["level"] in ("stadsdeel", "gebied", "wijk", "buurt")})
        index["gemeenten"].append({"code": gm_code, "naam": gm_name, "levels": levels})
    (OUT / "index.json").write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
    print("OK index.json")

    copy_geo()

    # sanity: Oost via stadsdeel-aggregaat
    ams = json.loads((OUT / "gm" / "GM0363.json").read_text(encoding="utf-8"))
    yi24 = ams["years"].index(2024)
    oost = ams["values"].get("SD-M", {}).get("a_inw", [])
    if oost and oost[yi24]:
        print(f"check: inwoners stadsdeel Oost 2024 = {oost[yi24]:,.0f} (was 147.660)")
    else:
        print("check: !! SD-M aggregaat ontbreekt (gebieden_amsterdam.json aanwezig?)")


if __name__ == "__main__":
    main()
