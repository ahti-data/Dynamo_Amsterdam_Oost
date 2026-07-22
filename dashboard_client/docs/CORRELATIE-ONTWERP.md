# Ontwerp — analysetabblad "Samenhang" (correlatie gebiedskenmerken × uitkomsten)

Status: ontwerp (niet geïmplementeerd). Doel: een nieuw tabblad in de
Dynamo-monitor dat de **samenhang tussen socio-demografische kenmerken van
gebieden (X)** en **zorg-/welzijns-/gezondheidsuitkomsten (Y)** zichtbaar maakt —
zowel per meetjaar als over de tijd. De analyse is **cross-sectioneel over
gebieden** binnen de gekozen scope/niveau (bijv. 15 wijken van Oost, 76 buurten,
of 110 Amsterdamse wijken).

Kernboodschap die de hele view moet uitstralen: **dit is een verkennend
signaleringsinstrument, geen causaal bewijs.** Samenhang tussen
gebiedsgemiddelden zegt niets over individuen (ecologische correlatie).

---

## 1. Methode

### 1.1 Coëfficiënt: Spearman ρ als standaard, Pearson r optioneel

**Standaard = Spearman rangcorrelatie (ρ).** Motivatie:

- **Percentages/aandelen, begrensd en scheef.** Zowel X (bijv. `p_hh_li`,
  `p_neu_al`, `p_65_oo`) als de RIVM-Y (allemaal percentages) zijn begrensd op
  [0,100] en vaak scheef verdeeld met lange staarten. Pearson veronderstelt
  bivariate normaliteit en lineariteit; die aanname houdt hier zelden.
- **Kleine N + uitschieters.** Bij Oost = 15 wijken domineert één afwijkend
  gebied (nieuwbouw als IJburg, studentenwijk, haven) de Pearson-r sterk.
  Spearman werkt op rangen en is robuust tegen zulke uitschieters.
- **Monotoon maar niet-lineair.** Veel plausibele verbanden (leeftijd ↔
  eenzaamheid, dichtheid ↔ geluidshinder) zijn monotoon maar krom. Spearman
  vangt die; Pearson onderschat ze.

**Pearson r als toggle**, voor wie een lineaire effectgrootte/trendlijn wil.
Toon altijd expliciet wélke coëfficiënt getoond wordt (label "Spearman ρ" /
"Pearson r"), nooit kaal "r". Als beide sterk verschillen (|ρ − r| groot) is dat
zelf een signaal van niet-lineariteit of uitschieters → toon dat als hint in de
drilldown.

Geen automatische richtingsnormalisatie van het teken: `meer groen` en `meer
eenzaamheid` betekenen tegengesteld. De coëfficiënt wordt "zoals gemeten"
berekend; de as-labels en een optionele "uitlijnen op behoefte-richting"-toggle
(gebruikt `Indicator.direction`) maken de leesrichting expliciet.

### 1.2 Minimum aantal gebieden

Pairwise per X-Y-paar geldt n = aantal gebieden met **beide** waarden aanwezig.

| n (complete paren) | Gedrag |
|---|---|
| < 8 | Geen coëfficiënt. Alleen scatter tonen + waarschuwing "te weinig gebieden". Cel in matrix grijs/leeg. |
| 8–11 | Coëfficiënt tonen, maar gemarkeerd als **indicatief / zeer onzeker** (ontzadigd, label). |
| ≥ 12 | Normaal tonen. |

Oost = 15 wijken valt in "normaal", maar zit dicht bij de ondergrens: het
95%-betrouwbaarheidsinterval van ρ is dan breed (bijv. ρ = 0,50 bij n = 15 →
BI ≈ [0,00; 0,80]). De UI moedigt aan om **buurtniveau (76 buurten)** of een
**ruimere scope (110 Amsterdamse wijken)** te kiezen voor stabielere schattingen,
met de kanttekening dat wijk en buurt niet dezelfde ρ opleveren (MAUP, zie §5).

### 1.3 Ontbrekende en onderdrukte waarden

- **Pairwise complete deletion**: per paar alleen gebieden met beide waarden
  niet-null. n verschilt dus per cel en wordt **altijd** getoond (in cel-hover en
  tabel).
- **Onderdrukt/geheim = null**, wordt uitgesloten — **nooit als 0 behandeld**
  (kernregel uit de datacatalogus: leeg ≠ nul).
- **Selectiebias signaleren.** Onderdrukking is niet willekeurig: inkomen is op
  buurtniveau vaak onderdrukt in kleine of afwijkende buurten. De gebieden mét
  data zijn dan geen aselecte steekproef → waarschuwing als > 25% van de gebieden
  in een paar wegvalt ("gebaseerd op n van N gebieden; ontbrekende gebieden
  kunnen systematisch afwijken").

### 1.4 Gemodelleerde Y-schattingen (RIVM 50150NED)

De RIVM-uitkomsten zijn **kleine-gebiedsschattingen uit modellen**, geen directe
buurtenquêtes. Twee specifieke gevolgen voor correlatie, prominent te tonen:

1. **Ruimtelijke smoothing → autocorrelatie.** Small-area-estimation trekt
   naburige gebieden naar elkaar toe. Dat kan correlaties kunstmatig gladstrijken
   of versterken en maakt de effectieve N kleiner dan n.
2. **Mogelijke circulariteit.** Als het RIVM-model zelf SES-/inkomens-/
   opleidingscovariaten gebruikt om bijv. eenzaamheid te schatten, dan is de
   samenhang tussen inkomen (X) en die uitkomst (Y) deels **ingebakken in het
   model**, geen onafhankelijke ontdekking. Toon bij X-en die op SES lijken een
   expliciete "mogelijk circulair"-markering.

Elke Y draagt een badge **"gemodelleerde schatting"**; waar het 95%-interval
beschikbaar is (reproduceerbaar via de RIVM-API/metadata) wordt het in de
drilldown getoond.

### 1.5 Ecologische kanttekening (permanent, niet weg te klikken)

Een verband tussen **gebiedsgemiddelden** is geen verband op **individueel**
niveau (ecologische drogreden). Een wijk met veel lage inkomens én veel
eenzaamheid bewijst niet dat lage-inkomensbewoners eenzamer zijn. Deze zin staat
vast in de kop van de view en wordt herhaald in elke drilldown en export.

### 1.6 Onzekerheid tonen

- **Sterktedrempels op |coëfficiënt|** met woordlabel:
  < 0,1 verwaarloosbaar · 0,1–0,3 zwak · 0,3–0,5 matig · 0,5–0,7 sterk ·
  > 0,7 zeer sterk. Toon getal + woord.
- **Betrouwbaarheidsinterval** via Fisher-z-transformatie (95%), in de
  cel-drilldown en de "over tijd"-lijn. Bij kleine n zichtbaar breed.
- **Significantie terughoudend.** p (tweezijdig, t-benadering op de coëfficiënt)
  is beschikbaar, maar door ruimtelijke autocorrelatie is p te optimistisch en
  door **multiple testing** (bijv. 10 X × 12 Y = 120 toetsen) vind je bij toeval
  "significante" cellen. Daarom: nadruk op effectgrootte + n + BI, niet op een
  p-drempel. Cellen met **n < 12 worden altijd ontzadigd** (vaste ontwerpeis, los
  van elke toggle); de toggle "onzekere cellen dempen" (standaard **aan**) voegt
  daar de *optionele* significantie-demping p ≥ 0,05 aan toe, met uitleg dat p hier
  verkennend is. Optioneel Benjamini-Hochberg-correctie als nette variant, maar
  geframed als verkennend, niet confirmatoir.

### 1.7 Rekenkundig contract (client-side)

Alle berekeningen gebeuren in de browser (matrix K×M over N gebieden is klein,
bijv. 12×12×110). Nieuwe helper `lib/correlation.ts`:

```
spearman(xs, ys) / pearson(xs, ys) -> { r, n }
fisherCI(r, n, 0.95) -> { lo, hi }
pValue(r, n) -> number
strengthLabel(absR) -> 'verwaarloosbaar'|'zwak'|'matig'|'sterk'|'zeer sterk'
correlationMatrix(ds, list, xIds, yIds, year, method) -> Cell[][]  // Cell = {r,n,ci,p}
```

`list` komt uit de bestaande `areas(ds, level, scope)`; `year` wordt via
`nearestYear` naar het dichtstbijzijnde RIVM-meetjaar gesnapt.

---

## 2. X- en Y-variabelen

### 2.1 X (socio-demografisch, kolommen/rijen) — gebruik percentages, geen aantallen

**Kritiek: alleen relatieve indicatoren als X.** Absolute aantallen (`a_inw`,
`a_hh`, `a_65_oo`, …) correleren onderling vooral met gebiedsomvang → schijn­-
correlatie. Curated standaardset uit de reeds bestaande indicatoren:

- Bestaanszekerheid: `p_hh_li` (% lage inkomens), `p_ink_ar` (armoede),
  `g_ink_pi` (inkomen p.p.), `m_hh_ver` (mediaan vermogen), `p_arb_pp`
  (arbeidsparticipatie).
- Opleiding/diversiteit: `a_opl_bvm`→ liever een %-variant indien beschikbaar,
  `p_neu_al` (% buiten Europa).
- Leeftijd/huishouden: `p_65_oo`, `p_00_14`, `p_15_24`, `p_1p_hh` (% alleenwonend),
  `p_hh_m_k` (% hh. met kinderen).
- Wonen: `p_wcorpw` (% corporatiewoningen), `p_koopw`, `g_wozbag` (WOZ, neutraal).
- Nabijheid: `g_afs_hp` (afstand huisarts).

De gebruiker kan de X-set aanpassen; default is deze curated lijst, thematisch
gegroepeerd via `Theme.indicatorIds`. Absolute-aantal-indicatoren worden uit de
X-keuze gefilterd (of expliciet gewaarschuwd).

### 2.2 Y (RIVM 50150NED-uitkomsten, kolommen) — percentages, gemodelleerd

Toe te voegen als nieuwe indicatoren (unit `pct`, estimate_type gemodelleerd,
alleen meetjaren 2012/2016/2020/2022/2024 gevuld, rest null). Curated
standaardset, aansluitend op Dynamo-dienstverlening:

- Ervaren gezondheid: `GoedErvarenGezondheid`, `EenOfMeerLangdurigeAandoeningen`,
  `LangdurigBeperkt`.
- Mentaal: `HoogRisicoAngststoornisOfDepressie`, `HeelVeelStressAfg4Weken`,
  `BrozeGezondheid` (kwetsbaarheid).
- Sociaal: `Eenzaam`, `SterkEenzaam`, `KrijgtSteunVanAnderen`, `Mantelzorger`,
  `Vrijwilligerswerk`.
- Bestaanszekerheid-beleving: `MoeiteMetRondkomen`.
- Leefstijl: `Overgewicht`, `RooktTabak`, `OvermatigDrinken`,
  `VoldoetAanDeBeweegrichtlijn`.

Overlappende jaren met de socio-demografie voor de "over tijd"-analyse:
**2016, 2020, 2022, 2024**.

---

## 3. Visualisaties

Alle vier bestaan naast elkaar in het tabblad en delen één `hoverCode`/
`selectedArea`, zoals Gentrificatie kaart↔scatter koppelt.

### 3.1 Correlatiematrix / heatmap (per jaar, per niveau) — kernvisual

- **Assen**: rijen = X (socio-demografisch, thematisch gegroepeerd),
  kolommen = Y (RIVM-uitkomsten). Scrollt horizontaal in een
  `overflow-x:auto`-container.
- **Kleur = coëfficiënt**, divergerend palet met neutraal midden, vaste domein
  `[-1, +1]` (geen robuuste cap nodig; ρ/r is al genormaliseerd). Hergebruik de
  bestaande `--div-neg-3…--div-pos-3` + `--div-mid`. Blauw = negatief, rood =
  positief. CVD-veilig zoals de rest van de tool.
- **Celtekst**: bij weinig cellen het getal in de cel; altijd n, coëfficiënt,
  sterktelabel en p in de **tooltip** (voldoet aan "altijd ook tabel/tooltip").
- **Onzeker/te klein**: n < 8 → lege/grijze cel; n = 8–11 → **altijd** gedempt
  patroon; (optioneel, via toggle) niet-significant → eveneens gedempt i.p.v.
  verzadigde kleur.
- **Interactie**: klik cel → opent de drilldown-scatter (§3.2) eronder; hover cel
  → highlight rij+kolomkop. Geen dubbele assen, één betekenis per kleur.
- Onder de matrix altijd een **DataTable** (X, Y, coëfficiënt, n, 95%-BI, p,
  sterkte) met CSV-export via de bestaande `toCsv`/`downloadCsv`.

### 3.2 Cel-drilldown: scatter over de gebieden (hergebruik ScatterPlot)

- X = gekozen socio-demografische indicator, Y = gekozen RIVM-uitkomst; één punt
  per gebied. `xRef`/`yRef` = mediaan van de gebieden → vier kwadranten met
  dynamische labels (hoog/laag X × hoog/laag Y, geformuleerd naar `direction`).
- **Trendlijn**: kleine uitbreiding van `ScatterPlot` met optionele
  `trendLine?: { slope; intercept }` (OLS, ter illustratie). Label:
  "lineaire hulplijn — gerapporteerde samenhang is Spearman ρ = …".
- **Kop** toont: coëfficiënt (ρ en r), n, 95%-BI, p, sterktelabel, en
  "gemodelleerde schatting"-badge + ecologische kanttekening.
- **Gebiedslabels**: bij weinig gebieden (wijk, n≈15) labels direct bij de punten;
  bij veel gebieden (buurten) op hover/selectie.
- **Kaartkoppeling**: naast de scatter een kleine `Choropleth` van de gekozen X
  (of Y), die op dezelfde `hoverCode` reageert; hover/klik synchroniseert punt ↔
  vlak, net als Gentrificatie.

### 3.3 Correlatie over tijd (hergebruik LineChart) + verandering-vs-verandering

- **ρ-per-jaar lijn**: voor het gekozen X-Y-paar een lijn van de coëfficiënt per
  RIVM-meetjaar (2016, 2020, 2022, 2024). Y-as van −1..+1 met referentielijn op 0.
  Elk punt toont n in de tooltip; jaren met n < 8 onderbroken/grijs. Laat zien of
  een verband stabiel, sterker wordend of verdwijnend is.
- **Verandering-vs-verandering scatter** (longitudinale robuustheidscheck):
  ΔX (2016→2024) op de horizontale, ΔY over dezelfde periode op de verticale as,
  één punt per gebied, `xRef=0`/`yRef=0`. Hergebruikt `ScatterPlot` +
  `deltaOverPeriod`. Als het cross-sectionele verband óók longitudinaal opgaat
  (gebieden waar X sneller veranderde zagen Y sneller veranderen), is dat een
  sterker — maar nog steeds ecologisch — signaal. Nadrukkelijk gelabeld als
  "robuustheidscheck: dubbel verschil, veel ruis, kleine N".

### 3.4 "Sterkste verbanden"-ranglijst (hergebruik BarChart)

- Horizontale staafgrafiek van de X-Y-paren met de grootste |coëfficiënt| in het
  gekozen jaar/niveau, gefilterd op n ≥ 8, kleur divergerend op het teken. Klik →
  drilldown. Paren die deels hetzelfde meten (inkomen↔armoede↔SES) worden gelabeld
  "meet deels dezelfde onderliggende factor" en tellen niet als onafhankelijk
  bewijs (zie §5).

---

## 4. Interactie en aansluiting op de contextbalk

- Nieuw item in `VIEWS` (App.tsx), bijv. **"Samenhang"**, tussen Gentrificatie en
  Tabel. Eigen view-lokale filterbar zoals Gentrificatie.
- **Sluit aan op de bestaande contextbalk** (gemeente / focus=scope / niveau /
  peiljaar):
  - `scope` + `level` bepalen de gebiedsset (de N) via `areas(ds, level, scope)`.
  - `year` (peiljaar) bepaalt de matrix, maar RIVM heeft alleen 2016/2020/2022/
    2024 → **snap naar dichtstbijzijnde RIVM-meetjaar** met de bestaande
    `nearestYear`, en toon dat expliciet ("RIVM-meetjaar 2024, dichtst bij gekozen
    peiljaar 2025").
- **View-lokale controls**: X-set en Y-set (multiselect met curated default),
  coëfficiënt-toggle (Spearman/Pearson), toggle "onzekere cellen dempen", en het
  actieve X-Y-paar voor drilldown/over-tijd.
- **Deelbaarheid**: extra hash-parameters (X-set, Y-set, coëfficiënt, actief paar)
  in de bestaande `readUrlState`/`writeUrlState`, zodat een analyse reproduceerbaar
  te delen is (conform review #13).
- **Te weinig gebieden**: als `areas(...)` < 8 gebieden oplevert (bijv. een klein
  focusgebied met 3 wijken), toon een empty-state à la Gentrificatie: "Te weinig
  gebieden voor een betrouwbare samenhang — kies een ruimere focus of een fijner
  niveau (buurten)." Individuele cellen met n < 8 blijven leeg met dezelfde uitleg.

---

## 5. Valkuilen (documenteren én in de UI tonen)

1. **Ecologische drogreden** — gebiedsverband ≠ individueel verband. Permanent in
   beeld.
2. **Schijncorrelatie / confounding** — een derde factor (bijv. leeftijdsopbouw)
   kan zowel X als Y drijven; correlatie ≠ oorzaak.
3. **Dubbeltelling van dezelfde onderliggende factor** — inkomen, opleiding,
   % lage inkomens, armoede en (later) SES-WOA meten grotendeels dezelfde latente
   SES-dimensie. Meerdere sterke verbanden met SES-achtige X-en zijn **niet**
   onafhankelijke bewijzen (expliciet in datacatalogus). Label zulke paren en
   waarschuw bij de ranglijst.
4. **Gemodelleerde Y-data** — ruimtelijke smoothing (autocorrelatie) en mogelijke
   circulariteit als het RIVM-model SES-covariaten gebruikte (§1.4).
5. **Kleine N** — brede BI, instabiele schatting, gevoelig voor uitschieters,
   en multiple-testing bij een volle matrix.
6. **Wijk vs buurt / MAUP** — schaal- en zoneringseffect: dezelfde data geeft op
   wijk- en buurtniveau verschillende coëfficiënten; grover aggregeren versterkt
   doorgaans het verband. Nooit wijk- en buurt-r als "hetzelfde" presenteren.
7. **Ruimtelijke autocorrelatie** — p-waarden te optimistisch, effectieve N lager
   dan n; daarom nadruk op effectgrootte en BI, niet op p.
8. **Absolute aantallen als X** — vermijden; correleren met bevolkingsomvang.
9. **Teken-/richtingverwarring** — `meer groen` en `meer eenzaamheid` betekenen
   tegengesteld; nooit automatisch de richting omdraaien zonder label.
10. **Jaar- en grens-mismatch** — peiljaar vs RIVM-meetjaar; indelings-/grensjaar
    van X (CBS) vs Y (RIVM indeling 2024). Toon een grens-/jaarwaarschuwing bij
    de over-tijd-analyse.

---

## 6. Aannames

- RIVM 50150NED wordt genormaliseerd naar het bestaande interne model
  (`values[code][indicator][yearIndex]`) met alleen de RIVM-meetjaren gevuld en de
  overige jaren null; koppeling op expliciete gebiedscode, niet op naam.
- De relatieve socio-demografische X-varianten (`p_*`, `g_ink_pi`, `m_hh_ver`)
  bestaan al in de bundel en zijn geschikt als X; absolute aantallen worden
  uitgesloten.
- Analyse is cross-sectioneel over gebieden binnen scope×niveau; N = uitkomst van
  `areas(ds, level, scope)`.
- Berekening client-side is ruim haalbaar (matrix ≈ 12×12 over ≤ ~110 gebieden).
- 95%-BI via Fisher-z; p via t-benadering op de coëfficiënt; beide expliciet als
  verkennend gelabeld vanwege ruimtelijke afhankelijkheid.
- Overlappende meetjaren voor "over tijd" zijn 2016, 2020, 2022, 2024.
- Bestaande componenten (Choropleth, ScatterPlot, LineChart, BarChart, DataTable,
  StatTile, Tooltip) worden hergebruikt; enige codewijziging is een optionele
  trendlijn-prop op ScatterPlot en een nieuwe Heatmap-component + `lib/correlation.ts`.
