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

Dat zet de levering om naar `data/app_data/` (parquet + geometrie). Daarna:

```r
shiny::runApp("app.R")
```

## Structuur

- `app.R` — het dashboard: één tab "Iteratie 1" met de subtabs **Kaart** en **Per regio**.
- `data-prep/` — eenmalige scripts die een RA-levering omzetten naar `data/app_data/`.
- `data/output_data/` — ruwe RA-leveringen (niet in git).
- `data/geo/` — Amsterdamse geometrie (buurten, wijken, gebieden).
- `utils/` — gedeelde helpers uit `shiny_dashboard_template`, inclusief de think-cell
  exportlaag (nog niet aangesloten, zie PLAN.md §6).
- `templates/` — think-cell `.pptx` sjablonen.

## Let op bij de cijfers

De output valt onder de CBS-uitvoerregels: aantallen onder de 10 zijn onderdrukt en waarden
zijn afgerond op 10. Een regio zonder cijfer is daarom **onvoldoende waarnemingen**, niet
nul — het dashboard toont dat ook zo. `variable_value` is de uitzondering op de afronding:
dat is een categorielabel (`0`, `1`, `2`, `3plus`), geen telling.
