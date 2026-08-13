# Achtergronddocument — databewerkingen per perspectief

**Dynamo Monitor Amsterdam Oost** · reproduceerbare verantwoording van elke bewerking op de brondata
**Versie:** 11 juli 2026 · **Status:** technische naslag (aanvullend op `AANNAMES.md`)

---

## 0. Waarom dit document

`AANNAMES.md` beschrijft *welke* keuzes zijn gemaakt en *waarom*. Dit document
beschrijft *hoe* die keuzes rekenkundig zijn uitgevoerd, zó gedetailleerd dat een
buitenstaander met de brondata en dit document **dezelfde getallen kan
reproduceren** — cel voor cel, formule voor formule.

Voor elk analyse-perspectief (tabblad) in de tool staat hieronder:

1. **Input** — welke brongegevens en welke kolommen.
2. **Bewerkingen** — de exacte volgorde van transformaties, met formules,
   constanten, drempels en afrondingen.
3. **Waar in de code** — het bestand/de functie die de bewerking uitvoert.
4. **Reproductie** — hoe je de stap zelfstandig naloopt.

> **Leeswijzer.** Hoofdstuk 1–2 beschrijven de bronnen en de **gemeenschappelijke
> pijplijn** (`../data-prep/build_data.py`) die de databundel maakt waar álle
> perspectieven op rusten. Hoofdstuk 3 t/m 11 beschrijven de bewerkingen *per
> perspectief*. Elke perspectief-sectie verwijst terug naar de gemeenschappelijke
> stappen en documenteert alleen wat het perspectief er bovenop doet.

> **Padnotatie.** Alle bestandsverwijzingen hieronder zijn relatief aan de map
> `docs/` waarin dit document staat: `../` verwijst naar de projectroot, en
> zusterdocumenten (`AANNAMES.md`, `CORRELATIE-ONTWERP.md`, `VOORUITBLIK-TEAM.md`)
> staan in dezelfde map.

---

## 1. Bronnen (provenance)

| Bron | Bestand(en) in repo | Herkomst | Peiljaren | Licentie |
|------|--------------------|----------|-----------|----------|
| **CBS Kerncijfers Wijken en Buurten (KWB)** | `../kwb-2016.xls` … `../kwb2025.xlsx` (projectroot) | CBS open data, reekspagina. 2016–2018 zijn `.xls` (vereisen `xlrd`); 2019+ zijn `.xlsx`. | 2016–2025 (2025 = **voorlopig**) | CBS open data (bronvermelding CBS) |
| **CBS variabelen­toelichting** | `Toelichting-variabelen-kwb-2025 (1).pdf` | CBS | 2025 | CBS |
| **RIVM Gezondheid per wijk en buurt (50150NED)** | `../external-data/raw/rivm_gezondheid_wijk_buurt_50150NED/data.csv` | RIVM/CBS StatLine (gedownload via `../external-data/download_sources.py`) | meetjaren 2012/2016/2020/2022/2024 (**gemodelleerd**, 18+) | CC BY 4.0 (RIVM/CBS) |
| **Amsterdamse gebiedsindeling (GGW)** | `../data-prep/gebieden_amsterdam.json` | `api.data.amsterdam.nl` + onderzoek.amsterdam.nl, GGW-indeling 24-3-2022 | — | gemeente Amsterdam open data |
| **Kaartgeometrie** | `../data-prep/geo/gm/*.geojson` → `../dashboard/public/data/gm/*.geojson` | PDOK / CBS Gebiedsindelingen (via `../data-prep/fetch_geo.py`), WGS84, vereenvoudigd | indeling 2023/2025 | PDOK open data |

**Reproductie van de download.** De externe bronnen zijn al aanwezig (~1 GB) en
opnieuw op te halen met `python external-data/download_sources.py`. Integriteit is
te verifiëren tegen `../external-data/checksums.sha256`. De catalogus met alle ~18
overwogen bronnen staat in `../external-data/DATA_CATALOGUS.md`; alleen RIVM 50150NED
is geïntegreerd (zie `AANNAMES.md` §9.5 voor de motivatie de rest niet op te nemen).

---

## 2. De gemeenschappelijke pijplijn — `../data-prep/build_data.py`

Eén Python-script leest de tien KWB-bestanden + RIVM + gebiedsindeling en schrijft
per gemeente een statische JSON-bundel die de tool client-side inlaadt. **Alle**
perspectieven lezen uit deze bundels; geen enkel perspectief raakt de ruwe
Excel-bestanden aan.

### 2.1 Draaien

```bash
# eenmalig
pip install pandas openpyxl xlrd          # xlrd is nodig voor de .xls van 2016-2018

# databundels bouwen
python data-prep/build_data.py            # schrijft dashboard/public/data/*

# regressietests (moet 0 fouten geven)
python data-prep/check_data.py

# app herbouwen
cd dashboard && npm install && npm run build
```

Output:
- `../dashboard/public/data/index.json` — lijst beschikbare gemeenten + niveaus.
- `../dashboard/public/data/gm/<GM>.json` — één bundel per gemeente (regio's,
  indicatoren, waarden, gentrificatie-config, uitkomst-ids, correlatie-meta).
- `../dashboard/public/data/gm/<GM>_wijken.geojson`,
  `../dashboard/public/data/gm/<GM>_buurten.geojson` en
  `../dashboard/public/data/gm/<GM>_gebieden.geojson` — kaartvlakken.

### 2.2 Inlezen & parseerregels (per KWB-jaargang)

Functie `load_year(year)`:

1. `pd.read_excel(FILES[year], dtype=str)` — **alles als tekst** inlezen, zodat CBS'
   eigen opmaak (decimaalkomma, voorloopnullen in codes) niet door pandas wordt
   verminkt.
2. Kolomnamen strippen: `df.columns = [c.strip() for c in df.columns]` — vangt de
   trailing spaces in de KWB-2024-koppen af.
3. Kolomhernoemingen toepassen (`RENAMES`, zie 2.3).
4. `gwb_code_10` (de regiocode) strippen tot schone string.

**Celparser `parse_cell(v)`** — de kern van de databetrouwbaarheid:

| Invoer | Resultaat |
|--------|-----------|
| `None` / `NaN` | `None` (ontbrekend) |
| getal (`int`/`float`) | `float(v)` |
| `""`, `"."`, `","`, `"x"`, `"-"` | `None` (CBS-notatie voor leeg/geheim) |
| `"26,4"` | `26.4` (decimaal**komma** → punt) |
| overige tekst | `None` |

> **Kernregel:** onderdrukt/geheim (`.`) en leeg zijn **`None`, nooit 0**. Deze
> regel geldt in élk perspectief — een 0 zou sommen, gemiddelden en correlaties
> vervuilen.

### 2.3 Kolomhernoemingen — conceptbreuken gladstrijken

CBS hernoemde kolommen tussen jaargangen. `RENAMES[year]` mapt oude → canonieke naam:

- **Opleiding** (`_OPL`): `a_opl_lg→a_opl_bvm`, `a_opl_md→a_opl_hvm`,
  `a_opl_hg→a_opl_hw`. Toegepast op **elke** jaargang (no-op waar de nieuwe namen al
  bestaan), zodat een toekomstige levering met de oude namen niet stil wordt
  genegeerd. Inhoudelijk identiek (geverifieerd op landelijke totalen).
- **WOZ** (`_WOZ`): `g_woz→g_wozbag`, **alleen 2016–2019**. Vanaf 2020 heet de
  kolom al `g_wozbag`. De reeks loopt continu door over de breuk (Amsterdam
  2019→2020 ratio ≈ 1,13, geen methodesprong) en wordt als één 10-jaars WOZ-reeks
  behandeld.

### 2.4 Regiokoppeling over jaargangen — het lastigste stuk

CBS wijzigt periodiek wijk-/buurtcodes bij herindelingen. Fout koppelen geeft
"spookbreuken" (het ene gebied krijgt de historie van een ander). De koppeling in
`find_row(reg)` (binnen `build_gemeente`) werkt in deze **prioriteitsvolgorde**:

1. **Codematch mét naamverificatie.** Als de code in de jaargang voorkomt én de
   genormaliseerde naam gelijk is aan de doelnaam → gebruik die rij.
   *Waarom naamcheck:* Zoetermeer en Diemen hebben na herverkaveling dezelfde code
   voor een **ander** gebied hergebruikt; blinde codematch gaf daar onjuiste trends.
2. **Geverifieerde Amsterdam-Oost-mapping** (`WIJK_MAP_OOST`, alleen Amsterdam):
   handmatig geverifieerde oude→nieuwe wijkcodes voor de 15 Oost-wijken. Let op: de
   volgorde **kruist** (WK036329 Dapperbuurt→WK0363ME; WK036330
   Transvaalbuurt→WK0363MD).
3. **Naamkoppeling** op genormaliseerde naam, apart voor wijken en buurten.
4. Geen match → cel blijft leeg (`None`). Nooit een gok.

**Naamnormalisatie `norm_name(s)`:** strip een leidend `"wijk NN "`/`"buurt NN "`
-voorvoegsel (CBS wisselt dit per jaargang), lowercase, verwijder alles behalve
`a-z0-9`. Zo matcht "Wijk 13 Dapperbuurt" met "Dapperbuurt".

### 2.5 Waardematrix vullen

Per jaar `yi` en per regio wordt voor elke kolom in `ALL_COLS` de cel geparsed en
weggeschreven naar `values[regiocode][indicator][yi]`. Twee bewerkingen daarbij:

- **Euro-omrekening** (`EURO_X1000 = {g_ink_pi, m_hh_ver, g_wozbag}`): de bron staat
  in ×€1.000; waarde × 1000 → hele euro's. (`26,4` → € 26.400.)
- Alle overige kolommen: waarde ongewijzigd (aantallen, percentages, promille, km).

### 2.6 Afgeleide indicatoren

CBS levert sommige aandelen niet als kolom; die worden zelf berekend (`DERIVED`),
teller/noemer uit **dezelfde regio-rij en hetzelfde jaar**, ×100, **1 decimaal**:

| Afgeleide | Formule |
|-----------|---------|
| `p_00_14`, `p_15_24`, `p_65_oo` | leeftijdsgroep ÷ `a_inw` × 100 |
| `p_1p_hh`, `p_hh_m_k` | huishoudenstype ÷ `a_hh` × 100 |
| `p_neu_al` | `a_neu_al` ÷ `a_inw` × 100 (vanaf 2023) |
| `p_verwed` | `a_verwed` ÷ `a_inw` × 100 |
| `p_gesch` | `a_gesch` ÷ `a_inw` × 100 |

`p_verwed` en `p_gesch` zijn toegevoegd omdat verweduwing/scheiding sterke
eenzaamheidsvoorspellers zijn (gebruikt in *Inzichten* en het thema Eenzaamheid).

### 2.7 RIVM-uitkomsten inlezen en koppelen

Functie `load_rivm()` leest de RIVM-CSV
(`../external-data/raw/rivm_gezondheid_wijk_buurt_50150NED/data.csv`) volgens
`../data-prep/rivm_outcome_spec.json`:

- `periodMap` mapt de RIVM-perioderaaien op kalenderjaren; alleen meetjaren die op
  de tool-jaaras vallen (**2016/2020/2022/2024**; 2012 vervalt).
- Per outcome-indicator (`id` met prefix `o_`) wordt `rivmColumn` geparsed met
  dezelfde `parse_cell`.
- Elke uitkomst krijgt `estimateType: "gemodelleerd"` en een `direction`
  (`hoog`=slechter, `laag`=beter, `neutraal` voor `o_mantelzorger` — hoge waarde is
  niet eenduidig "meer behoefte").

**Merge (op code, niet op naam):** RIVM volgt indeling 2024. Codes die tussen de
RIVM-indeling (2024) en de tool-indeling (2025) van **naam veranderen** (dus:
hergebruikt voor een ander gebied) worden **overgeslagen** (`unstable_codes`), zodat
een uitkomst nooit aan de verkeerde geografie hangt. Gevolg: Amsterdam ~95% wijk /
~80% buurt-dekking; Zoetermeer heeft door codehergebruik géén RIVM-uitkomsten.

### 2.8 Aggregatie naar stadsdeel & gebied (Amsterdam)

Stadsdeel- en gebiedstotalen staan **niet** in CBS en worden zelf geaggregeerd uit
de onderliggende wijken. Regels (per jaar, per aggregaatcode):

- **Dekkingsdrempel:** een aggregaat krijgt alleen een waarde als
  `≥ ceil(0.8 × aantal wijken)` van de leden gevuld is.
- **Aantallen** (`a_*`): som van de gevulde wijken.
- **Huishoudensgrootte** `g_hhgro` = Σinwoners ÷ Σhuishoudens (2 decimalen).
- **Bevolkingsdichtheid** `bev_dich` = Σinwoners ÷ Σland­oppervlak, waarbij het
  oppervlak per wijk wordt teruggerekend als `a_inw / bev_dich`.
- **Percentages/gemiddelden:** gewogen gemiddelde. Weegfactor:
  - **naar woningen** (`a_woning`) voor `WEIGHT_BY_WON = {p_koopw, p_wcorpw, g_wozbag}`;
  - **naar huishoudens** (`a_hh`) voor `WEIGHT_BY_HH = {p_hh_li, m_hh_ver}`;
  - **naar inwoners** (`a_inw`) voor de rest. (1 decimaal.)
- **Mediaan vermogen** `m_hh_ver` wordt **niet** geaggregeerd — medianen zijn niet
  optelbaar; er verschijnt bewust geen schijnmediaan op aggregaatniveau.
- **RIVM-uitkomsten** op aggregaat: inwoner-gewogen gemiddelde van de
  wijk-percentages (benadering; percentages zijn van 18+).

Elk aggregaat draagt `members` = aantal onderliggende wijken (dekking zichtbaar in
de tool). Gebieden met één wijk nemen het wijkcijfer over (dekking 1/1).

### 2.9 Beschikbaarheid per indicator per jaar

`years_available(ind)` neemt een jaar op als `≥ ceil(0.8 × aantal wijken)` gevuld is
(harde drempel voor CBS-indicatoren). `years_available_soft(ind)` gebruikt **≥50%**
voor RIVM-uitkomsten (partiële dekking blijft bruikbaar; de minimum-N in *Samenhang*
bewaakt betrouwbaarheid). Alleen jaren die de drempel halen komen in
`indicator.years`.

> **Belangrijk voor *Vooruitblik*:** `indicator.years` toont voor sociaaleconomische
> reeksen vaak alleen 2023–2025, maar de **kern-demografie** (`a_inw`,
> `a_00_14/15_24/45_64/65_oo`, `a_hh`, `a_1p_hh`) heeft wél volledige `values`
> 2016–2025 — daarom prognosticeerbaar.

### 2.10 Buurt-allowlist

Op buurtniveau zijn alleen voldoende gevulde indicatoren behouden
(`BUURT_INDICATOREN`): demografie + huishoudens + herkomst + de vier
gentrificatiecomponenten (`g_wozbag`, `p_koopw`, `p_wcorpw`, `g_ink_pi`, `p_hh_li`)
+ RIVM-uitkomsten. Sociaaleconomische registers zijn op buurtniveau te sterk
onderdrukt en worden weggelaten om schijnprecisie te voorkomen.

### 2.11 Outputstructuur (per bundel)

```
meta:        { title, source, generated, yearsCovered, gemeente }
years:       [2016..2025]
regions:     [{ code, name, level, sd?, gb?, wk?, members? }]
indicators:  [{ id, label, shortLabel, unit, theme, description,
                direction, years, derived?, isOutcome?, estimateType? }]
values:      { <regiocode>: { <indicator>: [v_2016 .. v_2025] } }   // null = ontbreekt
themes:      [{ id, title, dynamoService, description, indicatorIds, headline }]
gentrification: { components:[…], note }                            // config, zie H7
outcomeIds:  [ o_… ]
correlation: { rivmMeetjaren:[2016,2020,2022,2024], note }
```

---

## 3. Perspectief — Overzicht

**Doel:** samenvattend wijkprofiel per thema (stat-tegels + ranglijst).

- **Input:** `values` + `indicators` uit de bundel; de per-thema `headline`-indicatoren.
- **Bewerkingen:** geen nieuwe aggregatie. Wel:
  - **Relatieve weergave** (optioneel): procentuele afwijking t.o.v. de gekozen
    referentie (gemeente of stadsdeel-/scope-totaal) = `(waarde − ref) / ref × 100`.
    **Uitgeschakeld voor absolute aantallen** — een wijk tegen het stadstotaal
    afzetten is betekenisloos; concentratie-index alleen voor
    percentages/gemiddelden/dichtheden (`AANNAMES.md` §4.5).
  - **Richting** (`indicator.direction`) bepaalt sortering van de ranglijst en
    kleurrichting: `hoog` = hogere waarde bovenaan/sterker signaal.
- **Waar:** `../dashboard/src/views/Overzicht.tsx`, helpers in `../dashboard/src/lib/data.ts`,
  `../dashboard/src/lib/format.ts`.
- **Reproductie:** lees `values[wijkcode][indicator][jaarindex]`; voor relatieve
  weergave deel door de referentiewaarde in hetzelfde jaar.

---

## 4. Perspectief — Kaart (choropleth)

**Doel:** ruimtelijk beeld per indicator/jaar, absoluut of relatief.

- **Input:** `values` + de wijk-/buurt-/gebied-geojson-lagen (zie H2.1). Koppeling
  vlak↔waarde op `properties.code`.
- **Bewerkingen:**
  - **Absolute modus:** waarde rechtstreeks; klassegrenzen data-gedreven (min–max
    over de selectie). **Kaartschaal vast over jaren:** de kleurgrenzen worden over
    álle beschikbare jaren van de selectie bepaald, zodat dezelfde kleur in elk jaar
    hetzelfde betekent (`AANNAMES.md` §7.5).
  - **Relatieve modus:** procentuele afwijking t.o.v. referentie op een
    **divergerende** schaal (blauw ↔ rood, neutraal midden). CVD-veilig palet.
  - **Beschikbaarheid dynamisch:** per indicator × niveau × focus bepaalt de tool
    welke jaren ≥60% gevulde gebieden hebben; een afwijkend getoond jaar wordt
    gemeld. Ontbrekende vlakken tonen een "geen data"-reden via `noDataReason()`.
- **Waar:** `../dashboard/src/views/Kaart.tsx`, `../dashboard/src/components/Choropleth.tsx`,
  `../dashboard/src/lib/data.ts`.
- **Reproductie:** geometrie op `code` joinen met `values`; klassegrenzen = min/max
  over alle geselecteerde jaren.

---

## 5. Perspectief — Ontwikkeling (trends over tijd)

**Doel:** tijdreeks per indicator/gebied.

- **Input:** de volledige `values[code][indicator]`-array (2016–2025).
- **Bewerkingen:** lijnen tekenen op de gevulde jaren; ontbrekende jaren
  onderbroken. Historische koppeling over de codewisseling 2023 is al in de bundel
  verwerkt (H2.4). Voor Amsterdamse buurten start de reeks veelal 2023
  (codewisseling 2022, geen overgangstabel gelegd → `AANNAMES.md` §1.4).
  Conceptbreuken (herkomst westers/niet-westers→NL/Europa/buiten Europa; armoede
  alleen 2024) worden **niet** over de breuk doorgetrokken.
- **Waar:** `../dashboard/src/views/Trends.tsx`, `../dashboard/src/components/LineChart.tsx`.
- **Reproductie:** plot de `values`-array tegen `years`; behandel `null` als gat.

---

## 6. Perspectief — Vooruitblik (demografische prognose)

**Doel:** omvang van 7 Dynamo-doelgroepen tonen richting 2026–2055.
**Volledig client-side; geen pijplijnwijziging.**

- **Input:** de historische reeks 2016–2025 van 7 absolute indicatoren
  (`a_65_oo`, `a_00_14`, `a_15_24`, `a_1p_hh`, `a_45_64`, `a_hh`, `a_inw`) **plus**
  `officialForecast[regiocode][indicatorId][jaar]`, gebouwd door
  `../data-prep/official_forecast.py` uit twee gemeentelijke bronnen (O&S-Excel
  voor Oost, BBGA voor heel Amsterdam) en toegevoegd aan de `GM0363`-bundel.
- **Waar:** `../dashboard/src/lib/forecast.ts`, `../dashboard/src/components/ForecastChart.tsx`,
  `../dashboard/src/views/Vooruitblik.tsx`. Methode-verantwoording: `VOORUITBLIK-TEAM.md`.

### 6.1 Rekenstappen (exact, sinds aug. 2026)

Er is **geen eigen trendmodel meer** — dat is volledig verwijderd (zie §6.2 voor
wat er was). De huidige logica is bewust simpel:

1. **Waarneming.** Voor elk jaar in `ds.years` met een niet-lege waarde: toon het
   punt (`forecast: false`).
2. **Officiële prognose.** Voor elk jaar in `HORIZONS = [2026, 2030, 2035, 2040,
   2050, 2055]` na het laatste waarnemingsjaar: als
   `officialForecast[code][indicator][jaar]` bestaat, toon dat punt exact zoals
   gepubliceerd (`forecast: true`). Bestaat het niet, dan wordt er **geen punt**
   toegevoegd voor dat jaar — geen doorgetrokken trend, geen afgeleide waarde.
3. **Geen band.** Elk punt is een los getal; er is geen `lo`/`hi`-interval, want
   geen van beide bronnen publiceert er een.
4. **Geen raking.** Sub-gebieden worden niet meer geschaald naar een
   ankergebied — elk gebied toont uitsluitend zijn eigen waarneming/officiële
   prognose, onafhankelijk van andere gebieden.

`views/Vooruitblik.tsx` rendert een expliciete lege staat zodra een
(gebied, doelgroep, horizonjaar)-combinatie geen officieel punt heeft, in
plaats van de grafiek stil leeg te laten of een geschat getal te tonen.

### 6.2 Vroegere methode (verwijderd aug. 2026, hier alleen ter archief)

Tot augustus 2026 deed dit bestand zelf een log-lineaire trendextrapolatie per
gebied × doelgroep, met omvang-gewogen shrinkage naar het bovenliggende gebied,
gedempte en glad gecomprimeerde groeivoeten, top-down raking en een
log-symmetrische onzekerheidsband. De volledige rekenstappen (fit, shrinkage-
gewichten, `softCap`/`tanh`-compressie, demping, raking, bandbreedte) staan niet
langer in dit document maar zijn te reproduceren uit de git-geschiedenis van
`../dashboard/src/lib/forecast.ts` (commits `eeeee0e` en `d9d9426`).

**Waarom verwijderd:** geen demografische onderbouwing (geen vitale statistiek,
geen woningbouwpijplijn) en het toonde overal een getal, ook waar de
onderliggende reeks kort, ruizig of onderdrukt was — een schijn van dekking die
de kwaliteit van de brondata niet had. Zie `VOORUITBLIK-TEAM.md` §3 voor de
volledige toelichting.

### 6.3 Reproductie

Neem de `values`-reeks van bijv. `a_65_oo` voor een wijk, pas stap 1–5 toe met de
genoemde constanten. `forecastArea(ds, indicator, code)` doet dit voor één gebied
zonder raking; `forecastGroup(...)` voor een set met raking naar een anker.

---

## 7. Perspectief — Gentrificatie

**Doel:** signaleren waar een gebied sneller gentrificeert dan de andere gebieden op
hetzelfde niveau. Config in de bundel (`gentrification`), berekening client-side.

- **Input:** vier CBS-componenten over een instelbare periode `[y0, y1]`:

| Component | id | modus | teken (`sign`) | logica |
|-----------|-----|-------|----------------|--------|
| Woningwaarde (WOZ) | `g_wozbag` | pct | +1 | stijging = gentrificatie |
| Inkomen per inwoner | `g_ink_pi` | pct | +1 | stijging = instroom kapitaalkracht |
| Corporatiewoningen | `p_wcorpw` | pp | −1 | krimp = verdringing sociale huur |
| Aandeel lage inkomens | `p_hh_li` | pp | −1 | daling = verdringing doelgroep |

- **Waar:** `../dashboard/src/lib/gentrification.ts`; config `GENTRIFICATION` in
  `../data-prep/build_data.py`; `../dashboard/src/views/Gentrificatie.tsx`. Onderbouwing `AANNAMES.md` §8.

### 7.1 Rekenstappen (exact)

1. **Ruwe verandering** per gebied × component over `[y0,y1]`:
   - modus `pct`: `(v1 − v0) / v0 × 100` (`null` als `v0 = 0` of een jaar ontbreekt);
   - modus `pp`: `v1 − v0` (procentpuntverschil).
2. **Standaardisatie per component** over de gebieden op hetzelfde niveau: bereken
   gemiddelde en **populatie**-standaarddeviatie (`variantie = Σ(v−μ)² / N`, dus
   delen door N, niet N−1) van de beschikbare veranderingen.
3. **Z-score × richting:** `z = ((verandering − μ) / σ) × sign`. Componenten zonder
   waarde of met `σ = 0` tellen niet mee.
4. **Index** = gemiddelde van de beschikbare component-z-scores (`coverage` =
   hoeveel van de 4 meetellen). **Positief = gentrificeert sneller dan het
   gemiddelde gebied** op dat niveau.

### 7.2 Periodekeuze & dekking

- `gentYears(...)`: jaren waarin ≥2 van de 4 componenten ≥50% gebiedsdekking hebben.
- `gentYearsFull(...)`: jaren waarin **alle 4** ≥50% dekking hebben — hieruit kiest
  de tool de standaardperiode, zodat kaart én verdringingsscatter gevuld zijn.
- Op buurtniveau is inkomen (`g_ink_pi`) vaak onderdrukt; de index rekent dan met de
  overige componenten en toont `coverage` per gebied.

### 7.3 Reproductie

Per gebied: bereken de vier veranderingen, standaardiseer over de gebiedsset
(populatie-sd), teken met `sign`, middel de beschikbare. Amsterdam-Oost heeft de
rijkste reeks (2016–2024, alle componenten).

> **Voorbehoud:** relatieve maat, geen absolute norm en **geen bewijs van
> individuele verdringing**.

---

## 8. Perspectief — Samenhang (correlatie X × Y)

**Doel:** samenhang tussen socio-demografische gebiedskenmerken (X, CBS) en
gezondheids-/welzijnsuitkomsten (Y, RIVM), cross-sectioneel over gebieden binnen
scope×niveau. **Verkennend signaleringsinstrument, geen causaal bewijs.**

- **Input:** relatieve X-indicatoren (`p_*`, `g_ink_pi`, `m_hh_ver`, `g_wozbag`,
  `g_afs_hp`) en RIVM-Y (`o_*`). **Absolute aantallen als X zijn uitgesloten** (die
  correleren met gebiedsomvang → schijncorrelatie).
- **Waar:** `../dashboard/src/lib/correlation.ts`, `../dashboard/src/views/Samenhang.tsx`,
  `../dashboard/src/components/Heatmap.tsx`. Volledig ontwerp: `CORRELATIE-ONTWERP.md`.

### 8.1 Rekenstappen (exact)

1. **Paren vormen** (`pearson`/`spearman`): per gebied in de lijst het (x,y)-paar
   uit hetzelfde jaar; alleen als **beide** waarden aanwezig en eindig zijn
   (**pairwise complete deletion**; onderdrukt = uitgesloten, nooit 0). `n` = aantal
   complete paren.
2. **Peiljaar → RIVM-meetjaar:** `year` wordt met `nearestYear` naar het
   dichtstbijzijnde RIVM-meetjaar (2016/2020/2022/2024) gesnapt en dat wordt gemeld.
3. **Coëfficiënt:**
   - **Spearman ρ (standaard):** rangen (gemiddelde rang bij gelijke waarden),
     daarna Pearson op de rangen. Robuust bij begrensde/scheve percentages, kleine N
     en uitschieters.
   - **Pearson r (optioneel):** `Σdxdy / √(Σdx²·Σdy²)`.
   - `n < 3` → geen coëfficiënt.
4. **Trendlijn** (voor de scatter): OLS op de **ruwe** waarden
   (`slope = Σdxdy/Σdx²`, `intercept = ȳ − slope·x̄`) — hulplijn, niet de
   gerapporteerde ρ.
5. **95%-BI** (`fisherCI`): via Fisher-z. SE = `1/√(n−3)` (Pearson) of
   `√(1,06/(n−3))` (Spearman, Fieller-correctie tegen een ~3% te smal interval).
6. **p-waarde** (`approxP`, verkennend): `t = |r|·√((n−2)/(1−r²))`, staartkans via
   regularized incomplete beta (`ibeta`). Bij `|r| ≥ 1` of `n < 3` geen p.
7. **Sterktelabel** (`strength`, op |r|): <0,2 verwaarloosbaar · 0,2–0,4 zwak ·
   0,4–0,6 matig · 0,6–0,8 sterk · ≥0,8 zeer sterk.

### 8.2 Betrouwbaarheidsregime (uit het ontwerp)

| n (complete paren) | Gedrag |
|--------------------|--------|
| < 8 | geen coëfficiënt; alleen scatter + waarschuwing |
| 8–11 | tonen, gemarkeerd als indicatief/zeer onzeker |
| ≥ 12 | normaal |

- **Selectiebias:** waarschuwing als >25% van de gebieden in een paar wegvalt
  (onderdrukking is niet willekeurig).
- **Ecologisch + gemodelleerd + circulariteit:** permanente kanttekeningen; p is
  door ruimtelijke autocorrelatie en multiple testing te optimistisch → nadruk op
  effectgrootte + n + BI.

### 8.3 Reproductie

Kies scope×niveau (de N), snap jaar naar RIVM-meetjaar, vorm pairwise-complete
paren, bereken Spearman ρ + Fisher-BI + p zoals boven. Zie `AANNAMES.md` §9.6–9.7.

---

## 9. Perspectief — Inzichten (doelgroepdossiers, multivariaat)

**Doel:** 25 meer-dimensionale doelgroepdossiers (5 per Dynamo-activiteit), elk met
persona, 3–6-dimensieprofiel en een multivariate koppeling aan uitkomsten.
Onderbouwd door een **eenmalig berekend statistisch fundament**.

- **Input:** `../dashboard/public/data/gm/GM0363.json` (Amsterdam), buurtniveau, jaar 2024.
- **Fundament:** `../data-prep/multivar_foundation.json` (het rekenresultaat) →
  gebruikt door `../dashboard/public/data/insights.json` en `../dashboard/src/views/Inzichten.tsx`.
- **Methode-onderbouwing:** `AANNAMES.md` §10.

### 9.1 Wat het fundament bevat

```
meta:                  { source, year:2024, level:"buurt", n_clustering:416,
                         n_amsterdam_buurten:517, dims:[14], dim_labels,
                         silhouette:{3..7}, chosen_k:4, ecologisch_voorbehoud }
cluster_profiles:      k-means typologieën (k=4); cluster 0=gezinnen/koop,
                         1=studenten/starters, 2=gemengd, 3=migrant-armoede
oost_cluster_assignment: clustertoewijzing van de Oost-buurten
regressions:           11× per uitkomst { outcome, label, r2, n, betas:[[dim, beta]…] }
partial_correlations:  22× { name, x, y, controls[], r_raw, r_partial, n, note }
composites:            16× { name, dims[], signs, outcome, r, n, note }
```

De regressies, partials en composieten zijn zó gekozen dat **élke in de 25 dossiers
(`insights.json`) geciteerde statistiek** herleidbaar is tot dit fundament.

De **14 dimensies:** `p_00_14, p_15_24, p_65_oo, p_1p_hh, p_hh_m_k, g_hhgro,
p_neu_al, p_hh_li, bev_dich, p_koopw, p_wcorpw, g_wozbag, p_verwed, p_gesch`.
Inkomen (`g_ink_pi`, `m_hh_ver`) is op buurtniveau te sterk onderdrukt en vervangen
door `p_hh_li` als inkomens-proxy.

### 9.2 De vier analyses (exact)

1. **k-means buurttypologieën.** Standaardiseer de 14 dimensies (z-scores),
   draai k-means voor k=3..7, kies k via de **silhouette-score** (gekozen: k=4,
   silhouette 0,254 — zwakke structuur; k=3 geeft 0,238). Elk cluster = een buurttype
   met een gemiddeld z-profiel. N=416 buurten met volledige dekking (van 517).
2. **Meervoudige lineaire regressie** per uitkomst (11 stuks: `o_eenzaam`,
   `o_ervaren_gezondheid`, `o_moeite_rondkomen`, `o_langdurige_aandoening`,
   `o_mantelzorger`, `o_veel_stress`, `o_krijgt_steun`, `o_obesitas`,
   `o_sterk_eenzaam`, `o_suicidegedachten`, `o_hoog_risico_angst_depressie`):
   uitkomst ~ 14 gestandaardiseerde dimensies, R² ≈ 0,85–0,94 (bv. eenzaamheid
   R²=0,925, N=416). **Let op:** de predictoren zijn zwaar collineair (VIF tot ~50),
   dus de betas zijn **geen** onafhankelijke, causale drivers — tekenomkeringen kunnen
   artefact zijn (zie AANNAMES §10.2; UI-notice in `Inzichten.tsx`).
3. **Partiële correlaties** (22 stuks, residuenmethode) om schijnverbanden te
   ontmaskeren: bv. `eenzaam ~ alleenwonend | leeftijd`: r_raw=0,513 → r_partial=0,409
   na controle voor leeftijdsopbouw (`p_65_oo`, `p_15_24`).
4. **Composiet-z-indices** (16 stuks): gemiddelde z van een dimensieset (optioneel met
   teken) gecorreleerd met een uitkomst — het prioriteringsinstrument achter de dossiers
   (bv. `migrant~eenzaam` = z(herkomst+sociale huur+lage inkomens) vs `o_eenzaam`, r=+0,89).

### 9.3 Reproduceerbaarheid — begeleidend script

> **Let op:** het fundament (`../data-prep/multivar_foundation.json`) was oorspronkelijk
> berekend zonder dat het **generatiescript in de repo bewaard** was. Het script is
> gereconstrueerd volgens de hierboven gedocumenteerde methode en toegevoegd als
> **`../data-prep/multivar_foundation.py`**. Het leest de gebouwde Amsterdam-bundel en
> herberekent typologieën, regressies, partiële correlaties én composiet-indices.
>
> Het script is later **uitgebreid** zodat élke in de dossiers geciteerde statistiek
> reproduceerbaar is: 5 extra regressies (obesitas, veel_stress, krijgt_steun,
> sterk_eenzaam, suïcidegedachten), 16 composiet-z-indices en 17 extra partiële
> correlaties. `insights.json` is daarna tegen dit fundament geverifieerd en gecorrigeerd
> (consistente clusternummers, R²/beta's per uitkomst, causale "driver"-taal verwijderd).

```bash
pip install numpy scikit-learn
python data-prep/multivar_foundation.py     # herschrijft data-prep/multivar_foundation.json
```

### 9.4 Voorbehoud (hard)

Alle uitkomsten zijn **RIVM-gemodelleerde buurtgemiddelden**; verbanden zijn
ecologisch (buurtniveau) en mogen niet 1-op-1 op individuen worden toegepast
(ecological fallacy). De dossiers benoemen dit expliciet.

---

## 10. Perspectief — Tabel

**Doel:** alle waarden platslaan naar een doorzoekbare/exporteerbare tabel.

- **Input:** `values` + `indicators` + `regions`.
- **Bewerkingen:** geen herberekening; wél formatteren per `unit` (euro, %, ‰, km,
  aantal) via `../dashboard/src/lib/format.ts`, en CSV-export via `toCsv`/`downloadCsv`. Promille
  (`p_geb`, `p_ste`, `p_wmo_t`) met ‰; euro's als hele euro's (al ×1000 in de bundel).
- **Waar:** `../dashboard/src/views/Tabel.tsx`, `../dashboard/src/components/DataTable.tsx`.
- **Reproductie:** directe uitlezing van de bundel; geen transformatie.

---

## 11. Kwaliteitsborging — `../data-prep/check_data.py`

Regressietests die na élke build moeten slagen (exitcode 1 bij fout). Bewaken o.a.:

- elke gemeente ≥1 indicator; geen indicator met lege jarenlijst; elke indicator
  heeft een richting; geometriecodes ⊆ regiocodes.
- Amsterdam: 2016 aanwezig in Oost; alle 15 Oost-wijken met `a_inw` 2016;
  één-wijkgebieden gevuld met dekking 1/1; **mediaan vermogen niet op aggregaten**;
  26 gebieden (25 GGW + Westpoort); som Oost-wijken == stadsdeelaggregaat 2024.
- Gentrificatie: 4 componenten; WOZ-reeks continu 2016–2025 en **geen sprong** over
  de `g_woz→g_wozbag`-breuk (1,0 < ratio < 1,4); WOZ Oost 2024 plausibel.
- **Spookbreuken:** over alle 35 gemeenten controleren dat `a_inw` geen onmogelijke
  wijk-sprong maakt (factor >2,5 bij >1000 inwoners); Zoetermeer/Diemen expliciet
  (0 spookbreuken); ≤6 resterende sprongen (echte nieuwbouw zoals IJburg).
- RIVM: ≥15 uitkomsten, alle "gemodelleerd", meetjaren 2016/2020/2022/2024,
  plausibele percentages, ook op buurtniveau (>40 buurten met eenzaamheid).

---

## 12. Reproduceerbaarheidschecklist

1. `pip install pandas openpyxl xlrd numpy scikit-learn scipy`
2. Brondata aanwezig: `kwb-2016.xls … kwb2025.xlsx` in de root; RIVM in
   `../external-data/raw/…` (evt. `python external-data/download_sources.py`,
   verifieer `../external-data/checksums.sha256`).
3. `python data-prep/build_data.py` → bundels in `../dashboard/public/data/`.
4. `python data-prep/multivar_foundation.py` → herbereken *Inzichten*-fundament.
5. `python data-prep/check_data.py` → **0 fouten** vereist.
6. `cd dashboard && npm install && npm run build` → statische `dist/`.
7. Nieuwe CBS-jaargang: leg `kwb*.xlsx` in de root, voeg toe aan `FILES` in
   `../data-prep/build_data.py`, controleer eventuele kolomhernoemingen in `RENAMES`, herhaal 3–6.

---

## 13. Bestandsverwijzingen (waar staat wat)

| Bewerking | Bestand |
|-----------|---------|
| Gehele databundel-pijplijn | `../data-prep/build_data.py` |
| RIVM-selectie & definities | `../data-prep/rivm_outcome_spec.json` |
| Amsterdamse gebiedsindeling | `../data-prep/gebieden_amsterdam.json` |
| Kaartgeometrie ophalen | `../data-prep/fetch_geo.py` |
| Multivariaat fundament (resultaat) | `../data-prep/multivar_foundation.json` |
| Multivariaat fundament (script) | `../data-prep/multivar_foundation.py` *(nieuw, H9.3)* |
| Prognose-engine | `../dashboard/src/lib/forecast.ts` |
| Gentrificatie-index | `../dashboard/src/lib/gentrification.ts` |
| Correlatie | `../dashboard/src/lib/correlation.ts` |
| Regressietests | `../data-prep/check_data.py` |
| Externe-bronnen-catalogus | `../external-data/DATA_CATALOGUS.md` |
| Aannames (het "waarom") | `AANNAMES.md` |
| Correlatie-ontwerp | `CORRELATIE-ONTWERP.md` |
| Vooruitblik-methode | `VOORUITBLIK-TEAM.md` |

---

*Wijzig je een bewerking? Pas dan `../data-prep/build_data.py` (of de betrokken `../dashboard/src/lib/*.ts`),
dit document, `AANNAMES.md` en `../dashboard/src/views/Verantwoording.tsx` samen aan, en draai
`python data-prep/check_data.py`.*
