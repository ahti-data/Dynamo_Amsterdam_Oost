# Dynamo Amsterdam — Shiny dashboard

Intern dashboard op de CBS RA-output van het Dynamo-project: risicostapeling bij
huishoudens met kinderen en bij ouderen (65+) in Amsterdam, 2018–2024.

Zie [PLAN.md](PLAN.md) voor de opzet en de verantwoording van de cijfers, en
[CLAUDE.md](CLAUDE.md) voor de conventies in deze map.

## Draaien

Eenmalig, na elke nieuwe RA-levering in `data/output_data/`:

```r
Rscript data-prep/01_build_app_data.R
```

Dat zet de levering om naar `data/app_data/` (parquet + geometrie). Verandert alleen de
afleiding in `data-prep/derive_support_splits.R` en niet de levering, dan volstaat
`Rscript data-prep/02_add_derived_splits.R` — dat werkt de bestaande parquet in seconden bij,
zonder de ruwe levering. Daarna:

```r
shiny::runApp("app.R")
```

## Structuur

- `app.R` — het dashboard: de tab "Iteratie 1" met de subtabs **Kaart** en **Per regio**,
  plus de drie gedeelde tabbladen **Favorites**, **Export history** en **Manage templates**
  (Engels, net als de panelen zelf — die komen ongewijzigd uit `shiny_dashboard_template`).
- `data-prep/` — eenmalige scripts die een RA-levering omzetten naar `data/app_data/`,
  inclusief de afgeleide ondersteuningsvariabelen (zie hieronder).
- `data/output_data/output_1b/` — de ruwe RA-levering (niet in git). `output_1b` is de
  huidige; er wordt nergens meer uit `output_1a` gelezen.
- `data/geo/` — Amsterdamse geometrie (buurten, wijken, gebieden).
- `utils/` — gedeelde helpers uit `shiny_dashboard_template`, inclusief de think-cell
  exportlaag. Die is aangesloten op het lijndiagram op **Per regio** (ruwe xlsx,
  think-cell-xlsx, slide `.pptx`, favorieten, exportgeschiedenis); de Kaart houdt zijn
  losse xlsx-download. Zie PLAN.md §6.
- `templates/` — think-cell `.pptx` sjablonen.

## Ondersteuning: wel/geen en hoeveel vormen

Naast de indicatoren uit de levering kent het dashboard vier **afgeleide**
ondersteuningsvariabelen, berekend uit `O_MPG_combination`/`O_OUD_combination` (PLAN.md §7):

- als **splitsvariabele** — `wel/geen ondersteuningssignaal` en `aantal vormen ondersteuning`
  (0–3). Die kruisen met een risicoscore: *van de gezinnen met twee vormen ondersteuning heeft
  x% drie of meer risicofactoren.*
- als **indicator** — `Ondersteuningssignaal (wel/geen)` en `Aantal vormen ondersteuning
  (0-3)`. Daar is de noemer de hele populatie: *x% van de gezinnen gebruikt een vorm van
  ondersteuning* (Amsterdam 2024: 42,9%).

Een afgeleide *celwaarde* verschijnt alleen als alle onderliggende combinaties gepubliceerd
zijn — anders staat er "onvoldoende waarnemingen", nooit een te laag getal. De *omvang* van
elke groep komt sinds levering `output_1b` rechtstreeks uit de kolom `n_totaal_region_split` en
is dus exact; die hangt niet van de risicowaarde af, dus één gepubliceerde rij van een
combinatieniveau is genoeg. Dat is precies waar `Aantal vormen ondersteuning` op wijk- en
buurtniveau eerder op stukliep (zie PLAN.md §7 en §9).

De venn op **Per regio** heeft een eigen indicatorkeuze. Standaard staat die op **(alle)**:
dan kleurt hij naar de verdeling zelf — welk deel van de populatie in welk deelgebied zit —
zonder dat je een risicoscore hoeft te kiezen. Kies je er wel een, dan kleurt hij naar het
aandeel daarvan binnen elk deelgebied. Eronder staan twee tabellen: de acht deelgebieden ×
de categorieën van de gekozen score, en de acht deelgebieden × de losse risicofactoren
(R1…R9). Let op: `R1` (armoede) loopt tot 2023 en `R9` (betalingsachterstand zorgverzekering)
tot 2022 — een lege kolom is daar geen onderdrukking maar een bronregister dat niet doorloopt.

## Uitsplitsen naar meerdere variabelen

Een rij in `output_1b` kan naar meer dan één variabele tegelijk uitgesplitst zijn, dus "Splits
uit naar" (Kaart) en "Splits de lijn uit naar" (Per regio) zijn meerkeuze: leeg betekent niet
uitsplitsen, en meerdere tegelijk geeft de gekruiste cellen. De levering publiceert niet elke
denkbare kruising; kies je er een die er niet is, dan zegt het dashboard dat in plaats van een
lege grafiek te tonen. Zie PLAN.md §9.

## Gemiddelden

`average_score` is een gemiddelde, geen telling. Daar geldt de keuze bij "Weergave" niet — er
staat altijd het gemiddelde zelf — en optellen kan niet: kies je meerdere waarden of niveaus
tegelijk, dan valt de kaart leeg met de reden erbij, in plaats van dat er twee gemiddelden bij
elkaar worden opgeteld.

## Kaart

De kaart kan tot één stadsdeel begrensd worden ("Toon"), zodat er een kaart van alleen Oost
uit te lichten is, en is als **png** te downloaden naast de xlsx. Bij "Waarde van de indicator"
en "Toon welk niveau" kun je **meerdere keuzes tegelijk** maken; die worden opgeteld, noemer
inbegrepen. Is in een regio een van die groepen onderdrukt, dan telt hij op wat er wel is; dat
cijfer is een ondergrens en krijgt een gestippelde rand, met het aantal boven de kaart. Bij "Weergave" kies je tegen welke noemer een aandeel afgezet wordt: het **regiototaal** (alle
gezinnen in die buurt of wijk) of **binnen de groep** (de gekozen groep zelf). Dat scheelt
flink — dezelfde selectie is in Zuidoost 16,0% binnen de groep en 1,6% van het regiototaal —
dus de gekozen noemer staat in de titel en bij de legenda. De kleurschaal
loopt door in plaats van in klassen, en het bereik is zelf in te stellen — handig om twee
kaarten op dezelfde schaal naast elkaar te leggen.

Rechtsboven staat **"Wat is er nieuw"**: wat er sinds je vorige bezoek veranderd is, uit
`data/metadata/changelog.R`. Dat bestand hoort bij elke wijziging bijgewerkt te worden. **Westpoort valt overal
weg**: haven- en bedrijventerrein, nauwelijks huishoudens, en het trekt de kleurschaal scheef.
Op **Per regio** is "Heel Amsterdam" een van de regio's en de standaardkeuze.

## Let op bij de cijfers

De output valt onder de CBS-uitvoerregels: aantallen onder de 10 zijn onderdrukt en waarden
zijn afgerond op 10. Een regio zonder cijfer is daarom **onvoldoende waarnemingen**, niet
nul — het dashboard toont dat ook zo. `variable_value` is de uitzondering op de afronding:
dat is een categorielabel (`0`, `1`, `2`, `3plus`), geen telling.
