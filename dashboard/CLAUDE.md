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
  the deploy workflow ships. **Committed to git** (~7.6 MB, already-aggregated CBS output under
  the same rounding/suppression as the delivery it's built from) — unlike `data/output_data/`,
  which stays local-only. Re-run `data-prep/01_build_app_data.R` and commit the result whenever
  `data/output_data/` gets a new delivery; nothing regenerates it automatically.
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

## Structure

- `app.R` — dashboard UI and server logic; sources the helpers below.
- `app_RA_prototype.R.bak` — the earlier prototype written to run *inside* the CBS RA against
  in-memory objects (`dt_huishoudens_agg_OT1`, `st_read("wc.shp")`). Does not run locally;
  kept as a reference for intended interaction only.
- `data-prep/` — one-off scripts that turn an RA delivery into `data/app_data/`. Re-run by
  hand after each new delivery; not part of the app's runtime.
- `utils/` — reusable functions shared across the app, incl. `auth.R` (shinymanager) and the
  think-cell export stack. `venn_diagram.R` is Dynamo-specific (a hand-built 3-circle SVG venn
  for `O_MPG_combination`/`O_OUD_combination`), not shared with sibling dashboards. One
  `venn_svg()` renders both the on-screen figure and the "Download figuur (svg)" file
  (`standalone = TRUE` adds the XML declaration, white background and pixel size); the colour
  scales the UI offers live in `VENN_PALETTES` in that same file. The **"none" region is
  deliberately off the colour scale** (`VENN_NONE_FILL`) — it is 60–90% of a selection, so on
  the shared scale it flattened all seven circle regions into one tint. Its value is still in
  the label and the tooltip.
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
from `app.R`.

Current failure baseline on this machine: **FAIL 36** — identical to the same suite in
`shiny_dashboard_template`, so it is not something this repo introduced. Every failure comes
from `zip` not being on PATH, which only affects the slide/favorites ZIP paths. The
template's `.claude/launch.json` works around it by prepending a `zip-shim` directory to
PATH. Treat 36 as the pass mark until `zip` is available; a 37th failure is a real
regression. Those 36 really are only the missing `zip`: on a Linux box that has `zip` (but
no `readxl`) the same suite ran **FAIL 0 | PASS 483 | SKIP 9** — that count predates
`test-venn_diagram.R`, which adds 59 passes plus one that needs `xml2` and skips without it.
