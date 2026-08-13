# Vooruitblik — teamsamenstelling, methode en aannames

Dit document beschrijft het team dat het tabblad **Vooruitblik** (demografische
prognose van Dynamo-doelgroepen) heeft opgezet, de gekozen methode en de
aannames die daarbij expliciet zijn gemaakt.

> **Statusnotitie (aug. 2026).** Het eigen trendmodel dat dit team oorspronkelijk
> bouwde (§3 hieronder) is op verzoek van de opdrachtgever **volledig
> verwijderd** en vervangen door uitsluitend officiële gemeentelijke
> puntprognoses (§4): "te naïef" — het had geen demografische drivers (geen
> vitale statistiek, geen woningbouwpijplijn) en het liet overal een getal
> zien, ook waar dat getal weinig voorstelde. §3 blijft hieronder staan als
> onderbouwing van *wat er was en waarom het verving is*, niet als beschrijving
> van de huidige code. De huidige, enige methode staat in §4.

## 1. Teamsamenstelling

De opdracht — *"stel een team samen van in ieder geval een sociaal-demograaf die
prognoses maakt van de ontwikkeling van de doelgroepen van Dynamo, leg contact
met het inzichtenteam, voorspel de omvang op zo laag mogelijk geografisch niveau,
visualiseer en trek conclusies"* — is uitgevoerd door een klein, rolgericht team.

| Rol | Verantwoordelijkheid | Bijdrage aan dit tabblad |
|-----|----------------------|--------------------------|
| **Sociaal-demograaf (lead)** | Prognosemethode kiezen die past bij de databeperkingen; doelgroepen afbakenen; methode verantwoorden en citeren | Leverde de methodische onderbouwing van het (sindsdien verwijderde) trendmodel, §3 |
| **Specialist kleine-gebiedsstatistiek** | Ruis van kleine gebieden temmen; onderdrukking en codehergebruik afvangen; consistentie tussen niveaus borgen | Ontwierp de (sindsdien verwijderde) shrinkage en top-down raking, §3 |
| **Data-engineer** | Methode implementeren in de bestaande React/TS-monitor, reproduceerbaar en zonder pijplijnwijziging | Bouwde `lib/forecast.ts`, `components/ForecastChart.tsx`, `views/Vooruitblik.tsx` en `data-prep/official_forecast.py`; berekening draait client-side op de bestaande databundel |
| **Inzichtenteam** (bestaand; het tabblad *Inzichten* zelf is aug. 2026 verwijderd als placeholder) | 25 multivariate buurtinzichten per Dynamo-activiteit (`public/data/insights.json`) | Geraadpleegd voor de doelgroepdefinities en de vertaling naar diensten; de prognose-doelgroepen sluiten aan op hun activiteitindeling (kinderwerk, jongerenwerk, ouderenwerk, eenzaamheids-/buurtwerk, mantelzorg) |

> **Contact met het inzichtenteam.** De doelgroepen in de Vooruitblik zijn
> één-op-één gekoppeld aan de Dynamo-activiteiten die het inzichtenteam hanteert.
> Beide tabbladen delen het ecologische voorbehoud (buurtgemiddelden, geen
> individuen).

## 2. Doelgroepen

| Doelgroep | CBS-indicator | Dynamo-dienst | Officiële prognose? |
|-----------|---------------|---------------|----------------------|
| Totaal inwoners | `a_inw` | Draagvlak en schaal van alle voorzieningen | Heel Amsterdam (gemeente/stadsdeel/gebied/wijk) — BBGA |
| Ouderen (65-plus) | `a_65_oo` | Ouderenwerk, seniorenactiviteiten, welzijn op recept | Heel Amsterdam (gemeente/stadsdeel/gebied/wijk) — BBGA |
| Kinderen (0–14) | `a_00_14` | Kinderwerk en jeugdwerk | Alleen stadsdeel Oost + zijn 15 wijken — O&S-Excel |
| Jongeren (15–24) | `a_15_24` | Jongerenwerk en talentontwikkeling | Alleen stadsdeel Oost + zijn 15 wijken — O&S-Excel |
| Aankomende senioren (45–64) | `a_45_64` | Mantelzorg en voorbereiding op vergrijzing | Alleen stadsdeel Oost + zijn 15 wijken — O&S-Excel |
| Alleenwonenden | `a_1p_hh` | Buurtwerk en eenzaamheidsbestrijding | **Nergens** — geen bron heeft deze variabele |
| Huishoudens | `a_hh` | Buurtwerk, Huizen van de Wijk, wonen | **Nergens** — geen bron heeft deze variabele |

Geen van beide bronnen publiceert op **buurtniveau**, en geen enkele gemeente
buiten Amsterdam heeft een vergelijkbare bron in deze tool. Waar de tabel
hierboven "nergens"/geen dekking aangeeft, toont Vooruitblik dat expliciet als
lege staat — zie §4.

## 3. Vroegere methode (verwijderd aug. 2026 — hier alleen ter verantwoording)

Dit was de oorspronkelijke, sindsdien volledig verwijderde aanpak: een eigen
log-lineaire trendextrapolatie per doelgroep en gebied, geschat op 2016–2025,
met omvang-gewogen shrinkage naar het bovenliggende gebied, gedempte
groeivoeten en top-down raking voor consistentie. De volledige formules staan
in de git-geschiedenis: de oorspronkelijke versie in commit `eeeee0e`, de
tussenstap die deze methode combineerde met de eerste officiële Oost-cijfers
in commit `d9d9426` (beide op `dashboard/src/lib/forecast.ts`).

**Waarom verwijderd.** Het model had geen demografische drivers — geen
geboorte-/sterfte-/migratiecijfers, geen woningbouwpijplijn — en trok simpelweg
de historische trend door. Voor sterk groeiende nieuwbouwgebieden (IJburg,
Zeeburgereiland) betekende dat een prognose die het model zelf al niet
betrouwbaar vond (vandaar de compressie naar een plafond in de oude code). En
omdat het overal een getal produceerde, ook waar de onderliggende reeks kort,
ruizig of onderdrukt was, gaf het een schijn van dekking die de kwaliteit van
de onderliggende data niet had. De opdrachtgever koos daarom voor "geen
prognose" als eerlijker antwoord dan "een naïeve prognose", waar geen officiële
bron bestaat.

**Waarom destijds niet cohort-component of Hamilton–Perry?** Cohort-component
vereist leeftijdsspecifieke geboorte-/sterfte-/migratiecijfers per buurt — die
ontbraken in de open CBS-data. Hamilton–Perry (cohort-change-ratio) vereist
leeftijdsklassen die op de projectiestap aansluiten; de CBS-klassen zijn
ongelijk van breedte (0–14, 15–24, 45–64, 65+, met een gat 25–44). Dit
argument staat los van de vervanging door officiële data — het verklaart
alleen waarom het oude team geen alternatief zelfbouwmodel koos.

## 4. Huidige methode: uitsluitend officiële prognose

**Eén regel samenvatting:** toon een prognosepunt alleen waar een officiële
bron (gemeente Amsterdam O&S of BBGA) er daadwerkelijk een publiceert; toon
overal elders expliciet dat er geen officiële prognose bestaat. Geen eigen
model, geen vangnet, geen band.

**Twee bronnen, elk voor wat ze uniek toevoegen:**

- **O&S-bevolkingsprognose 2026** (Excel per wijk + stadsdeel;
  `external-data/raw/amsterdam_ois_bevolkingsprognose_oost/`) → `a_00_14`
  (som 0–4/5–9/10–14), `a_15_24` (som 15–19/20–24), `a_45_64` (som
  45–49/…/60–64). Jaren 2026/2030/2035/2040/2050/2055. **Alleen stadsdeel Oost
  (`SD-M`) en zijn 15 wijken (`WK0363MA`–`WK0363MQ`)** — het bestand bevat geen
  andere geografie.
- **BBGA** (Basisbestand Gebieden Amsterdam, al gedownload voor de catalogus;
  `external-data/raw/amsterdam_bbga/`) → `a_inw` (variabele `BEV_PROG`) en
  `a_65_oo` (`BEV65PLUS_PROG`), jaarlijks 2027–2055, voor **heel Amsterdam**:
  de gemeente zelf (`gebiedcode15 = 'STAD'` → `GM0363`), elk van de 9
  stadsdelen, elk van de 25 GGW-gebieden, en elke wijk — via het
  `gebiedcode15`-schema opgelost met `data-prep/gebieden_amsterdam.json`
  (hetzelfde bestand dat `build_data.py` gebruikt), dus zonder losse
  mapping-tabel. BBGA's eigen leeftijdsklassen (0–17/18–64/65+/75+) sluiten
  niet aan op de Dynamo-doelgroepen; alleen de twee variabelen die wél
  1-op-1 matchen (totaal en 65+) worden gebruikt.
- `a_1p_hh` (alleenwonenden) en `a_hh` (huishoudens) hebben in **geen van
  beide** bronnen een prognosevariabele, dus overal en altijd geen officiële
  prognose. Geen enkele bron publiceert op **buurtniveau**.

**Geen onzekerheidsband.** Beide bronnen publiceren een puntschatting, geen
interval of scenario (hoog/laag) — gecontroleerd in de BBGA-metadata, er
bestaat geen `*_PROG`-variant met een marge. Een verzoek om O&S's eigen
interval is uitgezet; zolang dat er niet is, toont de tool alleen het punt.

**Geen fallback.** Waar geen van beide bronnen een waarde heeft voor een
gevraagd (gebied, doelgroep, jaar), toont `lib/forecast.ts` simpelweg geen
prognosepunt voor die combinatie — geen doorgetrokken trend, geen geschatte
tussenwaarde. `views/Vooruitblik.tsx` rendert in dat geval een expliciete lege
staat in plaats van een leeg of misleidend grafiekvlak.

**Verwerking:** `data-prep/official_forecast.py` (parser voor beide bronnen) →
`bundle["officialForecast"][regiocode][indicatorId][jaar]` in `build_data.py`
(alleen voor `GM0363`) → `dashboard/src/lib/forecast.ts` leest dit veld direct;
er is geen ander pad naar een prognosewaarde. Ontbreken de bronbestanden
lokaal, dan blijft `officialForecast` leeg voor heel Amsterdam (waarschuwing in
de build-log, geen harde fout) — Vooruitblik toont dan overal de lege staat.

**Horizon.** `HORIZONS` in `forecast.ts` bevat alle jaren waarvoor een van de
bronnen een prognose publiceert: 2026, 2030, 2035, 2040, 2050 en 2055. De
horizon-keuze in de bevroren parameterbalk is hier direct op gebaseerd.

**Bewust (nog) niet gedaan:** geen buurt- of gebiedsniveau-afleiding voor de
drie Oost-leeftijdsklassen (bijv. een proportionele verdeling van het
wijktotaal over buurten) — dat zou een eigen, zij het eenvoudiger, model zijn,
en de opdrachtgever koos expliciet voor "geen prognose" boven "een afgeleide
prognose" op elk niveau waar geen bron zelf publiceert.

## 5. Resterende aannames

1. **Ecologisch voorbehoud.** Alle cijfers zijn gebiedsgemiddelden, geen
   individuen. De prognose stuurt *waar* je capaciteit verschuift, niet *wie*
   precies wordt bereikt (gedeeld met het inzichtenteam).
2. **Codehergebruik/gebiedsherindeling.** Amsterdam wisselde in 2023 van
   wijk-/buurtcodes; historische koppeling is elders in de monitor geverifieerd
   (zie AANNAMES). Een dekkingsbreuk in de wijk-/buurtreeks van een gebied
   wordt in de view gemeld — die reeks toont dan een sprong die niets met een
   echte verandering te maken heeft.
3. **Onderdrukking ≠ nul.** Door het CBS afgeschermde/ontbrekende cellen worden
   als missing behandeld, niet als 0.
4. **Puntschatting, geen marge.** De officiële cijfers worden getoond zoals
   gepubliceerd; er is geen eigen onzekerheidsschatting toegevoegd. Lees ze als
   het officiële gemeentelijke cijfer op peildatum 2026, niet als een bandbreedte.

## 6. Waar te vinden in de code

- `dashboard/src/lib/forecast.ts` — leest de officiële prognose (geen eigen model meer).
- `dashboard/src/components/ForecastChart.tsx` — chart (waarneming vol, officiële prognose gestippeld, geen band).
- `dashboard/src/views/Vooruitblik.tsx` — het tabblad, inclusief expliciete lege staten waar geen officiële bron bestaat.
- `data-prep/official_forecast.py` — parser voor de O&S-Excel en BBGA (§4).
- In de tool: **Verantwoording → Vooruitblik (prognose)** vat methode en voorbehoud samen.
