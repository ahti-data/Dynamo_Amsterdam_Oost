# Dynamo dashboard (Shiny) — project notes for Claude

Internal Shiny dashboard for the Dynamo Amsterdam Oost project, built on top of
`shiny_dashboard_template` (checked out as a sibling under the same `Git Repos` parent).

Not to be confused with `dashboard_client/` in this same repo — that is a separate React SPA
with its own `CLAUDE.md` at the repo root. This folder is the R/Shiny dashboard.

## Data

Source data is CBS microdata output from the **CBS Remote Access environment**. Only
aggregated, non-identifiable output ever leaves that environment and lands here — never
person-level records.

- `data/output_data/output_1b/` — raw RA deliveries, **never committed** (hundreds of MB).
  Treat as read-only inputs. `output_1b` is the current one; `output_1a` is superseded and
  nothing reads it any more. Which delivery a built parquet came from is written next to it
  (`data/app_data/source_info.rds`) rather than hard-coded in `app.R`, so a new delivery only
  needs `DELIVERY_ID` in `data-prep/01_build_app_data.R` changed.
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
- `data/metadata/changelog.R` — what changed, **for the people who use the dashboard**. The
  "Wat is er nieuw" button in the header reads it. See the convention below: every push that
  changes anything a user can see adds an entry here.

CBS output rules still apply to anything rendered: cells below 10 are suppressed and values
are rounded to 10 in the delivery. **Render a suppressed region as explicitly "onvoldoende
waarnemingen", never as 0** — the distinction matters and collapsing it misreads the data.
`variable_value` is the exception to the rounding rule: it is a category label (`0`, `1`, `2`,
`3plus`), not a count.

## Structural facts about the output tables

These are verified against the actual delivery, not assumed from the output form — check
`PLAN.md` §2 before changing any aggregation logic.

The `output_1b` items were measured on the delivery itself (18-09-2026, `OT_HHKIND.csv`
10.733.781 rows × 14 columns, `OT_OUD.csv` 721.821 × 13). The raw files are gitignored and stay
on the analyst's machine, so re-measuring means running the prep step there. It checks these
assumptions rather than trusting them anyway — a missing column, a split column without an `all`
value, an `n_split` that disagrees with `n_totaal` on a total row by more than one rounding step,
an unnamed category that is not the known `3plus` case, or a separator inside a value all stop
the build with a message naming the problem. If one of those fires, the assumption is what is
wrong, not the data.

- **A row can be split by more than one variable at once** (since `output_1b`; `output_1a`
  never crossed two). `split_var` is therefore a *set* of names and `split_level` the matching
  set of values, encoded as one string by `utils/splits.R`: names in a fixed order joined with
  ` | `, values in that same order. A single split is the length-one case, so the long schema
  and every existing filter (`split_var == "O_MPG_combination"`) still mean exactly what they
  meant. **Build the key with `split_key()`, never by pasting**: it sorts with
  `method = "radix"`, and that is load-bearing — plain `sort()` follows the locale's collation,
  the prep step and the Shiny server need not share one, and a key built under the other
  collation silently matches no rows at all. Not every crossing is published, so a selection
  that has no rows is reported as such (`split_key_bestaat()`), never left as an empty chart.
- Which columns are split variables is read from the delivery's header, not listed in code:
  everything outside `DELIVERY_FIXED_COLS` is a split variable, and a candidate column with no
  `all` value anywhere stops the build (that is a new fixed column, not a split).
- `n_totaal_population_in_region` is constant per region × year.
- **`n_totaal_region_splitvar` (in the parquet: `n_split`) is the published size of each
  region × split cell**, new in `output_1b`. It is the exact denominator for metrics that count
  the population unit (`n_households`, `n_ouderen_with_var_value`) and it replaced a pile of
  back-calculation — see `utils/metrics.R` for which metric may be summed, divided, or neither.
  It does **not** apply to the `n_kinderen_*` metrics: those count children against a household
  denominator, so their denominator stays the sum over the `variable_value` categories.
- **`average_score` is a mean, not a count.** It cannot be summed and has no denominator, so
  `denominator` is `NA` for those rows, the "Weergave" choice does not apply, and the map
  refuses to aggregate it (it blanks out and says why) instead of adding averages together.
- Category values sum to `n_totaal` only for `metric_name = n_households`. The `n_kinderen_*`
  metrics count children against a household denominator — don't divide them by `n_totaal`.
- Region boundaries are back-assigned to one vintage across all years (Weesp appears in
  2018–2021), so a single geojson vintage is correct for the whole 2018–2024 series.
- `OT_OUD` has **three** split variables, not four — the output form lists a `langwonende_hh`
  column that is not in the file.
- **`output_1b` only goes below gebied level for Oost.** 63 buurten and 15 wijken, all in
  stadsdeel Oost; gebied, stadsdeel and gemeente still cover the whole city (`output_1a` had 451
  buurten and 109 wijken citywide). That is the delivery's scope, not suppression and not a bug
  in the derivation — a coverage count that drops against `output_1a` at those two levels is
  expected. It matters for display: an undelivered region and a suppressed one are both a grey
  shape, and that is exactly the distinction this project must not blur, so the app says which
  stadsdelen a level covers (`dekking_note()`, built from `DEKKING_STADSDELEN`, which is read
  from the data — a later delivery may be wider).
- **Not every indicator has every metric** (since `output_1b`). `average_score` exists only on
  `R_*_totaal`, and those carry nothing else. The "Metric" list therefore follows the selected
  indicator, like "Waarde van de indicator" does (`update_indicator_keuzes()`); a
  population-wide list opened the dashboard on an empty map, because `average_score` sorts
  before `n_households`.
- **A share can exceed 100% in the data.** Numerator and denominator now come from two
  independently rounded sources (the published cell, or reference − none, against the published
  group size), which could not happen when the denominator was the category sum from the same
  slice. It hits 4.945 of 6,4M derived rows (0,08%), always at the suppression floor — 20 out of
  a group of 10. `add_display()` caps the displayed share at 100%; the absolute count is left
  alone.
- **The delivery carries a `population` column of its own**, constant within each file. It is a
  fixed column, not a split — `reshape_delivery()` overwrites it with the label the app uses
  (`huishoudens_met_kinderen` → `huishoudens met kinderen`). Leave it out of
  `DELIVERY_FIXED_COLS` and the build stops, correctly, on "a column with no `all` value".
- **`output_1b` renamed the cumulative risk score.** `R_MPG_totaal`/`R_OUD_totaal` now carry
  only the mean (`average_score`, `variable_value = "nvt"`); the 0/1/2/3plus classes moved to
  `R_MPG_totaal_cat`/`R_OUD_totaal_cat`, and `R_MPG_all`/`R_OUD_all` is the whole population in
  one category. Those three are summaries, not risk factors: `RISICO_TOTAAL_*` in
  `variable_labels.R` keeps them out of the risk-factor table under the venn (`R_MPG_all` would
  be a column of 100%).
- **`R_MPG_totaal_cat`'s `3plus` class arrives unnamed in `OT_HHKIND`** — the rows and their
  counts are there, `variable_value` is empty. `OT_OUD` spells it out, and the RA pipeline that
  built the delivery knows only those four names, so the label got lost in transit, not the
  category. `herstel_lege_categorie()` puts it back, but only where the picture matches exactly
  (the other classes are 0/1/2 and `3plus` occurs nowhere); anything else stops the build rather
  than inventing a name. Worth asking RA to fix at source — then that function does nothing.
- **`n_totaal_region_splitvar` and `n_totaal_population_in_region` are rounded to tens
  independently**, so on a total row they can legitimately land a ten apart (240 of 109.320 rows
  in `output_1b`). The build's check tolerates one rounding step and only warns beyond it.
- **The derivation runs per (population, region level), not over the whole table.** Every group
  key in `derive_support_splits.R` carries `population` and `region_level`, so the result is
  identical — but `output_1b` is 11.4M rows against `output_1a`'s 2.7M, and in one pass
  data.table's grouping ran out of hash table on a 16 GB machine. `support_per_regioniveau()`
  is what makes the prep step runnable; a test pins chunked == unchunked.
- **Not every risk factor runs to 2024.** `R_MPG1_armoede_hh` stops after 2023 and
  `R_MPG9_wanbet_zv_hh` after 2022 — those source registers simply aren't in the delivery's
  last years (Amsterdam-wide counts of 5.400 and 3.100 in their final year, far above any
  suppression threshold). An empty column for those in a recent year is *not* "onvoldoende
  waarnemingen", and the risk-factor table under the venn says so explicitly. Check this per
  factor before reading a gap as suppression.
- The 8 `O_MPG_combination`/`O_OUD_combination` levels **partition the population** — their sum
  matches the total row up to rounding. That is what makes the derived
  `ondersteuningssignaal` / `aantal_ondersteuningsvormen` splits and the
  `O_*_ondersteuning` / `O_*_aantal_vormen` / `O_*_combinatie` indicators valid (PLAN.md §7, §9).
  Suppression is a **missing row**, not an `NA` — the lowest `metric_value` anywhere in the
  delivery is 10 — so any sum over combination levels silently counts a suppressed cell as zero.
  A derived *cell value* is therefore written only when all of its building blocks are
  published, and the "wel" level comes from *reference row − none* rather than summing the other
  seven. Don't relax that without documenting the resulting error margin.
- **Group sizes, unlike cell values, are now published.** `n_split` does not depend on the risk
  value, so one surviving row of a combination level gives its exact size — where the old route
  needed a complete series of risk categories. That is what lifts `*_aantal_vormen` below
  gebied level. The median-over-usable-sources reconstruction survives only for metrics that
  do not count the population unit (`support_indicator_reconstructed()`); that is also the only
  place `SUPPORT_ROUND_TOL` still matters.
- **A risk score can have fewer categories in one region than nationally, with nothing
  suppressed** — in Geuzenveld 2024 `R_MPG1_armoede_hh` has only value `0`, counting the whole
  wijk. Such a source is the *best* one available (no cross-tabulation, so no suppression in
  its level rows). Judging completeness against the national category count throws exactly
  those away; judge it against the source's own total rows instead, with a one-rounding-step
  tolerance because everything is rounded to tens and sources therefore land a ten apart.
  Getting this wrong left `*_aantal_vormen` all but empty below gebied level (PLAN.md §7).
- **Derived rows are flagged** with `afgeleid = TRUE`, because otherwise they cannot be told
  apart from rows the delivery publishes itself: the refresh in `02_add_derived_splits.R` would
  delete real rows, and a delivery that starts publishing `aantal_ondersteuningsvormen` would
  be double-counted. When the delivery publishes one of these splits itself, nothing is derived
  — the real figure wins.

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
- `utils/splits.R` — Dynamo-specific: the encoding of a composite `split_var`/`split_level`,
  shared by `app.R`, `data-prep/` and the tests, so the key the app builds is byte-for-byte the
  key the prep step wrote.
- `utils/metrics.R` — Dynamo-specific: what a metric counts, and therefore whether it may be
  summed (`metric_is_optelbaar()`) and what its denominator is (`metric_telt_populatie()`).
  A new counting metric needs adding to `METRIC_POPULATIE_EENHEID` only if it counts the
  population unit itself; a new average is recognised by its name.
- `utils/map.R` — Dynamo-specific, like `venn_diagram.R`: everything the map shares between
  the screen and the download.
  - `map_aggregate()` sums the selected combination levels and/or indicator values. **The
    denominator rule is the part to be careful with**: across `variable_value` the denominator
    is the *same* row value (it is by definition the sum over all categories in that slice),
    so adding it up would double-count and halve the percentage; across `split_level` each
    level has its *own* denominator and those do add up. Hence: sum over the *unique* split
    levels.
    An average (`average_score`) is the exception: it cannot be summed and cannot be weighted
    from this slice, so `optelbaar = FALSE` blanks the whole map as soon as more than one cell
    is requested — deliberately including the regions that happen to have only one published,
    because otherwise one region would show an average over two groups and its neighbour one
    over a single group, side by side on the same map.
    A region missing one of the requested cells **keeps its number** and is marked
    `compleet = FALSE`; the map dashes its border, names the count above the map, and the
    tooltip says how many of the requested parts were published ("1 of 3" means something very
    different from "5 of 6"). That is a deliberate exception to the all-or-nothing rule
    elsewhere here: for a hand-picked group a flagged lower bound beats a grey shape — under
    the strict rule a wijk map of "O_MPG1 + O_MPG2 + the combination" came out entirely empty
    (0 of 11 wijken qualified). It does **not** extend to the derived indicators in
    `data-prep/derive_support_splits.R`: there the sum *is* the denominator of a percentage, so
    half a partition would make that percentage too high. Here the denominator is summed along
    with the numerator, so a missing cell lowers both and shifts the ratio far less.
  - `map_noemer()` — which denominator a chosen "weergave" uses. Alongside `"abs"` there is
    `"gem"`, the average of an `average_score` metric: neither a share nor a count, so it gets
    decimals and no `%`, and `map_is_aandeel()`/`map_is_gemiddelde()` are what every formatter
    keys off. The map offers three shares:
    *van regiototaal* (everyone in that buurt/wijk/gebied/stadsdeel), *binnen groep* (the
    sum over the indicator's categories within the selection, the PLAN.md §6 convention and
    the only one the app had at first) and *binnen indicatorwaarde*. The gap is large enough
    that it must never be implicit — the same selection reads 16.0% within-group and 1.6% of
    the region total in Zuidoost — so the chosen one is named in the title, the legend and the
    export. The region total is
    **not** `n_totaal`: that counts households while the `n_kinderen_*` metrics count children,
    so it comes from the total rows' own denominator instead. Per regio and the venn still send
    the old `"rel"`, which keeps meaning within-group.
    *Binnen indicatorwaarde* (`"rel_indicator"`) is the **transpose of within-group**: the same
    indicator value with the split removed, i.e. the total row. Within-group reads "of the
    families with this support profile, x% has this risk score"; this one reads "of the
    families with this risk score, x% has this support profile" — 30 of the 60 households with
    3+ risk factors in a wijk = 50%. It is the one denominator that does not depend on the
    metric's denominator convention, because numerator and denominator are the same metric and
    the same indicator value and only the split differs. It comes from `metric_value` on the
    total row (not `denominator`, which would be the whole population), summed over the same
    selected `variable_value`s as the numerator. **If one of those values is suppressed on the
    total row the denominator is short and the share would come out too high**, so
    `met_regio_totaal()` sets it to `NA` and the region reads as "onvoldoende waarnemingen"
    rather than as a wrong percentage.
  - `map_domein()` / `map_klem()` — the colour range (data range, or the user's own) and
    clamping into it, so a region past the chosen maximum takes the end of the ramp instead of
    `colorNumeric()`'s NA colour, which would read as "onvoldoende waarnemingen".
  - `choropleth_ggplot()` redraws the layer with ggplot2 + geom_sf for the "Download kaart
    (png)" button, on the same `kaart_domein()` as the screen. The scale is **continuous**
    (`scale_fill_gradientn` + `scales::squish`), not binned — binning lost the difference
    between two regions in the same class, and the colourbar guide sidesteps the empty-key
    problem that the old discrete legend had.
- `utils/` — reusable functions shared across the app, incl. `auth.R` (shinymanager) and the
  think-cell export stack. `venn_diagram.R` is Dynamo-specific (a hand-built 3-circle SVG venn
  for `O_MPG_combination`/`O_OUD_combination`), not shared with sibling dashboards. One
  `venn_svg()` renders both the on-screen figure and the "Download figuur (svg)" file
  (`standalone = TRUE` adds the XML declaration, white background and pixel size); the colour
  scales the UI offers live in `VENN_PALETTES` in that same file. The **"none" region is
  deliberately off the colour scale** (`VENN_NONE_FILL`) — it is 60–90% of a selection, so on
  the shared scale it flattened all seven circle regions into one tint. Its value is still in
  the label and the tooltip. The same file also renders **the cross-tabs
  under the figure**. `kruistabel_html()` is the generic one — rows × an indicator's values,
  with an optional `n` column and an optional `aandeel` matrix that makes a cell read
  "300 (2,0%)" — and the three tables on Per regio are each a thin layer over it, so they
  cannot drift apart. Extend that function with an argument rather than adding a fourth table.
  `venn_matrix_html()` is the venn's layer: the eight regions × the risk score's categories,
  the one view the figure cannot give (it stands on a single chosen value). Figure and table
  share `venn_levels()` — one key vector, so a combination level can never land in a different
  cell in the two. The third layer is the **ondersteuningsvormen × risk score** cross-tab
  (`vormen_matrix()` in `app.R`): four rows that partition the population against the score's
  categories, each cell a count plus its share **of the whole region**, so the table sums to
  100% and every cell is comparable with every other. Its columns are the categories as
  delivered (0/1/2/3plus) and deliberately **not** merged into "1-2" the way a hand-drawn
  version of this table did: summing two categories goes wrong the moment one is suppressed.
  The tables' styling lives with the rest of the app's CSS in `app.R`, unlike
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
- **The map does have a gemeente level, and it is one polygon.** As a choropleth that says
  nothing — there is nothing to compare — but it is the quickest way to read the city-wide
  figure without switching tabs, which is what it is there for. "Heel Amsterdam" is also a
  region on the Per regio tab and is its default; that one is the comparison baseline.
  The gemeente outline is not in `geo.rds`: `app.R` unions the stadsdelen itself, because it
  is the outer edge of geometry that is already there and because it is only correct *after*
  Westpoort has been dropped, which is this app's display choice and not the prep step's.
- The Kaart tab's "Toon" control limits the map to one stadsdeel and zooms to it, so a map of
  Oost alone can be lifted out. It filters the geometry, not the data — and it is **skipped at
  gemeente level**, where the single polygon lies in no stadsdeel and the filter would blank
  the map instead of narrowing it. The PNG's subtitle follows the same exception.
  `dekking_note()` is likewise silent there: gemeente does not break down into stadsdelen, so
  without that guard it would claim nothing had been delivered.

## Conventions

- **Every push that changes something a user can see adds an entry to
  `data/metadata/changelog.R`** (newest first, ISO date, plain Dutch about what they will
  notice — not about functions or columns). The header button shows the top entry's date and
  marks it unseen in the reader's browser; leave the file behind and everyone concludes
  nothing happened. A pure refactor or a docs-only change needs no entry.
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

`tests/testthat.R` sources every `utils/` file the tests touch — including `chart_downloads.R`,
without which `test-chart_downloads.R` cannot find the module it tests. It also sources
`data/metadata/brand_colors.R` and `utils/venn_diagram.R` and loads `leaflet` — `venn_svg()` needs `ahti_branding` and `colorNumeric()`, which the app itself gets
from `app.R`. It also sources `data-prep/derive_support_splits.R` and loads `data.table`: the
derivation runs in the prep step rather than in `utils/`, but the CBS rule it enforces (a
suppressed cell is never summed as zero) is worth a test.

The suite is **green**: measured **PASS 837 | FAIL 0 | SKIP 5** on Windows (R 4.5.2) with a
`zip` shim on `R_ZIPCMD`; the five skips are the platform- and `zip`-gated ones. Treat any
failure as real.

Two environment traps, both of which produce failures that have nothing to do with the code:

- **`zip` must be on PATH**, or every slide/favorites ZIP path fails (that was the old "FAIL 36"
  baseline). The template's `.claude/launch.json` works around it with a `zip-shim` directory.
- **`filelock` is optional but noisy**: without it every favorites/templates write warns about
  running unlocked. Those warnings are environmental, not failures.
- **Run under a UTF-8 locale.** Under `C`, three `test-favorites.R` checks fail on the middot
  and ellipsis in their expected strings — a multibyte character is no longer one character as
  far as R is concerned. `LANG=C.UTF-8` is enough. This is the same trap `VENN_SUPPRESSED_MARK`
  in `utils/venn_diagram.R` works around by writing an XML entity instead of a literal en dash
  — that one matters in production too, because Shiny Server itself can run under `C`.
