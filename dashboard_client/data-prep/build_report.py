# -*- coding: utf-8 -*-
"""Bouwt data-prep/schema_report.json voor het Dynamo-dashboard."""
import pandas as pd, os, json

BASE = r"C:\Development\CBS gwk - 2"
FILES = {2021: "kwb-2021.xlsx", 2022: "kwb-2022.xlsx", 2023: "kwb2023.xlsx",
         2024: "kwb2024.xlsx", 2025: "kwb2025.xlsx"}
dfs = {y: pd.read_excel(os.path.join(BASE, f), dtype=str) for y, f in FILES.items()}

def is_missing(s):
    return s.isna() | s.astype(str).str.strip().isin(['.', '', ','])

# kolommen die in 2025 volledig missing zijn
df25 = dfs[2025]
id_cols = ['gwb_code_10','gwb_code_8','regio','gm_naam','recs','gwb_code','ind_wbi']
all_missing_2025 = [c for c in df25.columns if c not in id_cols and is_missing(df25[c]).all()]
print('2025 volledig leeg (%d):' % len(all_missing_2025), all_missing_2025)

# 2024 idem
df24 = dfs[2024]
all_missing_2024 = [c for c in df24.columns if c not in id_cols and is_missing(df24[c]).all()]
print('2024 volledig leeg:', all_missing_2024)

cols = {y: list(df.columns) for y, df in dfs.items()}
sets = {y: set(c) for y, c in cols.items()}
common = [c for c in cols[2021] if all(c in sets[y] for y in FILES)]

# wijkmapping + a_inw vergelijking
old2new = {
    'WK036327': ('WK0363MB', 'Weesperzijde'),
    'WK036328': ('WK0363MC', 'Oosterparkbuurt'),
    'WK036329': ('WK0363ME', 'Dapperbuurt'),
    'WK036330': ('WK0363MD', 'Transvaalbuurt'),
    'WK036331': ('WK0363MF', 'Indische Buurt-West'),
    'WK036332': ('WK0363MG', 'Indische Buurt-Oost'),
    'WK036333': ('WK0363MA', 'Oostelijk Havengebied'),
    'WK036334': ('WK0363MH', 'Zeeburgereiland/Bovendiep'),
    'WK036335': ('WK0363MJ', 'IJburg-West'),
    'WK036350': ('WK0363MK', 'IJburg-Oost'),
    'WK036351': ('WK0363ML', 'IJburg-Zuid'),
    'WK036355': ('WK0363MM', 'Frankendael'),
    'WK036356': ('WK0363MN', 'Middenmeer'),
    'WK036357': ('WK0363MP', 'Betondorp'),
    'WK036358': ('WK0363MQ', 'Omval/Overamstel'),
}
def inw(y, code):
    df = dfs[y]
    r = df[df['gwb_code_10'] == code]
    return int(str(r.iloc[0]['a_inw']).strip()) if len(r) else None

mapping_check = []
for old, (new, naam) in old2new.items():
    i22, i23 = inw(2022, old), inw(2023, new)
    dev = round(100 * (i23 - i22) / i22, 1) if i22 else None
    mapping_check.append({'code_2021_2022': old, 'code_2023_plus': new, 'naam_2023': naam,
                          'a_inw_2022': i22, 'a_inw_2023': i23, 'delta_pct': dev,
                          'afwijking_gt_10pct': (dev is None) or abs(dev) > 10})
for m in mapping_check:
    print(m['code_2021_2022'], '->', m['code_2023_plus'], m['naam_2023'], m['delta_pct'], '%')

# buurten Oost missingness per jaar (kernindicatoren)
keys = ['a_inw','a_00_14','a_65_oo','a_hh','g_hh_sti','p_hh_li','a_soz_wb','a_soz_ao',
        'p_jz_tn','p_wmo_t','g_ink_pi','g_wozbag','p_huurw','p_wcorpw']
buurt_missing = {}
for y in (2023, 2024, 2025):
    b = dfs[y][(dfs[y]['recs'].str.strip() == 'Buurt') & (dfs[y]['gwb_code_10'].str.match(r'^BU0363M'))]
    buurt_missing[y] = {'n_buurten': len(b),
                        'missing_per_indicator': {c: int(is_missing(b[c]).sum()) for c in keys if c in b.columns}}

b23 = dfs[2023][(dfs[2023]['recs'].str.strip() == 'Buurt') & (dfs[2023]['gwb_code_10'].str.match(r'^BU0363M'))]
buurten_lijst = [{'code': r['gwb_code_10'], 'naam': str(r['regio']).strip(),
                  'wijk': 'WK' + r['gwb_code_10'][2:8]} for _, r in b23.iterrows()]

report = {
  'meta': {
    'beschrijving': 'Schema-analyse CBS Kerncijfers Wijken en Buurten (kwb) 2021-2025 t.b.v. demografisch dashboard Dynamo, stadsdeel Amsterdam Oost',
    'bronbestanden': {str(y): f for y, f in FILES.items()},
    'gegenereerd': '2026-07-10',
    'rijen_per_jaar': {str(y): int(len(df)) for y, df in dfs.items()},
    'recs_waarden': {str(y): dfs[y]['recs'].str.strip().value_counts().to_dict() for y in FILES},
  },
  'kolommen': {
    'per_jaar': {str(y): cols[y] for y in FILES},
    'aantal_per_jaar': {str(y): len(cols[y]) for y in FILES},
    'gemeenschappelijk_alle_5_jaren': common,
    'aantal_gemeenschappelijk': len(common),
    'trailing_space_kolomnamen_2024': ['a_nb_won ', 'p_won_m ', 'p_won_ev '],
  },
  'hernoemingen_en_wijzigingen': {
    'zekere_hernoemingen': {
      'opleidingsniveau_15_74jr': {
        'mapping': {'a_opl_lg': 'a_opl_bvm', 'a_opl_md': 'a_opl_hvm', 'a_opl_hg': 'a_opl_hw'},
        'toelichting': '2021/2022 en 2025 gebruiken a_opl_lg/md/hg; 2023/2024 gebruiken a_opl_bvm/hvm/hw. Zelfde begrip (opleidingsniveau laag/middelbaar/hoog), geverifieerd via NL-totalen (3,55/5,56/4,39 mln sluiten aan). LET OP: in 2025 zijn deze kolommen aanwezig maar volledig leeg (.).',
      },
      'kolomnamen_met_spatie_2024': {
        'mapping': {'a_nb_won ': 'a_nb_won', 'p_won_m ': 'p_won_m', 'p_won_ev ': 'p_won_ev'},
        'toelichting': "2024 heeft trailing spaces in drie kolomnamen; 2025 zonder spatie. Altijd kolomnamen strippen bij inlezen.",
      },
    },
    'concept_wijzigingen_geen_1_op_1_mapping': {
      'herkomst': {
        'vervallen_na_2022': ['a_w_all', 'a_nw_all', 'a_marok', 'a_antaru', 'a_suri', 'a_tur', 'a_ov_nw'],
        'nieuw_vanaf_2023': ['a_geb_nl', 'a_geb_eu', 'a_geb_ne', 'a_gbl_ne', 'a_gbl_eu', 'a_nl_all', 'a_eur_al', 'a_neu_al'],
        'toelichting': 'CBS is per 2023 overgestapt van westers/niet-westers-migratieachtergrond naar de nieuwe herkomstindeling (geboren in NL / Europa / buiten Europa). Niet 1-op-1 vergelijkbaar over de breuk 2022->2023.',
      },
      'armoede_inkomen_huishoudens': {
        'vervallen_na_2023': ['p_hh_110', 'p_hh_120', 'p_hh_lkk', 'p_hh_osm'],
        'nieuw_vanaf_2024': ['p_ink_ar', 'p_ink_ba'],
        'toelichting': 'p_hh_110/120 (onder 110%/120% sociaal minimum, NL ~9,5/12) t/m 2023; vanaf 2024 p_ink_ar/p_ink_ba (NL 3,1/6,4) - andere (armoedegrens-)definitie, waarden NIET vergelijkbaar. In 2025 nog leeg.',
      },
      'bouwjaar_woningen': {
        'vervallen_na_2023': ['p_bjj2k', 'p_bjo2k'],
        'nieuw_vanaf_2024': ['p_bj_mi10', 'p_bj_me10'],
        'toelichting': 'T/m 2023 percentage bouwjaar voor/vanaf 2000 (NL 82/18); vanaf 2024 minder/meer dan 10 jaar oud (NL 8/92). Andere definitie, niet vergelijkbaar.',
      },
      'energie_per_woningtype': {
        'vervallen_na_2023': ['g_ele_ap','g_ele_hw','g_ele_tw','g_ele_2w','g_ele_vw','g_ele_hu','g_ele_ko',
                              'g_gas_ap','g_gas_hw','g_gas_tw','g_gas_2w','g_gas_vw','g_gas_hu','g_gas_ko'],
        'nieuw_vanaf_2024': ['g_ele_tr'],
        'toelichting': 'Uitsplitsing gas/elektra naar woningtype/eigendom vervalt na 2023. g_ele en g_gas (totaalgemiddelden) blijven in alle jaren. g_ele_tr (2024+) is een nieuwe kolom (vermoedelijk teruglevering, NL 790 kWh) - geen hernoeming. Energiekolommen zijn in 2025 volledig leeg.',
      },
      'onderwijs_deelnemers': {
        'alleen_2023_2024': ['a_ons_po','a_ons_vovavo','a_ons_mbo','a_ons_hbo','a_ons_wo'],
        'toelichting': 'Aantallen onderwijsvolgenden alleen in 2023 en 2024.',
      },
      'woningvoorraad_nieuw_2024_plus': ['a_vastg','a_nb_vastg','a_nb_won','p_won_ev','p_won_m','p_won_z','p_won_zs',
                                          'p_1gezw_tw','p_1gezw_hw','p_1gezw_2w','p_1gezw_vw (2025) / p_1gezw_hvw (2024)'],
      'overig': {
        'a_antaru': 'alleen 2021/2022 (herkomst Antillen/Aruba, zie herkomst)',
        'a_arb_wz / p_arb_wf / p_arb_wv': 'nieuw vanaf 2023 (arbeid werkzaam/werkloos)',
        'a_lp_pub': 'nieuw vanaf 2024 (laadpunten publiek)',
      },
      'uitkeringen_ongewijzigd': 'a_soz_wb, a_soz_ao, a_soz_ww, a_soz_ow bestaan onveranderd in alle 5 jaargangen (wel leeg in 2025).',
    },
  },
  'wijkcode_mapping_oost': {
    'toelichting': 'Mapping oude wijkcodes (indeling t/m 2022, 99 wijken Amsterdam) naar nieuwe codes (vanaf 2023, 110 wijken). Op naam gematcht; alle 15 Oost-wijken 1-op-1 terug te vinden. a_inw 2022 (kwb-2022) vs 2023 (kwb2023) als plausibiliteitscheck.',
    'mapping': mapping_check,
    'afwijkingen_gt_10pct': [m for m in mapping_check if m['afwijking_gt_10pct']],
    'naamswijzigingen': {
      'Zeeburgereiland/Nieuwe Diep': 'Zeeburgereiland/Bovendiep (WK0363MH)',
      'Indische Buurt West/Oost, IJburg West/Oost/Zuid': 'zelfde naam maar met koppelteken in 2023+ (Indische Buurt-West etc.)',
    },
  },
  'conventies': {
    'prefixen': {
      'a_': 'absoluut aantal (geverifieerd: a_inw, a_hh, a_soz_* zijn gehele aantallen)',
      'p_': 'percentage (geverifieerd: p_geb is per 1000 inwoners! p_ste idem; overige p_ zijn %, 0-100, geheel of 1 decimaal)',
      'g_': 'gemiddelde (g_hhgro, g_ink_pi, g_ele, g_wozbag=gem. WOZ-waarde x1000 euro)',
      'm_': 'mediaan (m_hh_ver = mediaan vermogen huishoudens x1000 euro)',
      'overig': 'bev_dich=bevolkingsdichtheid per km2, ste_oad=omgevingsadressendichtheid, ste_mvs=stedelijkheidsklasse 1-5, pst_mvp/pst_dekp=postcode, ind_wbi=indicator wijziging gebiedsindeling',
    },
    'let_op_p_geb_p_ste': 'p_geb en p_ste zijn geboorte/sterfte per 1000 inwoners, geen percentage.',
    'missing_codes': [
      "'.' (punt), vaak met voorloopspaties zoals '       .' - strip waarden voor parsing",
      "lege cel / NaN (vooral 2023: a_opl_*, a_jz_tn, p_jz_tn, a_wmo_t, p_wmo_t, g_afs_*, p_geb, p_ste)",
      "',' (losse komma) - alleen 2022, kolom g_gas_ap, 5507 cellen",
    ],
    'decimaal_scheiding': "INCONSISTENT: sommige kolommen gebruiken decimale komma (bijv. g_ink_pi '26,4', p_hh_110 '9,8'), andere decimale punt (g_hhgro '1.2'). Parse met vervanging ,->. na strip.",
    'afronding': [
      'a_inw op wijk/buurtniveau altijd veelvoud van 5 (0 uitzonderingen in 2021 en 2023); alle a_-aantallen op wijk/buurt zijn afgerond op 5-tallen',
      'percentages geheel getal of 1 decimaal',
      'g_wozbag in 1000 euro; g_ink_* in 1000 euro per persoon/huishouden; m_hh_ver in 1000 euro',
      'g_ele in kWh, g_gas in m3 (gehele tientallen)',
    ],
    'cellen_bevatten_soms_voorloopspaties': 'Ook numerieke waarden hebben soms voorloopspaties; altijd str.strip() toepassen.',
  },
  'volledigheid_2025': {
    'toelichting': 'kwb2025 is een voorlopige jaargang: 42 indicatorkolommen zijn volledig leeg (.) omdat de cijfers nog niet beschikbaar zijn (o.a. opleiding, energie, inkomen, uitkeringen, jeugdzorg, wmo, bedrijven, autos, nabijheid).',
    'volledig_lege_kolommen_2025': all_missing_2025,
    'volledig_lege_kolommen_2024': all_missing_2024,
  },
  'buurten_oost': {
    'toelichting': 'Buurten binnen de 15 Oost-wijken (BU0363M*). Stabiel 76 buurten in 2023, 2024 en 2025. Demografie (a_inw, leeftijd, huishoudens) is compleet. Sociaaleconomische indicatoren missen bij 16-26 van de 76 buurten (kleine buurten, onderdrukking) in 2023/2024; in 2025 vrijwel alle sociaaleconomische indicatoren leeg (nog niet gepubliceerd). Bruikbaar voor demografie op buurtniveau; voor inkomen/uitkeringen/jeugdzorg/wmo beperkt bruikbaar (ca. 65-80% dekking, kleine buurten vallen weg) - adviseer wijkniveau als primair niveau.',
    'aantal_per_jaar': {str(y): buurt_missing[y]['n_buurten'] for y in (2023, 2024, 2025)},
    'missing_per_indicator': {str(y): buurt_missing[y]['missing_per_indicator'] for y in (2023, 2024, 2025)},
    'buurten_2023': buurten_lijst,
    'buurtniveau_2021_2022': 'In 2021/2022 gelden oude buurtcodes (BU03633xx etc.) binnen de oude wijkindeling; koppeling met nieuwe buurten vereist een aparte CBS-overgangstabel en is hier niet gelegd.',
  },
}

os.makedirs(os.path.join(BASE, 'data-prep'), exist_ok=True)
out = os.path.join(BASE, 'data-prep', 'schema_report.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
print('geschreven:', out)
