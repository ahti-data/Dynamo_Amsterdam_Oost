# Dynamo dashboard (Shiny) — project notes for Claude

Internal Shiny dashboard for the Dynamo Amsterdam Oost project, built on top of
`shiny_dashboard_template` (checked out as a sibling under the same `Git Repos` parent).

Not to be confused with `dashboard_client/` in this same repo — that is a separate React SPA
with its own `CLAUDE.md` at the repo root. This folder is the R/Shiny dashboard.

## Data

Source data is CBS microdata output from the **CBS Remote Access environment**. Only
aggregated, non-identifiable output ever leaves that environment and lands here — never
person-level records.

- `data/output_data/output_1a/` — raw RA deliveries, **never committed** (330 MB CSV + 19 MB
  xlsx). Treat as read-only inputs.
- `data/geo/` — Amsterdam geometry (buurten / wijken / gebieden), copied from
  `dashboard_client/data-prep/geo/`.
- `data/app_data/` — the prep step's parquet + geo output; this is what the app reads, and what
  the deploy workflow ships. **Committed to git** (~9.9 MB, already-aggregated CBS output under
  the same rounding/suppression as the delivery it's built from) — unlike `data/output_data/`,
  which stays local-only. Re-run `data-prep/01_build_app_data.R` and commit the result whenever
  `data/output_data/` gets a new delivery; nothing regenerates it automatically. Change only
  the derivation in `data-prep/derive_support_splits.R` and `02_add_derived_splits.R` refreshes
  the committed parquet in seconds, without needing the raw delivery.
- `data/metadata/brand_colors.R` — ahti branding palette, shared with the template.
- `data/metadata/variable_labels.R` — Dutch labels for every `R_`/`O_`-variable, taken from
  `Outcomes.xlsx` (see PLAN.md §3). Update this file from a new `Outcomes.xlsx`, never guess a
  label from the column name.

CBS output rules still apply to anything rendered: cells below 10 are suppressed and values
are rounded to 10 in the delivery. **Render a suppressed region as explicitly "onvoldoende
waarnemingen", never as 0** — the distinction matters and collapsing it misreads the data.
`variable_value` is the exception to the rounding rule: it is a category label (`0`, `1`, `2`,
`3plus`), not a count.

## Structural facts about the output tables

These are verified against the actual delivery, not assumed from the output form — check
`PLAN.md` §2 before changing any aggregation logic.

- **Split variables are marginal: never two at once.** Every row is either a total row (all
  split columns `all`) or a single-variable marginal. This is why the prep step can reshape
  the wide split columns into one `split_var`/`split_level` pair, and why the UI offers one
  "split by" at a time.
- `n_totaal_population_in_region` is constant per region × year.
- Category values sum to `n_totaal` only for `metric_name = n_households`. The `n_kinderen_*`
  metrics count children against a household denominator — don't divide them by `n_totaal`.
- Region boundaries are back-assigned to one vintage across all years (Weesp appears in
  2018–2021), so a single geojson vintage is correct for the whole 2018–2024 series.
- `OT_OUD` has **three** split variables, not four — the output form lists a `langwonende_hh`
  column that is not in the file.
- **Not every risk factor runs to 2024.** `R_MPG1_armoede_hh` stops after 2023 and
  `R_MPG9_wanbet_zv_hh` after 2022 — those source registers simply aren't in the delivery's
  last years (Amsterdam-wide counts of 5.400 and 3.100 in their final year, far above any
  suppression threshold). An empty column for those in a recent year is *not* "onvoldoende
  waarnemingen", and the risk-factor table under the venn says so explicitly. Check this per
  factor before reading a gap as suppression.
- The 8 `O_MPG_combination`/`O_OUD_combination` levels **partition the population** — their sum
  matches the total row up to rounding. That is what makes the derived
  `ondersteuningssignaal` / `aantal_ondersteuningsvormen` splits and the
  `O_*_ondersteuning` / `O_*_aantal_vormen` indicators valid (PLAN.md §7). Suppression is a
  **missing row**, not an `NA` — the lowest `metric_value` anywhere in the delivery is 10 — so
  any sum over combination levels silently counts a suppressed cell as zero. Every derived cell
  is therefore written only when all of its building blocks are published, and the "wel" level
  comes from *total − none* rather than summing the other seven. Don't relax that without
  documenting the resulting error margin.
- **A risk score can have fewer categories in one region than nationally, with nothing
  suppressed** — in Geuzenveld 2024 `R_MPG1_armoede_hh` has only value `0`, counting the whole
  wijk. Such a source is the *best* one available (no cross-tabulation, so no suppression in
  its level rows). Judging completeness against the national category count throws exactly
  those away; judge it against the source's own total rows instead, with a one-rounding-step
  tolerance (`SUPPORT_ROUND_TOL`) because everything is rounded to tens and sources therefore
  land a ten apart. Getting this wrong left `*_aantal_vormen` all but empty below gebied level
  (PLAN.md §7).

## Structure

- `app.R` — dashboard UI and server logic; sources the helpers below.
- `app_RA_prototype.R.bak` — the earlier prototype written to run *inside* the CBS RA against
  in-memory objects (`dt_huishoudens_agg_OT1`, `st_read("wc.shp")`). Does not run locally;
  kept as a reference for intended interaction only.
- `data-prep/` — one-off scripts that turn an RA delivery into `data/app_data/`. Re-run by
  hand after each new delivery; not part of the app's runtime. `derive_support_splits.R` is
  the shared derivation of the support splits/indicators (PLAN.md §7), called by both `01_`
  and `02_` so the two routes cannot drift apart; it is the one `data-prep/` file the test
  suite covers.
- `utils/map_download.R` — Dynamo-specific, like `venn_diagram.R`. Leaflet draws in the
  browser and can't be written to a file server-side (that needs a headless browser, which
  the server doesn't have), so this redraws the same layer with ggplot2 + geom_sf for the
  "Download kaart (png)" button. The class breaks come from the app (`kaart_bins()`), not from
  `colorBin()`, so the figure and the screen provably share one classification — that is why
  the app computes them itself. `choropleth_klassen()` holds the part that can go wrong
  (breaks, labels, colours) and is tested without sf or a graphics device.
- `utils/` — reusable functions shared across the app, incl. `auth.R` (shinymanager) and the
  think-cell export stack. `venn_diagram.R` is Dynamo-specific (a hand-built 3-circle SVG venn
  for `O_MPG_combination`/`O_OUD_combination`), not shared with sibling dashboards. One
  `venn_svg()` renders both the on-screen figure and the "Download figuur (svg)" file
  (`standalone = TRUE` adds the XML declaration, white background and pixel size); the colour
  scales the UI offers live in `VENN_PALETTES` in that same file. The **"none" region is
  deliberately off the colour scale** (`VENN_NONE_FILL`) — it is 60–90% of a selection, so on
  the shared scale it flattened all seven circle regions into one tint. Its value is still in
  the label and the tooltip. The same file also renders **the venn as a table**
  (`venn_matrix_html()`): the eight regions × the risk score's categories, which is the one
  view the figure cannot give (it stands on a single chosen value). Figure and table share
  `venn_levels()` — one key vector, so a combination level can never land in a different cell
  in the two. The table's styling lives with the rest of the app's CSS in `app.R`, unlike
  `venn_svg()`, which stays self-contained because it also ships as a standalone `.svg`.
- `templates/` — built-in think-cell `.pptx` slide templates for the "Download slide" export.
  The line chart on **Per regio** is the one chart wired to the export layer
  (`chart_data_downloads_ui`/`_server`, id `r_downloads`, `chart_type = "line"`); the
  choropleth and the venn have no think-cell equivalent and keep plain download buttons
  (the venn: its own `.svg` of the figure plus an xlsx of its slice, which has a different
  year and split than the line chart's export). Adding a chart means repeating that ui/server
  pair — see
  PLAN.md §6 and the `thinkcell-export` skill, never reimplementing export logic in `app.R`.
- `state/` — runtime state (favorites, export history, uploaded templates); never committed,
  never synced by the deploy workflow, so it survives a redeploy.
- `tests/testthat/` — testthat tests.
- `deploy.env` — `APP_FOLDER` sets the project name under `/apps/` (`dynamo_internal` — `dynamo`
  itself is already taken by `dashboard_client`, the client-facing dashboard in this same repo).

## Deployment

The GitHub Actions workflow is **not** under `dashboard/.github/workflows/` — GitHub only reads
`.github/workflows/` at the repo root, so a copy there (as the template ships it) never actually
runs. The real one is [.github/workflows/deploy-dynamo-internal.yml](../.github/workflows/deploy-dynamo-internal.yml)
at the repo root, modelled on `pharm` and `RVS_laatste_1000_dagen`'s own root-level workflows
(both Shiny dashboards with the same `dashboard/` subfolder layout as this repo). It triggers on
push to `main` (path-filtered to `dashboard/**`) and on manual dispatch, reads `APP_FOLDER` from
`dashboard/deploy.env`, and SFTPs `app.R` + `data/` + `utils/` + `templates/` to
`/apps/dynamo_internal/` on healthinsights.ahti.nl — `state/` is deliberately excluded, same as
every other dashboard built from this template. See the `healthinsights-server-admin` skill for
how the server itself treats a newly-uploaded `/apps/` folder (protected by default, no config
change needed).

## Display choices that are not in the data

- **Westpoort is excluded everywhere** (`UITGESLOTEN_STADSDEEL` in `app.R`) — harbour and
  industrial estate, two wijken, almost no households. On the map it colours in like any other
  wijk and its tiny counts skew the scale. The parquet keeps it; only the app hides it.
- The map has no gemeente level (a choropleth of one polygon), but **"Heel Amsterdam" is a
  region on the Per regio tab** and is its default — that is the comparison baseline.
- The Kaart tab's "Toon" control limits the map to one stadsdeel and zooms to it, so a map of
  Oost alone can be lifted out. It filters the geometry, not the data.

## Conventions

- Add reusable logic to `utils/`, not inline in `app.R`.
- The deploy workflow ships only `app.R`, `data/`, `utils/` and `templates/`. Keep runtime
  dependencies inside those directories.
- `utils/` is shared with `shiny_dashboard_template` and its other siblings (e.g.
  `RVS_laatste_1000_dagen`, `pharm`). A fix made to a `utils/` file here is almost always
  relevant there too — port it back and run that repo's test suite.
- New think-cell chart types go in `utils/format_thinkcell_download.R` with tests before
  being exposed in the UI (`utils/chart_downloads.R` shows the wiring pattern).
- Pass `source_output`/`source_sheet` when wiring `chart_data_downloads_server()` so exports
  can be traced back to the originating RA delivery, not just the dashboard tab.
- Set `dl_option_prefixes` on `tc_register_app_context()` per chart, so each export's
  provenance log lists only that chart's own inputs.
- Every chart needs a real title, computed once in a reactive shared by the plot and by
  `chart_data_downloads_server(figure_title = ...)`.

## Dependencies

Verified present on this machine (R 4.5.2): shiny, leaflet, sf, data.table, ggplot2, dplyr,
plotly, arrow, readxl, jsonlite, bslib, DT, shinyWidgets, writexl, filelock, shinymanager,
testthat.

`format_tc_data()` also reaches for tidyr, tibble and rlang, and it takes `%>%` from the
app's own `library(dplyr)` rather than importing it — so those three are runtime
dependencies of `app.R` now that the export layer is wired up, not just of the test suite.

## Running

```r
shiny::runApp("app.R")
```

## Tests

```r
testthat::test_dir("tests")
```

Run the suite after changing anything in `utils/`.

`tests/testthat.R` sources `data/metadata/brand_colors.R` and `utils/venn_diagram.R` and loads
`leaflet` — `venn_svg()` needs `ahti_branding` and `colorNumeric()`, which the app itself gets
from `app.R`. It also sources `data-prep/derive_support_splits.R` and loads `data.table`: the
derivation runs in the prep step rather than in `utils/`, but the CBS rule it enforces (a
suppressed cell is never summed as zero) is worth a test.

Current failure baseline on this machine: **FAIL 36** — identical to the same suite in
`shiny_dashboard_template`, so it is not something this repo introduced. Every failure comes
from `zip` not being on PATH, which only affects the slide/favorites ZIP paths. The
template's `.claude/launch.json` works around it by prepending a `zip-shim` directory to
PATH. Treat 36 as the pass mark until `zip` is available; a 37th failure is a real
regression. Those 36 really are only the missing `zip`: on a Linux box that has `zip` (but
no `readxl`) the same suite ran **FAIL 0 | PASS 483 | SKIP 9** — that count predates
`test-venn_diagram.R`, which adds 59 passes plus one that needs `xml2` and skips without it.
