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
- `data/output_data/` — ruwe RA-leveringen (niet in git).
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

Een afgeleide cel verschijnt alleen als alle onderliggende combinaties gepubliceerd zijn —
anders staat er "onvoldoende waarnemingen", nooit een te laag getal. `Ondersteuningssignaal`
is daardoor op elk regioniveau gevuld (99% van de buurten en wijken). `Aantal vormen
ondersteuning` vraagt alle acht combinaties tegelijk en haalt dat op gemeente-, stadsdeel- en
gebiedsniveau (100/83/65%), op ongeveer een kwart van de wijken en nauwelijks op buurtniveau.
Dat is de vorm van de levering, niet de berekening: de combinaties staan er alleen gekruist
met een risicoscore. Een ongekruiste combinatietelling in de volgende RA-levering lost het op
— zie PLAN.md §7.

De venn op **Per regio** heeft een eigen indicatorkeuze. Standaard staat die op **(alle)**:
dan kleurt hij naar de verdeling zelf — welk deel van de populatie in welk deelgebied zit —
zonder dat je een risicoscore hoeft te kiezen. Kies je er wel een, dan kleurt hij naar het
aandeel daarvan binnen elk deelgebied. Eronder staan twee tabellen: de acht deelgebieden ×
de categorieën van de gekozen score, en de acht deelgebieden × de losse risicofactoren
(R1…R9). Let op: `R1` (armoede) loopt tot 2023 en `R9` (betalingsachterstand zorgverzekering)
tot 2022 — een lege kolom is daar geen onderdrukking maar een bronregister dat niet doorloopt.

## Kaart

De kaart kan tot één stadsdeel begrensd worden ("Toon"), zodat er een kaart van alleen Oost
uit te lichten is, en is als **png** te downloaden naast de xlsx. **Westpoort valt overal
weg**: haven- en bedrijventerrein, nauwelijks huishoudens, en het trekt de kleurschaal scheef.
Op **Per regio** is "Heel Amsterdam" een van de regio's en de standaardkeuze.

## Let op bij de cijfers

De output valt onder de CBS-uitvoerregels: aantallen onder de 10 zijn onderdrukt en waarden
zijn afgerond op 10. Een regio zonder cijfer is daarom **onvoldoende waarnemingen**, niet
nul — het dashboard toont dat ook zo. `variable_value` is de uitzondering op de afronding:
dat is een categorielabel (`0`, `1`, `2`, `3plus`), geen telling.
