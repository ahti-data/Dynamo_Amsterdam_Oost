# -*- coding: utf-8 -*-
"""Schema-analyse CBS Kerncijfers Wijken en Buurten 2021-2025 voor Dynamo dashboard."""
import pandas as pd
import numpy as np
import json, re, os

BASE = r"C:\Development\CBS gwk - 2"
FILES = {2021: "kwb-2021.xlsx", 2022: "kwb-2022.xlsx", 2023: "kwb2023.xlsx",
         2024: "kwb2024.xlsx", 2025: "kwb2025.xlsx"}

dfs = {}
for y, f in FILES.items():
    dfs[y] = pd.read_excel(os.path.join(BASE, f), dtype=str)
    print(y, dfs[y].shape)

cols = {y: list(df.columns) for y, df in dfs.items()}
sets = {y: set(c) for y, c in cols.items()}
common = [c for c in cols[2021] if all(c in sets[y] for y in FILES)]

# --- recs values ---
for y in FILES:
    print(y, dfs[y]['recs'].value_counts().to_dict())

# --- missing value codes: unique non-numeric strings in indicator columns ---
id_cols = {'gwb_code_10', 'gwb_code_8', 'regio', 'gm_naam', 'recs', 'gwb_code', 'ind_wbi', 'pst_mvp', 'pst_dekp'}
missing_tokens = {}
for y, df in dfs.items():
    toks = {}
    for c in df.columns:
        if c in id_cols:
            continue
        s = df[c].dropna()
        nonnum = s[~s.str.match(r'^-?\d+(?:[.,]\d+)?$')]
        for v in nonnum.unique():
            toks[v] = toks.get(v, 0) + int((nonnum == v).sum())
    missing_tokens[y] = toks
    print(y, 'non-numeric tokens:', {k: v for k, v in sorted(toks.items(), key=lambda x: -x[1])[:10]})

# NaN counts (empty cells) exist?
for y, df in dfs.items():
    n_nan = int(df.drop(columns=[c for c in id_cols if c in df.columns]).isna().sum().sum())
    print(y, 'empty cells:', n_nan)

# --- wijk mapping Oost ---
old_wijken = {
    'WK036327': 'Weesperzijde', 'WK036328': 'Oosterparkbuurt', 'WK036329': 'Dapperbuurt',
    'WK036330': 'Transvaalbuurt', 'WK036331': 'Indische Buurt West', 'WK036332': 'Indische Buurt Oost',
    'WK036333': 'Oostelijk Havengebied', 'WK036334': 'Zeeburgereiland/Nieuwe Diep',
    'WK036335': 'IJburg West', 'WK036350': 'IJburg Oost', 'WK036351': 'IJburg Zuid',
    'WK036355': 'Frankendael', 'WK036356': 'Middenmeer', 'WK036357': 'Betondorp',
    'WK036358': 'Omval/Overamstel'
}

def wijk_rows(df, pattern):
    m = df[(df['recs'].str.strip() == 'Wijk') & (df['gwb_code_10'].str.match(pattern))]
    return m

w22 = wijk_rows(dfs[2022], r'^WK0363')
w23 = wijk_rows(dfs[2023], r'^WK0363')
print('wijken A\'dam 2022:', len(w22), ' 2023:', len(w23))
oost23 = wijk_rows(dfs[2023], r'^WK0363M')
print('Oost wijken 2023:', len(oost23))
for _, r in oost23.iterrows():
    print(r['gwb_code_10'], '|', r['regio'].strip(), '|', r['a_inw'])

# old codes present in 2021/2022?
for y in (2021, 2022):
    w = dfs[y][dfs[y]['gwb_code_10'].isin(old_wijken)]
    print(y, 'old Oost codes found:', len(w))
    for _, r in w.iterrows():
        print(' ', r['gwb_code_10'], '|', r['regio'].strip(), '|', r['a_inw'])

# --- buurten Oost 2023+ ---
for y in (2023, 2024, 2025):
    b = dfs[y][(dfs[y]['recs'].str.strip() == 'Buurt') & (dfs[y]['gwb_code_10'].str.match(r'^BU0363M'))]
    print(y, 'Oost buurten:', len(b))
    if y == 2023:
        # missingness on buurt level for key indicators
        keys = ['a_inw', 'a_hh', 'g_hh_sti', 'p_hh_li', 'a_soz_wb', 'p_jz_tn', 'p_wmo_t', 'g_ink_pi',
                'a_00_14', 'a_65_oo', 'g_wozbag', 'p_huurw']
        for c in keys:
            s = b[c]
            miss = int((s.isna() | s.str.strip().isin(['.', 'x', '-'])).sum())
            print('  ', c, 'missing', miss, '/', len(b))
        buurt_list = [{'code': r['gwb_code_10'], 'naam': r['regio'].strip()} for _, r in b.iterrows()]
        json.dump(buurt_list, open(os.path.join(BASE, 'data-prep', 'oost_buurten_2023.json'), 'w'), ensure_ascii=False, indent=1)
