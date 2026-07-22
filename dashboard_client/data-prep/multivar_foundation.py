# -*- coding: utf-8 -*-
"""
Herberekent het multivariate fundament achter het tabblad *Inzichten*
(doelgroepdossiers) en schrijft data-prep/multivar_foundation.json.

Analyseniveau: Amsterdamse BUURTEN, peiljaar 2024, op de gebouwde databundel
dashboard/public/data/GM0363.json (draai eerst build_data.py).

Drie analyses (zie docs/ACHTERGROND-DATABEWERKINGEN.md §9 en AANNAMES.md §10):
  1. k-means buurttypologieën (k gekozen via silhouette) op 14 gestandaardiseerde
     socio-demografische dimensies;
  2. meervoudige lineaire regressie per RIVM-uitkomst met GESTANDAARDISEERDE
     coëfficiënten (= onafhankelijke drivers) + R²;
  3. partiële correlaties (residuenmethode) die schijnverbanden ontmaskeren.

Reproduceerbaarheid: random_state is vast (0). k-means-clusterindices zijn
inherent volgorde-onafhankelijk; de profielen en groottes zijn stabiel, de
nummering van de clusters kan per run verschillen.

    pip install numpy scikit-learn
    python data-prep/multivar_foundation.py

Ecologisch voorbehoud: alle profielen zijn buurtgemiddelden (ecologisch niveau),
geen individuen (ecological fallacy). Uitkomsten zijn RIVM-gemodelleerde
schattingen.
"""
import json
from pathlib import Path

import numpy as np
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "dashboard" / "public" / "data" / "gm" / "GM0363.json"
OUT = ROOT / "data-prep" / "multivar_foundation.json"

YEAR = 2024
RANDOM_STATE = 0
K_RANGE = range(3, 8)  # 3..7

# 14 socio-demografische dimensies (inkomen p.p./mediaan vermogen zijn op
# buurtniveau te sterk onderdrukt en vervangen door p_hh_li als inkomens-proxy)
DIMS = [
    "p_00_14", "p_15_24", "p_65_oo", "p_1p_hh", "p_hh_m_k", "g_hhgro",
    "p_neu_al", "p_hh_li", "bev_dich", "p_koopw", "p_wcorpw", "g_wozbag",
    "p_verwed", "p_gesch",
]
DIM_LABELS = {
    "p_00_14": "aandeel 0-14", "p_15_24": "aandeel 15-24", "p_65_oo": "aandeel 65+",
    "p_1p_hh": "alleenwonend", "p_hh_m_k": "gezinnen met kinderen",
    "g_hhgro": "huishoudensgrootte", "p_neu_al": "herkomst buiten Europa",
    "p_hh_li": "lage inkomens", "bev_dich": "bevolkingsdichtheid",
    "p_koopw": "koopwoningen", "p_wcorpw": "sociale huur", "g_wozbag": "WOZ-waarde",
    "p_verwed": "verweduwd (%)", "p_gesch": "gescheiden (%)",
}

# uitkomsten waarvoor een gemiddeld z-profiel per cluster wordt getoond
OUTCOME_Z = [
    "o_ervaren_gezondheid", "o_langdurige_aandoening", "o_langdurig_beperkt",
    "o_hoog_risico_angst_depressie", "o_veel_stress", "o_angst_depressie_gevoelens",
    "o_suicidegedachten", "o_eenzaam", "o_sterk_eenzaam", "o_regie_eigen_leven",
    "o_krijgt_steun", "o_mantelzorger", "o_moeite_rondkomen", "o_overgewicht",
    "o_obesitas", "o_rookt", "o_overmatig_drinken", "o_beweegrichtlijn",
    "o_wekelijks_sporten", "o_tevreden_woonomgeving",
]

# uitkomsten waarvoor een volledige regressie op de 14 dimensies wordt gedraaid.
# De onderste vijf zijn toegevoegd omdat de doelgroepdossiers (Inzichten) er een
# R²/beta van citeren; zonder deze regressies waren die citaten niet herleidbaar tot
# dit fundament (L5/M4). Volgorde bovenaan ongewijzigd zodat bestaande citaten blijven.
REGRESSION_OUTCOMES = [
    ("o_eenzaam", "Eenzaam"),
    ("o_hoog_risico_angst_depressie", "Hoog risico angst/depressie"),
    ("o_ervaren_gezondheid", "Goed ervaren gezondheid"),
    ("o_moeite_rondkomen", "Moeite met rondkomen"),
    ("o_langdurige_aandoening", "Langdurige aandoening"),
    ("o_mantelzorger", "Mantelzorger"),
    ("o_veel_stress", "Veel stress"),
    ("o_krijgt_steun", "Krijgt steun uit omgeving"),
    ("o_obesitas", "Obesitas"),
    ("o_sterk_eenzaam", "Sterk eenzaam"),
    ("o_suicidegedachten", "Suïcidegedachten"),
]

# partiële correlaties (residuenmethode): x ⟂ y na uitpartialiseren van controls.
# De eerste vijf zijn de kern; de rest is toegevoegd omdat de doelgroepdossiers
# (Inzichten) er een r_partial van citeren — zo zijn die citaten herleidbaar tot dit
# fundament (L5). controls leeg = ruwe correlatie.
PARTIALS = [
    ("eenzaam~alleenwonend|leeftijd", "o_eenzaam", "p_1p_hh", ["p_65_oo", "p_15_24"],
     "eenzaamheid vs alleenwonend na controle voor leeftijdsopbouw"),
    ("goede_gezh~herkomst|inkomen", "o_ervaren_gezondheid", "p_neu_al", ["p_hh_li"],
     "ervaren gezondheid vs herkomst na controle voor inkomen"),
    ("rondkomen~lageinkomen|herkomst+leeftijd", "o_moeite_rondkomen", "p_hh_li",
     ["p_neu_al", "p_65_oo"], "moeite rondkomen vs lage inkomens na controle herkomst+leeftijd"),
    ("angstdepr~herkomst|inkomen", "o_hoog_risico_angst_depressie", "p_neu_al", ["p_hh_li"],
     "angst/depressie vs herkomst na controle voor inkomen"),
    ("eenzaam~WOZ|alleenwonend", "o_eenzaam", "g_wozbag", ["p_1p_hh"],
     "eenzaamheid vs WOZ-waarde na controle voor alleenwonend"),
    # -- aanvullend, geciteerd in de dossiers --
    ("kinddichtheid~angstdepr|inkomen", "o_hoog_risico_angst_depressie", "p_00_14", ["p_hh_li"],
     "suppressie: kinderdichtheid vs angst/depressie na controle voor inkomen"),
    ("obesitas~kinddichtheid|inkomen+herkomst", "o_obesitas", "p_00_14", ["p_hh_li", "p_neu_al"],
     "obesitas vs kinderdichtheid na controle voor inkomen en herkomst"),
    ("aandoening~65+|inkomen+herkomst", "o_langdurige_aandoening", "p_65_oo", ["p_hh_li", "p_neu_al"],
     "langdurige aandoening vs 65+ na controle voor inkomen en herkomst"),
    ("rondkomen~inkomen|65+", "o_moeite_rondkomen", "p_hh_li", ["p_65_oo"],
     "moeite rondkomen vs lage inkomens na controle voor leeftijd"),
    ("rondkomen~socialehuur|inkomen", "o_moeite_rondkomen", "p_wcorpw", ["p_hh_li"],
     "moeite rondkomen vs sociale huur na controle voor inkomen (schijnverband)"),
    ("rondkomen~socialehuur|inkomen+herkomst", "o_moeite_rondkomen", "p_wcorpw", ["p_hh_li", "p_neu_al"],
     "moeite rondkomen vs sociale huur na controle voor inkomen en herkomst (schijnverband)"),
    ("rondkomen~alleenwonend|inkomen", "o_moeite_rondkomen", "p_1p_hh", ["p_hh_li"],
     "moeite rondkomen vs alleenwonend na controle voor inkomen (suppressie)"),
    ("eenzaam~alleenwonend|leeftijd+herkomst", "o_eenzaam", "p_1p_hh", ["p_65_oo", "p_15_24", "p_neu_al"],
     "eenzaamheid vs alleenwonend na controle voor leeftijd en herkomst"),
    ("eenzaam~65+|alleenwonend", "o_eenzaam", "p_65_oo", ["p_1p_hh"],
     "eenzaamheid vs 65+ na controle voor alleenwonend"),
    ("eenzaam~verweduwd|65+alleenwonend", "o_eenzaam", "p_verwed", ["p_65_oo", "p_1p_hh"],
     "eenzaamheid vs verweduwd na controle voor leeftijd en alleenwonend (suppressie)"),
    ("eenzaam~herkomst|inkomen+alleenwonend", "o_eenzaam", "p_neu_al", ["p_hh_li", "p_1p_hh"],
     "eenzaamheid vs herkomst na controle voor inkomen en alleenwonend"),
    ("eenzaam~15-24|inkomen+herkomst", "o_eenzaam", "p_15_24", ["p_hh_li", "p_neu_al"],
     "eenzaamheid vs 15-24 na controle voor inkomen en herkomst (leeftijd valt weg)"),
    ("eenzaam~gescheiden|leeftijd+inkomen", "o_eenzaam", "p_gesch", ["p_65_oo", "p_hh_li"],
     "eenzaamheid vs gescheiden na controle voor leeftijd en inkomen"),
    ("beperkt~steun|leeftijd", "o_langdurig_beperkt", "o_krijgt_steun", ["p_65_oo"],
     "langdurig beperkt vs ervaren steun na controle voor leeftijd"),
    ("steun~herkomst|leeftijd+inkomen", "o_krijgt_steun", "p_neu_al", ["p_65_oo", "p_hh_li"],
     "ervaren steun vs herkomst na controle voor leeftijd en inkomen"),
    ("mantelzorg~alleenwonend|leeftijd", "o_mantelzorger", "p_1p_hh", ["p_65_oo"],
     "mantelzorg-aanbod vs alleenwonend na controle voor leeftijd"),
    ("veelstress~15-24|alleenwonend+inkomen", "o_veel_stress", "p_15_24", ["p_1p_hh", "p_hh_li"],
     "veel stress vs 15-24 na controle voor alleenwonend en inkomen (zelfstandig leeftijdseffect)"),
]

# composiet-z-indices: gemiddelde z van de dimensies (optioneel teken) vs een
# uitkomst. Geciteerd in de dossiers als prioriteringsinstrument (L5).
COMPOSITES = [
    ("jeugd_armoede~angstdepr", ["p_00_14", "p_hh_li", "p_neu_al", "p_wcorpw"], None,
     "o_hoog_risico_angst_depressie", "kind+armoede+migratie+sociale huur vs angst/depressie"),
    ("jeugd_armoede~obesitas", ["p_00_14", "p_hh_li", "p_neu_al", "p_wcorpw"], None,
     "o_obesitas", "kind+armoede+migratie+sociale huur vs obesitas"),
    ("jeugd_armoede~erv_gezh", ["p_00_14", "p_hh_li", "p_neu_al", "p_wcorpw"], None,
     "o_ervaren_gezondheid", "kind+armoede+migratie+sociale huur vs goede ervaren gezondheid"),
    ("jong~suicide", ["p_15_24", "p_1p_hh", "p_hh_li"], None,
     "o_suicidegedachten", "15-24+alleenwonend+lage inkomens vs suicidegedachten"),
    ("jong~veel_stress", ["p_15_24", "p_1p_hh", "p_hh_li"], None,
     "o_veel_stress", "15-24+alleenwonend+lage inkomens vs veel stress"),
    ("jong~angstdepr", ["p_15_24", "p_1p_hh", "p_hh_li"], None,
     "o_hoog_risico_angst_depressie", "15-24+alleenwonend+lage inkomens vs angst/depressie"),
    ("gezin~rondkomen", ["p_hh_li", "p_wcorpw", "p_neu_al", "p_gesch"], None,
     "o_moeite_rondkomen", "inkomen+sociale huur+herkomst+scheiding vs moeite rondkomen"),
    ("gezin~erv_gezh", ["p_hh_li", "p_wcorpw", "p_neu_al", "p_gesch"], None,
     "o_ervaren_gezondheid", "inkomen+sociale huur+herkomst+scheiding vs goede ervaren gezondheid"),
    ("bestaan~rondkomen", ["p_hh_li", "p_wcorpw", "p_neu_al"], None,
     "o_moeite_rondkomen", "inkomen+sociale huur+herkomst vs moeite rondkomen"),
    ("bestaan~angstdepr", ["p_hh_li", "p_wcorpw", "p_neu_al"], None,
     "o_hoog_risico_angst_depressie", "inkomen+sociale huur+herkomst vs angst/depressie"),
    ("bestaan~erv_gezh", ["p_hh_li", "p_wcorpw", "p_neu_al"], None,
     "o_ervaren_gezondheid", "inkomen+sociale huur+herkomst vs goede ervaren gezondheid"),
    ("ouderen~eenzaam", ["p_65_oo", "p_1p_hh", "p_verwed"], None,
     "o_eenzaam", "65+ en alleenwonend en verweduwd vs eenzaamheid (zwak)"),
    ("migrant~eenzaam", ["p_neu_al", "p_wcorpw", "p_hh_li"], None,
     "o_eenzaam", "herkomst+sociale huur+lage inkomens vs eenzaamheid"),
    ("migrant~sterk_eenzaam", ["p_neu_al", "p_wcorpw", "p_hh_li"], None,
     "o_sterk_eenzaam", "herkomst+sociale huur+lage inkomens vs sterke eenzaamheid"),
    ("campus~eenzaam", ["p_15_24", "p_1p_hh", "p_hh_li", "g_wozbag"], [1, 1, 1, -1],
     "o_eenzaam", "jong+alleenwonend+lage inkomens+lage WOZ vs eenzaamheid"),
    ("scheiding~eenzaam", ["p_gesch", "p_verwed"], None,
     "o_eenzaam", "gescheiden+verweduwd vs eenzaamheid (zwak, ruw)"),
]


def load_bundle():
    ds = json.loads(BUNDLE.read_text(encoding="utf-8"))
    yi = ds["years"].index(YEAR)
    buurten = [r for r in ds["regions"] if r["level"] == "buurt"]
    vals = ds["values"]

    def series(code, ind):
        arr = vals.get(code, {}).get(ind)
        return arr[yi] if arr else None

    return ds, buurten, series


def zscore(col):
    """Populatie-z-score (delen door N), NaN blijft NaN."""
    m = np.nanmean(col)
    sd = np.nanstd(col)  # ddof=0
    return (col - m) / sd if sd > 0 else col * 0.0


def complete_matrix(buurten, series, cols):
    """Matrix + codelijst van buurten met ALLE opgegeven kolommen aanwezig."""
    rows, codes, names = [], [], []
    for b in buurten:
        vec = [series(b["code"], c) for c in cols]
        if all(v is not None for v in vec):
            rows.append([float(v) for v in vec])
            codes.append(b["code"])
            names.append(b["name"])
    return np.array(rows, dtype=float), codes, names


def ols_standardized(X, y):
    """Gestandaardiseerde OLS-betas (X en y z-gescoord) + R²."""
    Xz = np.column_stack([zscore(X[:, j]) for j in range(X.shape[1])])
    yz = zscore(y)
    A = np.column_stack([np.ones(len(yz)), Xz])  # intercept
    coef, *_ = np.linalg.lstsq(A, yz, rcond=None)
    betas = coef[1:]  # intercept ~ 0 na standaardisatie
    pred = A @ coef
    ss_res = np.sum((yz - pred) ** 2)
    ss_tot = np.sum((yz - np.mean(yz)) ** 2)
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else 0.0
    return betas, float(r2)


def partial_corr(x, y, controls):
    """Partiële Pearson-correlatie van x en y na uitpartialiseren van controls."""
    C = np.column_stack([np.ones(len(x))] + [controls[:, j] for j in range(controls.shape[1])])
    rx = x - C @ np.linalg.lstsq(C, x, rcond=None)[0]
    ry = y - C @ np.linalg.lstsq(C, y, rcond=None)[0]
    return float(np.corrcoef(rx, ry)[0, 1])


def raw_corr(x, y):
    return float(np.corrcoef(x, y)[0, 1])


def is_oost(code):
    # Amsterdamse buurtcode: BU0363<stadsdeelletter>...; Oost = letter 'M'
    return len(code) > 6 and code[6] == "M"


def main():
    ds, buurten, series = load_bundle()
    n_ams = len(buurten)

    # ---- 1. k-means typologieën op de 14 gestandaardiseerde dimensies
    Xdim, codes, names = complete_matrix(buurten, series, DIMS)
    n_clust = len(codes)
    Xz = np.column_stack([zscore(Xdim[:, j]) for j in range(Xdim.shape[1])])

    silhouette = {}
    best_k, best_s, best_labels = None, -1, None
    for k in K_RANGE:
        km = KMeans(n_clusters=k, n_init=10, random_state=RANDOM_STATE).fit(Xz)
        s = silhouette_score(Xz, km.labels_)
        silhouette[str(k)] = round(float(s), 4)
        if s > best_s:
            best_k, best_s, best_labels = k, s, km.labels_

    # uitkomst-z per buurt (voor cluster-outcome-profielen), NaN waar ontbreekt
    out_z = {}
    for oid in OUTCOME_Z:
        col = np.array([series(c, oid) if series(c, oid) is not None else np.nan
                        for c in codes], dtype=float)
        out_z[oid] = zscore(col)

    cluster_profiles = []
    oost_assignment = []
    for cl in range(best_k):
        idx = [i for i in range(n_clust) if best_labels[i] == cl]
        oost_idx = [i for i in idx if is_oost(codes[i])]
        cluster_profiles.append({
            "cluster": cl,
            "n": len(idx),
            "n_oost": len(oost_idx),
            "dim_z": {DIMS[j]: float(np.mean(Xz[idx, j])) for j in range(len(DIMS))},
            "outcome_z": {oid: (float(np.nanmean(out_z[oid][idx]))
                                if np.any(~np.isnan(out_z[oid][idx])) else None)
                          for oid in OUTCOME_Z},
            "oost_buurten": [names[i] for i in oost_idx],
        })
    for i in range(n_clust):
        if is_oost(codes[i]):
            oost_assignment.append({"code": codes[i], "name": names[i],
                                    "cluster": int(best_labels[i])})

    # ---- 2. regressies per uitkomst (complete-case op 14 dims + de uitkomst)
    regressions = []
    for oid, label in REGRESSION_OUTCOMES:
        Xr, rcodes, _ = complete_matrix(buurten, series, DIMS + [oid])
        y = Xr[:, -1]
        Xd = Xr[:, :-1]
        betas, r2 = ols_standardized(Xd, y)
        order = sorted(zip(DIMS, betas), key=lambda t: -abs(t[1]))
        regressions.append({
            "outcome": oid, "label": label, "r2": r2, "n": len(rcodes),
            "betas": [[d, float(b)] for d, b in order],
        })

    # ---- 3. partiële correlaties (residuenmethode, pairwise complete)
    partial_correlations = []
    for name, x, y, ctrl, note in PARTIALS:
        Xp, pcodes, _ = complete_matrix(buurten, series, [x, y] + ctrl)
        xv, yv, cv = Xp[:, 0], Xp[:, 1], Xp[:, 2:]
        partial_correlations.append({
            "name": name, "x": x, "y": y, "controls": ctrl,
            "r_raw": round(raw_corr(xv, yv), 3),
            "r_partial": round(partial_corr(xv, yv, cv), 3),
            "n": len(pcodes), "note": note,
        })

    # ---- 4. composiet-z-indices (gemiddelde z van dims) vs een uitkomst
    composites = []
    for name, dims, signs, outcome, note in COMPOSITES:
        Xc, ccodes, _ = complete_matrix(buurten, series, dims + [outcome])
        yv = Xc[:, -1]
        zcols = [zscore(Xc[:, j]) * (signs[j] if signs else 1) for j in range(len(dims))]
        idx = np.mean(np.column_stack(zcols), axis=1)
        composites.append({
            "name": name, "dims": dims, "signs": signs, "outcome": outcome,
            "r": round(raw_corr(idx, yv), 3), "n": len(ccodes), "note": note,
        })

    result = {
        "meta": {
            "source": "GM0363.json Amsterdam",
            "year": YEAR,
            "level": "buurt",
            "n_clustering": n_clust,
            "n_amsterdam_buurten": n_ams,
            "dims": DIMS,
            "dim_labels": DIM_LABELS,
            "ecologisch_voorbehoud": (
                "Alle profielen zijn buurtgemiddelden (ecologisch niveau), geen "
                "individuen. Verbanden op buurtniveau mogen niet 1-op-1 op personen "
                "worden toegepast (ecological fallacy)."),
            "silhouette": silhouette,
            "chosen_k": best_k,
        },
        "cluster_profiles": cluster_profiles,
        "oost_cluster_assignment": oost_assignment,
        "regressions": regressions,
        "partial_correlations": partial_correlations,
        "composites": composites,
    }
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=None), encoding="utf-8")
    print(f"OK {OUT.name}: k={best_k} (silhouette {best_s:.4f}), "
          f"{n_clust}/{n_ams} buurten geclusterd, {len(regressions)} regressies, "
          f"{len(partial_correlations)} partiële correlaties, "
          f"{len(composites)} composieten, "
          f"{len(oost_assignment)} Oost-buurten toegewezen")


if __name__ == "__main__":
    main()
