# Review: `targets` usage in the Dynamo iter1 pipeline

Scope: `_targets.R`, `R/globals.R`, and `R/01`–`R/05` in this folder. This is
purely about how you're using the `targets`/`tarchetypes` machinery — not
about the substance of the GGZ/CBS variables themselves.

You're right that you're scratching the surface: the pipeline works and is
already more disciplined than a lot of first `targets` pipelines (see "What's
already working well" below), but it's using `targets` mostly as "a
`tar_target()` per data.table step" and not touching most of what makes
`targets` worth the switch from a plain sourced R script.

## What's already working well

- `tar_option_set(workspace_on_error = TRUE)` — good instinct, this is exactly
  the tool for debugging a failed target inside the RA environment
  (`tar_workspace(<target>)` to drop into its exact environment).
- `tar_source()` instead of manually sourcing every file.
- The disclosure-control step (`>= 10` filter, round to 10) is isolated in its
  own targets (`OT_HHKIND_output`, `OT_OUD_output`) rather than inlined
  everywhere — that's the right instinct for an output-check pipeline.
- `description = "..."` on some targets, which shows up in `tar_manifest()`/
  `tar_visnetwork()` — worth doing consistently (see below).

## 1. The biggest miss: no dynamic branching (`pattern = map(...)`)

Almost every "loop over years and rbind" pattern is done *inside* a single
target with `lapply()` + `rbindlist()`:

- `get_base_population()` (`01_load_and_filter.R:17`)
- `load_filter_clean_stapeling()` (`01_load_and_filter.R:85`)
- `load_filter_clean_huisarts()` (`01_load_and_filter.R:398`)
- `load_filter_clean_medicijntab()` (`01_load_and_filter.R:432`)
- `load_filter_clean_inhatab()` (`01_load_and_filter.R:308`)

This is precisely what `targets` branching exists for:

```r
tar_target(
  years, base_years
),
tar_target(
  dt_stapeling_yr,
  load_stapeling_one_year(years, dt_rins),  # pull the inner lapply body out
  pattern = map(years),
  description = "stapeling, one branch per jaar"
)
```

Why it matters in an RA context specifically:

- **Partial reruns.** Right now, if the 2024 `stapelingsmonitor` release gets
  corrected, the *entire* multi-year `rbindlist()` target is invalidated and
  every year gets reloaded from `H:`/`G:` again. With branching, only the 2024
  branch reruns.
- **Debuggability.** `workspace_on_error` gives you the whole target's
  workspace, but with 7 years crammed into one `lapply`, you still have to
  figure out *which* year failed. With branching, the failing branch is named
  and isolated (`tar_workspace()` on that one branch).
- **Parallelism.** Branches are the unit `targets` schedules across workers.
  Without them, loading 7 years of `stapelingsmonitor` is inherently
  sequential even if you configure a `crew` controller (see §4).

This is a genuinely bigger refactor than the others below — I'd treat it as a
"iter2" item rather than something to bolt on today, but it's the one with
the highest payoff for a pipeline this shape.

**Does branching conflict with the lagged variables?** No — and it's worth
being explicit about why, since it's a fair worry. Branching would only apply
to the *loading* step for a given source table (e.g. one branch per year of
raw `stapelingsmonitor`), and none of those loads in `01_load_and_filter.R`
actually depend on a previous year's *loaded data* — `get_base_population()`
computes `rin_set_sample` once (a plain non-branched target) and every year's
branch just receives that same value; nothing in the year-loop itself reads
year *n-1*'s output. The lag logic (`burgstaat_prev <- shift(burgstaat, ...)`
in `enrich_stapeling()`, `02_enrich_and_score.R:14`, and the "present 5 years
ago" lookup right after it) already runs *after* all years have been
`rbindlist()`-ed together, on the combined table, as a separate, ordinary
(non-branched) target. Branching the *load* and keeping the lag computation
on the *combined* result downstream are not in tension — you'd write:

```r
tar_target(years, base_years),
tar_target(
  dt_stapeling_yr,
  load_stapeling_one_year(years, dt_rins),  # single-year body, no cross-year logic
  pattern = map(years)
),
tar_target(
  dt_stapeling_filtered_clean,
  rbindlist(dt_stapeling_yr, fill = TRUE)   # ordinary target: receives ALL branches as one list
),
tar_target(
  dt_stapeling_enriched,
  enrich_stapeling(dt_stapeling_filtered_clean)   # lag vars computed here, same as today
)
```

The one thing to know: a *non-branched* target that depends on a *branched*
one (like `dt_stapeling_filtered_clean` above) automatically receives the
list of all branches, not just one — `targets` does the "gather" for you, you
just still call `rbindlist()`/`vctrs::vec_c()` yourself to combine it. If some
year genuinely *did* need last year's loaded/processed value (not the case
here, but for future reference), that's what `pattern = map(years)` combined
with an explicit rolling/lag join in the downstream target is for — you don't
lose access to other years' branches, they're just not automatically visible
*to each other* inside the branching step itself.

## 2. `tarchetypes` is loaded but unused

`tar_option_set(packages = c(..., "tarchetypes", ...))` — but no `tar_map()`,
`tar_group_by()`, `tar_rep()`, or `tar_file_read()` anywhere.

Worth being precise about what `tar_map()` actually is, since it's easy to
conflate with `pattern = map()` from §1 — they're unrelated mechanisms that
happen to share the word "map":

- `pattern = map(x)` (core `targets`) is **dynamic branching**: one target
  definition in `_targets.R`, and `targets` decides *at runtime* how many
  branches to create — one per element of `x` (which can even change between
  runs, e.g. `base_years` growing by one). This is what §1 is about.
- `tarchetypes::tar_map()` is **static target generation**: at *pipeline-build
  time* (i.e. when `_targets.R` itself is sourced), it takes a *target
  template* (ordinary `tar_target()` calls, written once) and a data frame of
  parameter values, and expands it into N *separate, independently named*
  targets — literally as if you'd copy-pasted the template N times and
  hand-edited each copy. There's no "runtime" aspect to it at all; it's a
  code-generation convenience.

Where this actually helps here: `aggregate_OT_HHKIND()` / `aggregate_OT_OUD()`
(`03_aggregate.R`) and their `prepare_output_table_*` counterparts
(`05_prepare_output_tables.R`) are two copy-pasted implementations of the same
shape (filter population → melt → aggregate by region level → mask & round).
That duplication is what `tar_map()` targets — but it only pays off once the
*R functions themselves* are unified into one parameterized function, since
`tar_map()` just generates target calls, it doesn't merge function bodies for
you. A worked, self-contained example against your two output tables:

```r
# in R/03_aggregate.R — ONE function replacing aggregate_OT_HHKIND + aggregate_OT_OUD
aggregate_output_table <- function(dt, population_filter, score_prefix, id_cols) {
  dt <- dt[eval(population_filter)]
  score_cols <- grep(paste0("^", score_prefix), names(dt), value = TRUE)
  # ... the melt/aggregate/mask body that's currently duplicated ...
}
```

```r
# in _targets.R
library(tarchetypes)

output_table_specs <- tibble::tribble(
  ~table_name, ~population_filter,        ~score_prefix, ~pop_label,
  "OT_HHKIND", quote(n_kinderen_hh > 0),   "R_MPG",       "huishoudens_met_kinderen",
  "OT_OUD",    quote(leeftijd >= 65),      "R_OUD",       "ouderen (65+)"
)

output_targets <- tar_map(
  values = output_table_specs,
  names = table_name,                     # branch/target-name suffix, e.g. dt_agg_OT_HHKIND
  tar_target(
    dt_agg,
    aggregate_output_table(dt_rins_with_vars, population_filter, score_prefix, pop_label)
  ),
  tar_target(
    output_ready,
    prepare_output_table(dt_agg)          # same masking/rounding function for both
  )
)

# then in the main pipeline list:
list(
  ... ,
  output_targets   # tar_map() returns a list of target lists — splice it in directly
)
```

`tar_map()` expands that into four real targets
(`dt_agg_OT_HHKIND`, `output_ready_OT_HHKIND`, `dt_agg_OT_OUD`,
`output_ready_OT_OUD`) — same DAG shape you have now, but adding a third
output table in iter2 becomes a one-row addition to `output_table_specs`
instead of a third copy-pasted pair of R functions. This is a real refactor of
`03_aggregate.R`/`05_prepare_output_tables.R`, not a five-minute change — I'd
sequence it after §1, not before.

The dozen `load_filter_clean_*` targets in `_targets.R` (lines 44–91) are
*not* a good `tar_map()` case on their own (the column lists and cleaning
logic differ too much per dataset to unify into one template function) —
but once §1's per-year branching exists for the ones that loop over years,
the two compose fine: `tar_map()` generates the per-dataset target, and that
generated target's own `command` uses `pattern = map(years)` internally.

## 3. External files read inside function bodies aren't tracked as targets

These reads happen **inside** target commands, not as their own
`tar_target(..., format = "file")`:

- `data/toeslagen_thresholds.csv` (`02_enrich_and_score.R:69`)
- `H:/data/crosswalks/INDELING_WIJK_AMS_032026.csv` (`02_enrich_and_score.R:290`)
- `data/quality_checks/qualitychecks_wijkenbuurten_2023.csv` and
  `data/quality_checks/externe_checks_OSams.xlsx` (`04_quality_checks.R:5,91`)

`targets` only knows a target is stale if something it *statically sees in
the command* changes (a global, an upstream target, or a `format = "file"`
target's path/hash). A `fread()`/`read_xlsx()` call buried inside a function
body is invisible to it — if you edit `toeslagen_thresholds.csv` next month,
`tar_outdated()` will happily tell you the pipeline is up to date, and you'll
ship stale numbers without realizing it.

Fix is mechanical:

```r
tar_target(path_thresholds, "data/toeslagen_thresholds.csv", format = "file"),
tar_target(dt_stapeling_enriched, enrich_stapeling(dt_stapeling_filtered_clean, path_thresholds))
# and inside enrich_stapeling(): dt_thresholds <- fread(path_thresholds)
```

Same pattern for the crosswalk and the two quality-check reference files.

## 4. Nothing configured for parallel execution

Everything runs through the default sequential backend. The modern way to
fix this is a `crew` controller
(`tar_option_set(controller = crew::crew_controller_local(workers = 4))`) —
**but if `crew` (or `mirai`, which it depends on) isn't installed in the RA
and you can't get it added, it's not usable, full stop.** `targets`' older
parallel backend, `tar_make_future()`, has the same problem: it needs the
`future` package (plus usually `future.callr`), which may equally not be on
the RA's approved list. Check what you actually have before planning around
either:

```r
rownames(installed.packages())[grepl("^(crew|mirai|future|callr|parallel)", rownames(installed.packages()))]
```

If neither `crew` nor `future` is available, `parallel` almost certainly is —
it ships with every base R installation, so it needs no RA approval at all.
It's not a `targets` *controller* (there's no `tar_option_set(controller = ...)`
equivalent for bare `parallel`), so you lose per-target scheduling/caching of
the parallel work — but you can still parallelize *inside* one target's
function body, which recovers most of the wall-clock win for the "load N
years/datasets independently" pattern in §1. On the RA's Windows VM, use a
PSOCK cluster (`makeCluster()` — fork-based `mclapply()` doesn't work on
Windows):

```r
load_stapeling_all_years <- function(base_years, dt_rins) {
  cl <- parallel::makeCluster(min(length(base_years), parallel::detectCores() - 1))
  on.exit(parallel::stopCluster(cl))
  parallel::clusterExport(cl, c("dt_rins", "all_cols_to_load_stapeling"), envir = environment())
  parallel::clusterEvalQ(cl, { library(data.table); library(glue) })

  dt_list <- parallel::parLapply(cl, base_years, function(yr) {
    load_dataset(yr - 1, "stapelingsmonitor", ...)  # same body as today's lapply
  })
  rbindlist(dt_list, fill = TRUE)
}
```

This is a worse tool than a real `crew`/`future` controller (no per-year
caching, you re-load all years together as one target again — so it actually
trades away some of §1's branching benefit for the parallelism), but it's a
realistic fallback if the RA package set genuinely won't budge, and it costs
nothing to try since `parallel` is already there.

## 5. Large data.table targets use the default `format = "rds"`

For the bigger intermediate tables (`dt_rins`, `dt_stapeling_filtered_clean`,
`dt_rins_merged`, `dt_rins_with_vars`) it's worth setting
`tar_option_set(format = "qs")` (or per-target `format = "qs"`) — `qs` is
usually noticeably faster to read/write than base `rds` for exactly this
"wide data.table with a few million rows" shape, and every `tar_make()` skip
of an up-to-date target still has to *read* the target to hash/pass it
downstream, so this compounds.

**Use `format = "qs"`, not `format = "qs2"`.** Recent `targets` versions added
a newer `"qs2"` format backed by the separate `qs2` package (a rewrite of
`qs` with a different API) and nudge you towards it in messages/docs — but
it's a genuinely different package, not just a newer version of the same one.
If only `qs` is installed in the RA, `format = "qs"` is the right (and still
fully supported) option; don't chase the `qs2` install just because `targets`
suggests it. No entry needs to be added to `tar_option_set(packages = ...)`
for this — that list is for packages your target *commands* call, and format
packages are loaded internally by `targets` regardless.

## 6. Memory: `memory` and garbage collection aren't tuned

Given the RA VM's memory is usually the actual constraint, not CPU:
`tar_option_set(memory = "transient", garbage_collection = TRUE)` releases a
target's value from the `targets` process as soon as its downstream targets
have consumed it, instead of holding every upstream target in memory for the
whole `tar_make()` run. Worth trying on this pipeline in particular — you
already do a manual `gc()` inside `aggregate_OT_OUD()` (`03_aggregate.R:124`),
which is a sign you've hit this problem by hand; the pipeline-level option
does it systematically instead of at one spot you happened to profile.

## 7. Output files written as side effects, not as tracked targets

`save_processed()` / `save_output()` (`globals.R:22-61`) write `.xlsx`/`.csv`
files as a side effect and the target still returns the data.table. `targets`
has no idea these files exist, so it can't tell you if someone manually
edited or deleted an output file between runs — `tar_make()` will report
"up to date" even though the file on disk no longer matches what the pipeline
produced. If the actual deliverable *is* the file (which for `OT_HHKIND`/
`OT_OUD` output tables, it is), consider a dedicated
`tar_target(path_OT_OUD, { save_output(...); destination_name }, format = "file")`
so the file's existence and hash become part of the dependency graph.

## 8. Untracked `source()` calls outside `tar_source()`

`R/globals.R:2-3` sources two files by absolute path
(`H:/utils/demog_functions.R`, `H:/_Personal_folders/Marco/loading function/src/m_functions.R`)
directly, outside the project's own `tar_source()` scan. If either changes,
`targets` has no static-code-analysis visibility into it and won't invalidate
anything downstream — same class of problem as §3, just for functions instead
of data. Where possible, keep function dependencies inside the project's own
tracked `R/` folder (vendoring a copy or, better, turning shared helpers into
an internal package) so `tar_source()`/`tar_option_set(packages=)` actually
sees them.

## 9. Quality checks exist but aren't in the pipeline's DAG

`perform_external_checks_statline()` and `perform_external_checks_OS()`
(`04_quality_checks.R`) are fully written but never called from `_targets.R`
— they're presumably run ad hoc in the console. Making them real targets
(`tar_target(qc_statline, perform_external_checks_statline(...))`) means
they show up in `tar_visnetwork()`, get cached like everything else, and —
more importantly — automatically rerun whenever their upstream aggregation
targets change, instead of relying on remembering to rerun them by hand
before an output check.

## 10. Small things worth tidying while you're in there

- Mixed `tar_target(name = x, command = y)` vs positional
  `tar_target(x, command = y)` (e.g. `dt_rins_merged` at `_targets.R:119`) —
  harmless, but pick one for consistency; `tar_manifest()` output reads
  slightly better with explicit `name =`/`command =` everywhere.
- `run_pipeline()` in `globals.R:66-92` re-implements a progress reporter by
  manually printing `tar_visnetwork()` before/after `tar_make()`. `targets`
  already has `tar_make(reporter = "timestamp")` for live per-target progress
  and a ready-made `tar_watch()` Shiny app for a live dashboard (you'd already
  found it — it's commented out at `globals.R:76-86`). Worth turning that
  back on instead of the bespoke wrapper.
- Consider `tar_option_set(error = "null")` (or per-target `error =`) for the
  quality-check targets from §9 specifically, so a QC mismatch doesn't take
  down the whole `tar_make()` run for targets that don't depend on it.

## Suggested order to tackle this

1. §3 and §8 (untracked file/function dependencies) — these are silent
   correctness risks, not just style, and are cheap to fix.
2. §7 (track output files) and §9 (put QC in the DAG) — same category, and
   both matter a lot for an output-check pipeline specifically.
3. §5/§6 (`qs` format, `memory = "transient"`) — five-minute changes, likely
   noticeable speedup in the RA session.
4. §4 (parallelism) — check what's actually installed first; `crew` is the
   real fix but only if the RA has it, otherwise the `parallel`-based
   fallback is worth a try once §1 exists.
5. §1 (dynamic branching) and §2 (`tar_map()` for the duplicated
   aggregate/output pairs) — the real structural upgrade for iter2.
