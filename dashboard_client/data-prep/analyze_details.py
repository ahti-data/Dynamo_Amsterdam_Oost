# -*- coding: utf-8 -*-
import pandas as pd, os, json

BASE = r"C:\Development\CBS gwk - 2"
FILES = {2021: "kwb-2021.xlsx", 2022: "kwb-2022.xlsx", 2023: "kwb2023.xlsx",
         2024: "kwb2024.xlsx", 2025: "kwb2025.xlsx"}
dfs = {y: pd.read_excel(os.path.join(BASE, f), dtype=str) for y, f in FILES.items()}

def nl(y, col):
    df = dfs[y]
    if col not in df.columns: return None
    r = df[df['recs'].str.strip() == 'Land']
    return r.iloc[0][col]

print("== opleiding rename check (NL row) ==")
for y in FILES:
    print(y, 'lg/bvm:', nl(y,'a_opl_lg'), nl(y,'a_opl_bvm'),
          '| md/hvm:', nl(y,'a_opl_md'), nl(y,'a_opl_hvm'),
          '| hg/hw:', nl(y,'a_opl_hg'), nl(y,'a_opl_hw'))

print("== bouwjaar check ==")
for y in FILES:
    print(y, 'p_bjj2k:', nl(y,'p_bjj2k'), 'p_bjo2k:', nl(y,'p_bjo2k'),
          'p_bj_me10:', nl(y,'p_bj_me10'), 'p_bj_mi10:', nl(y,'p_bj_mi10'))

print("== energie check ==")
for y in FILES:
    print(y, 'g_ele:', nl(y,'g_ele'), 'g_ele_tw:', nl(y,'g_ele_tw'), 'g_ele_tr:', nl(y,'g_ele_tr'), 'g_gas:', nl(y,'g_gas'))

print("== woningvoorraad 2024/25 nieuwe kolommen (NL) ==")
for y in (2024, 2025):
    for c in [c for c in dfs[y].columns if c.strip() in ('p_won_ev','p_won_m','p_won_z','p_won_zs','a_nb_won','a_nb_vastg','a_vastg','p_1gezw','p_1gezw_2w','p_1gezw_hw','p_1gezw_tw','p_1gezw_vw','p_1gezw_hvw')]:
        print(y, repr(c), nl(y, c))

print("== inkomen/armoede check ==")
for y in FILES:
    print(y, 'p_hh_110:', nl(y,'p_hh_110'), 'p_hh_120:', nl(y,'p_hh_120'), 'p_ink_ar:', nl(y,'p_ink_ar'), 'p_ink_ba:', nl(y,'p_ink_ba'), 'p_hh_li:', nl(y,'p_hh_li'))

print("== herkomst check (NL) ==")
for y in FILES:
    print(y, 'a_w_all:', nl(y,'a_w_all'), 'a_nw_all:', nl(y,'a_nw_all'), 'a_geb_nl:', nl(y,'a_geb_nl'), 'a_nl_all:', nl(y,'a_nl_all'), 'a_eur_al:', nl(y,'a_eur_al'), 'a_neu_al:', nl(y,'a_neu_al'))

print("== komma-token 2022 ==")
df22 = dfs[2022]
for c in df22.columns:
    s = df22[c].dropna()
    n = int((s.str.strip() == ',').sum())
    if n: print(' col', c, ':', n)

print("== NaN kolommen 2023 ==")
df23 = dfs[2023]
nn = df23.isna().sum()
print(nn[nn > 0])

print("== trailing space kolomnamen ==")
for y in FILES:
    ts = [repr(c) for c in dfs[y].columns if c != c.strip()]
    if ts: print(y, ts)

print("== afronding a_inw (veelvoud van 5?) op wijk/buurtniveau 2023 ==")
w = df23[df23['recs'].str.strip().isin(['Wijk','Buurt'])]['a_inw'].dropna().str.strip()
w = w[w.str.match(r'^\d+$')].astype(int)
print('niet-deelbaar door 5:', int((w % 5 != 0).sum()), 'van', len(w))

print("== decimalen: g_hhgro, p_geb voorbeelden 2023 (wijk) ==")
print(df23[df23['recs'].str.strip()=='Wijk'][['g_hhgro','p_geb','g_ink_pi','g_wozbag']].head(8).to_string())

print("== a_inw 2021 afronding ==")
w21 = dfs[2021][dfs[2021]['recs'].str.strip().isin(['Wijk','Buurt'])]['a_inw'].dropna().str.strip()
w21n = w21[w21.str.match(r'^\d+$')].astype(int)
print('niet-deelbaar door 5:', int((w21n % 5 != 0).sum()), 'van', len(w21n))

print("== missingness buurten Oost 2024/2025 kernindicatoren ==")
keys = ['a_inw','g_hh_sti','p_hh_li','a_soz_wb','p_jz_tn','p_wmo_t','g_wozbag','p_huurw','g_ink_pi']
for y in (2024, 2025):
    b = dfs[y][(dfs[y]['recs'].str.strip()=='Buurt') & (dfs[y]['gwb_code_10'].str.match(r'^BU0363M'))]
    row = {c: int((b[c].isna() | b[c].str.strip().isin(['.','x','-'])).sum()) for c in keys if c in b.columns}
    print(y, len(b), row)

print("== gwb_code_8 / gwb_code vorm (voorbeeld 2023 Oost wijk) ==")
r = df23[df23['gwb_code_10'] == 'WK0363MA'].iloc[0]
print({k: r[k] for k in ['gwb_code_10','gwb_code_8','gwb_code','regio','recs','ind_wbi']})
