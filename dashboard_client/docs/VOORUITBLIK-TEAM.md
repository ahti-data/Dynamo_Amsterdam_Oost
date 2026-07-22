# Vooruitblik — teamsamenstelling, methode en aannames

Dit document beschrijft het team dat het tabblad **Vooruitblik** (demografische
prognose van Dynamo-doelgroepen) heeft opgezet, de gekozen methode en de
aannames die daarbij expliciet zijn gemaakt.

## 1. Teamsamenstelling

De opdracht — *"stel een team samen van in ieder geval een sociaal-demograaf die
prognoses maakt van de ontwikkeling van de doelgroepen van Dynamo, leg contact
met het inzichtenteam, voorspel de omvang op zo laag mogelijk geografisch niveau,
visualiseer en trek conclusies"* — is uitgevoerd door een klein, rolgericht team.

| Rol | Verantwoordelijkheid | Bijdrage aan dit tabblad |
|-----|----------------------|--------------------------|
| **Sociaal-demograaf (lead)** | Prognosemethode kiezen die past bij de databeperkingen; doelgroepen afbakenen; methode verantwoorden en citeren | Leverde de methodische onderbouwing (§3): log-lineaire extrapolatie met shrinkage, demping en top-down raking; wees cohort-component en zuiver Hamilton–Perry af |
| **Specialist kleine-gebiedsstatistiek** | Ruis van kleine gebieden temmen; onderdrukking en codehergebruik afvangen; consistentie tussen niveaus borgen | Ontwierp de omvang-gewogen shrinkage naar de parent en de top-down raking (buurt → wijk → gebied → stadsdeel) |
| **Data-engineer** | Methode implementeren in de bestaande React/TS-monitor, reproduceerbaar en zonder pijplijnwijziging | Bouwde `lib/forecast.ts`, `components/ForecastChart.tsx` en `views/Vooruitblik.tsx`; berekening draait client-side op de bestaande databundel |
| **Inzichtenteam** (bestaand, zie tabblad *Inzichten*) | 25 multivariate buurtinzichten per Dynamo-activiteit (`public/data/insights.json`) | Geraadpleegd voor de doelgroepdefinities en de vertaling naar diensten; de prognose-doelgroepen en de conclusieteksten sluiten aan op hun activiteitindeling (kinderwerk, jongerenwerk, ouderenwerk, eenzaamheids-/buurtwerk, mantelzorg) |

> **Contact met het inzichtenteam.** De doelgroepen in de Vooruitblik zijn
> één-op-één gekoppeld aan de Dynamo-activiteiten die het inzichtenteam hanteert.
> De prognose beantwoordt de vervolgvraag op hun *waar-nu*-analyse: *hoe
> ontwikkelt de omvang van diezelfde groepen zich richting 2030–2035?* Beide
> tabbladen delen het ecologische voorbehoud (buurtgemiddelden, geen individuen).

## 2. Doelgroepen

Elke doelgroep is een absolute CBS-telling, gekoppeld aan de dienst die erop
stuurt:

| Doelgroep | CBS-indicator | Dynamo-dienst |
|-----------|---------------|---------------|
| Ouderen (65-plus) | `a_65_oo` | Ouderenwerk, seniorenactiviteiten, welzijn op recept |
| Kinderen (0–14) | `a_00_14` | Kinderwerk en jeugdwerk |
| Jongeren (15–24) | `a_15_24` | Jongerenwerk en talentontwikkeling |
| Alleenwonenden | `a_1p_hh` | Buurtwerk en eenzaamheidsbestrijding |
| Aankomende senioren (45–64) | `a_45_64` | Mantelzorg en voorbereiding op vergrijzing |
| Huishoudens | `a_hh` | Buurtwerk, Huizen van de Wijk, wonen |
| Totaal inwoners | `a_inw` | Draagvlak en schaal van alle voorzieningen |

Deze zeven hebben een volledige reeks 2016–2025 op stadsdeel-, gebied-, wijk- én
buurtniveau (409–517 Amsterdamse buurten, 86–110 wijken met historie), wat
trendextrapolatie mogelijk maakt. Herkomst (`a_neu_al`) en armoede zijn bewust
niet opgenomen: hun reeks is te kort (2023–2025) voor een verdedigbare prognose.

## 3. Methode

Kernaanbeveling van de sociaal-demograaf, in één zin: **log-lineaire
trendextrapolatie per doelgroep en gebied, geschat op 2016–2025, gecorrigeerd met
omvang-gewogen shrinkage naar het bovenliggende gebied, gedempte groeivoeten en
top-down raking voor consistentie — met Hamilton–Perry uitsluitend als
plausibiliteitscheck.**

Geïmplementeerd in `dashboard/src/lib/forecast.ts`:

1. **Trend.** Per gebied × doelgroep een log-lineaire regressie op de beschikbare
   jaren (max. laatste 10). Log-ruimte houdt aantallen non-negatief en dempt
   uitschieters. Uitkomst: een jaarlijkse groeivoet `r` en de residuruis `σ`.
2. **Shrinkage.** De gebruikte groeivoet is een mix van de eigen trend en die van
   het bovenliggende gebied: `r* = w·r_eigen + (1−w)·r_parent`, met
   `w = omvang / (omvang + K)` (K = mediane gebiedsomvang op dat niveau) verder
   verlaagd bij korte reeksen. Kleine/ruizige/korte buurten leunen zo op de
   robuustere wijk-/stadsdeeltrend.
3. **Demping + gladde compressie.** De groeivoet telt elke stap verder zwakker mee
   (factor 0,9). De begrenzing is een **knie met gladde verzadiging**, geen harde knip:
   tot ±6%/jaar (`GROWTH_CAP`) blijft de trend onaangetast; daarboven verzadigt de
   groeivoet via `tanh` naar een absoluut plafond van ±9%/jaar (`RATE_CEIL`). Zo houdt
   elke snelle groeier een eigen, onderscheiden prognose. *(Een eerdere harde knip op
   6% maakte álle nieuwbouwwijken exact gelijk — +47,9% — omdat de %-verandering alleen
   van de groeivoet afhangt.)*
4. **Top-down raking.** Sub-gebieden worden zo geschaald dat hun som gelijk is aan
   de onafhankelijk geprognosticeerde omvang van het focusgebied (het robuustere
   niveau fungeert als controle-totaal).
5. **Onzekerheidsband (≈±1σ), log-symmetrisch.** Uit `σ` (gekapt op 0,25),
   verbredend met √horizon en ruimer bij meer shrinkage. De band is `value·exp(±σ√h)`,
   zodat de ondergrens nooit negatief wordt. Gecommuniceerd als band, niet als
   puntschatting.

**Waarom niet cohort-component of zuiver Hamilton–Perry?** Cohort-component
vereist leeftijdsspecifieke geboorte-/sterfte-/migratiecijfers per buurt — die
ontbreken. Hamilton–Perry (cohort-change-ratio) vereist leeftijdsklassen die op de
projectiestap aansluiten; de CBS-klassen zijn ongelijk van breedte (0–14, 15–24,
45–64, 65+, met een gat 25–44) en schuiven niet netjes door. Beide dienen hooguit
als plausibiliteitscheck op stadsdeelniveau.

**Bronnen/richtlijnen:** Hamilton & Perry (1962); Smith, Tayman & Swanson,
*State and Local Population Projections*; Wilson & Rees, *Recent developments in
population projection methodology*; CBS/PBL Regionale bevolkings- en
huishoudensprognose; Primos (ABF Research) / VNG-toepassingen.

## 4. Aannames (expliciet gemaakt)

1. **Trendcontinuïteit.** De prognose veronderstelt dat de trend van 2016–2025
   doorzet. Er is **geen** geplande nieuwbouw, sloop of beleidswijziging
   ingebracht. Gevolg: sterk groeiende nieuwbouwgebieden (IJburg, Zeeburgereiland,
   Oostelijk Havengebied) groeien sneller dan het model betrouwbaar extrapoleert; hun
   groeivoet wordt glad gecomprimeerd naar het plafond en hun prognose is een **getemde
   ondergrens** — de UI markeert deze gebieden expliciet als zodanig. In werkelijkheid
   kunnen ze nog harder groeien of juist afvlakken.
2. **Ecologisch voorbehoud.** Alle cijfers zijn gebiedsgemiddelden, geen
   individuen. De prognose stuurt *waar* je capaciteit verschuift, niet *wie*
   precies wordt bereikt (gedeeld met het inzichtenteam).
3. **Leeftijdsklassen ongelijk; 25–44 als restpost.** De 25–44-groep bestaat niet
   als losse CBS-kolom en wordt afgeleid als `totaal − (0–14 + 15–24 + 45–64 +
   65+)`. Dat is een ruizige, afgeleide grootheid; alleen gebruikt in de
   opbouw-verschuiving, niet als zelfstandige prognose.
4. **Codehergebruik/gebiedsherindeling.** Amsterdam wisselde in 2023 van
   wijk-/buurtcodes; historische koppeling is elders in de monitor geverifieerd
   (zie AANNAMES). Buurten met historie pas vanaf 2023 (korte reeks) krijgen via de
   shrinkage bijna volledig de parent-trend toegewezen.
5. **Onderdrukking ≠ nul.** Door het CBS afgeschermde/ontbrekende cellen worden als
   missing behandeld, niet als 0; gebieden zonder bruikbare reeks worden
   overgeslagen (melding in de view).
6. **Horizon 2030 en 2035.** Verder dan ~10 jaar vooruit extrapoleren is met deze
   data niet verantwoord; de band verbreedt zichtbaar naar 2035.
7. **Afronding.** Aantallen worden indicatief getoond; buurtprognoses zijn klein en
   ruizig en moeten als orde-van-grootte worden gelezen, niet als exacte tellingen.

## 5. Waar te vinden in de code

- `dashboard/src/lib/forecast.ts` — prognose-engine (trend, shrinkage, demping, raking, band).
- `dashboard/src/components/ForecastChart.tsx` — fan chart (waarneming + prognose + band).
- `dashboard/src/views/Vooruitblik.tsx` — het tabblad (doelgroepkeuze, tegels, ranking, kaart, leeftijdsopbouw, conclusies).
- In de tool: **Verantwoording → Vooruitblik (prognose)** vat methode en voorbehoud samen.
