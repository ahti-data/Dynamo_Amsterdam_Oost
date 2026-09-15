# Build the app's data from a CBS RA delivery.
#
# One-off prep step: re-run by hand after each new delivery. De ruwe levering
# onder data/output_data/ blijft lokaal (gitignored); de parquet-uitvoer onder
# data/app_data/ wordt wel gecommit -- de CI-runner bouwt hem niet zelf (PLAN.md 6).
#
#   Rscript data-prep/01_build_app_data.R
#
# Reads  : data/output_data/output_1a/{OT_HHKIND.csv,OT_OUD.xlsx}
#          data/geo/GM0363_{buurten,wijken,gebieden}.geojson
#          data-prep/derive_support_splits.R  (afgeleide ondersteuningsvormen)
# Writes : data/app_data/indicators.parquet  (partitioned by population/region_level)
#          data/app_data/geo.rds

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(sf)
  library(readxl)
})

# Resolve the dashboard root from the script's own path, so the script runs the
# same via Rscript and from an R session with any working directory.
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
ROOT <- if (length(script_arg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[1])), ".."))
} else {
  normalizePath(".")  # sourced interactively from the dashboard folder
}

RAW_DIR  <- file.path(ROOT, "data", "output_data", "output_1a")
GEO_DIR  <- file.path(ROOT, "data", "geo")
OUT_DIR  <- file.path(ROOT, "data", "app_data")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Shared vocabulary
# ---------------------------------------------------------------------------

# region_agg_level in the delivery -> label used throughout the app.
LEVEL_LABELS <- c(
  bc         = "buurt",
  wc         = "wijk",
  gebiedcode = "gebied",
  stadsdeel  = "stadsdeel",
  gemeente   = "gemeente"
)

# The letter inside an Amsterdam region code identifies the stadsdeel. Verified
# against the delivery: nine letters in the geometry, nine stadsdeel values in
# the data, one-to-one.
STADSDEEL_BY_LETTER <- c(
  A = "Centrum", B = "Westpoort", E = "West",   F = "Nieuw-West", K = "Zuid",
  M = "Oost",    N = "Noord",     S = "Weesp",  T = "Zuidoost"
)

TOTAL_LABEL <- "(totaal)"

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

message("Reading geometry ...")

read_geo <- function(file, code_col, name_col, strip) {
  g <- st_read(file.path(GEO_DIR, file), quiet = TRUE)
  g$region_code <- substring(as.character(g[[code_col]]), strip + 1L)
  g$region_name <- as.character(g[[name_col]])
  g[, c("region_code", "region_name")]
}

geo_buurt  <- read_geo("GM0363_buurten.geojson",  "statcode", "statnaam", 2L)  # BU0363AA01 -> 0363AA01
geo_wijk   <- read_geo("GM0363_wijken.geojson",   "statcode", "statnaam", 2L)  # WK0363AA   -> 0363AA
geo_gebied <- read_geo("GM0363_gebieden.geojson", "code",     "naam",     0L)  # GA01       -> GA01

# The letter sits at a different offset per level, so derive it per level rather
# than with one shared rule.
geo_buurt$stadsdeel  <- STADSDEEL_BY_LETTER[substr(geo_buurt$region_code,  5, 5)]
geo_wijk$stadsdeel   <- STADSDEEL_BY_LETTER[substr(geo_wijk$region_code,   5, 5)]
geo_gebied$stadsdeel <- STADSDEEL_BY_LETTER[substr(geo_gebied$region_code, 2, 2)]

# No stadsdeel file ships with the delivery; dissolve the wijken into one.
geo_stadsdeel <- aggregate(
  geo_wijk["geometry"],
  by   = list(region_code = geo_wijk$stadsdeel),
  FUN  = function(x) x[1]
)
geo_stadsdeel$region_name <- geo_stadsdeel$region_code
geo_stadsdeel$stadsdeel   <- geo_stadsdeel$region_code

# Simplify in RD (metres) rather than degrees, so the tolerance means something.
simplify_m <- function(g, tol_m) {
  g |>
    st_transform(28992) |>
    st_simplify(dTolerance = tol_m, preserveTopology = TRUE) |>
    st_transform(4326) |>
    st_make_valid()
}

geo <- list(
  buurt     = simplify_m(geo_buurt,      10),
  wijk      = simplify_m(geo_wijk,       15),
  gebied    = simplify_m(geo_gebied,     20),
  stadsdeel = simplify_m(geo_stadsdeel,  25)
)

for (lvl in names(geo)) {
  message(sprintf("  %-10s %3d features", lvl, nrow(geo[[lvl]])))
}

saveRDS(geo, file.path(OUT_DIR, "geo.rds"))

# Region code -> name lookup, for levels that have geometry.
name_lookup <- rbindlist(lapply(names(geo), function(lvl) {
  d <- st_drop_geometry(geo[[lvl]])
  data.table(region_level = lvl, region_code = d$region_code,
             region_name = d$region_name, stadsdeel = d$stadsdeel)
}))

# ---------------------------------------------------------------------------
# Reshape one delivery table into the shared long schema
# ---------------------------------------------------------------------------

# Every row in the delivery is either a total (all split columns "all") or a
# single-variable marginal -- never two splits at once. That is what lets the
# wide split columns collapse into one split_var/split_level pair, and it is
# what the app's single "splits uit naar" control relies on. Verified on the
# 09-09-2026 delivery: 0 rows with more than one non-"all" split.
reshape_delivery <- function(dt, split_cols, population_label) {
  setDT(dt)

  keep <- c("region_code", "year", "variable_name", "variable_value",
            "n_totaal_population_in_region", "metric_name", "metric_value",
            "region_agg_level")
  stopifnot(all(c(keep, split_cols) %in% names(dt)))

  for (cl in split_cols) set(dt, j = cl, value = as.character(dt[[cl]]))

  n_nonall <- Reduce(`+`, lapply(split_cols, function(cl) as.integer(dt[[cl]] != "all")))
  if (max(n_nonall) > 1L) {
    stop("Delivery has rows with more than one non-'all' split variable; the ",
         "single-split assumption behind the app's data model no longer holds.")
  }

  totals <- dt[n_nonall == 0L, ..keep]
  totals[, `:=`(split_var = TOTAL_LABEL, split_level = TOTAL_LABEL)]

  marg <- melt(
    dt[n_nonall == 1L, c(keep, split_cols), with = FALSE],
    id.vars       = keep,
    measure.vars  = split_cols,
    variable.name = "split_var",
    value.name    = "split_level",
    variable.factor = FALSE
  )[split_level != "all"]

  out <- rbind(totals, marg)

  setnames(out, "n_totaal_population_in_region", "n_totaal")
  out[, `:=`(
    population   = population_label,
    region_level = unname(LEVEL_LABELS[region_agg_level]),
    year         = as.integer(year),
    metric_value = as.numeric(metric_value),
    n_totaal     = as.numeric(n_totaal)
  )]
  out[, region_agg_level := NULL]
  out[]
}

# ---------------------------------------------------------------------------
# Read the two deliveries
# ---------------------------------------------------------------------------

message("Reading OT_HHKIND.csv (330 MB) ...")
hh <- fread(file.path(RAW_DIR, "OT_HHKIND.csv"), showProgress = FALSE)
message(sprintf("  %s rows", format(nrow(hh), big.mark = ".")))

hh_long <- reshape_delivery(
  hh,
  split_cols = c("kinderopvangtoeslag_hh", "migratieachtergrond_hh",
                 "langwonende_hh", "O_MPG_combination"),
  population_label = "huishoudens met kinderen"
)
rm(hh); invisible(gc())

message("Reading OT_OUD.xlsx (268 MB unpacked) -- slow, single pass ...")
oud <- as.data.table(read_xlsx(file.path(RAW_DIR, "OT_OUD.xlsx"), sheet = 1, guess_max = 100000))
message(sprintf("  %s rows", format(nrow(oud), big.mark = ".")))

# The output form lists a langwonende_hh column for OT_OUD; it is not in the
# file. Take the split columns from what is actually present.
oud_long <- reshape_delivery(
  oud,
  split_cols = intersect(c("herkomst7", "geslacht", "O_OUD_combination"), names(oud)),
  population_label = "ouderen (65+)"
)
rm(oud); invisible(gc())

dt <- rbind(hh_long, oud_long)
rm(hh_long, oud_long); invisible(gc())

# ---------------------------------------------------------------------------
# Names, stadsdeel, denominator
# ---------------------------------------------------------------------------

message("Joining region names ...")

dt <- merge(dt, name_lookup, by = c("region_level", "region_code"), all.x = TRUE)

# gemeente has no geometry entry; stadsdeel is its own name.
dt[region_level == "gemeente",  `:=`(region_name = region_code, stadsdeel = NA_character_)]
dt[region_level == "stadsdeel", `:=`(region_name = region_code, stadsdeel = region_code)]

missing_name <- dt[is.na(region_name), .N]
if (missing_name > 0L) {
  warning(sprintf("%d rows have no region_name -- check the geometry vintage.", missing_name))
  print(unique(dt[is.na(region_name), .(region_level, region_code)])[1:20])
}

# ---------------------------------------------------------------------------
# Afgeleide ondersteuningsuitsplitsingen
# ---------------------------------------------------------------------------

# "Wel/geen ondersteuningssignaal" en "hoeveel vormen tegelijk" zitten niet als
# kolom in de levering, maar zijn exact af te leiden uit de combinatierijen --
# zie data-prep/derive_support_splits.R voor de afleiding en de
# onderdrukkingsregel. Draait voor de noemerberekening hieronder, zodat die in
# een keer ook over de nieuwe rijen gaat.
source(file.path(ROOT, "data-prep", "derive_support_splits.R"))

message("Deriving support splits ...")
n_voor <- nrow(dt)
dt <- add_support_derivations(dt)
message(sprintf("  +%s rows", format(nrow(dt) - n_voor, big.mark = ".")))

# Share denominator: the total across the variable_value categories within the
# same slice. Unlike n_totaal (households) this stays a valid percentage for
# every metric, including the n_kinderen_* ones that count children.
message("Computing share denominators ...")
dt[, denominator := sum(metric_value, na.rm = TRUE),
   by = .(population, region_level, region_code, year,
          variable_name, metric_name, split_var, split_level)]

setcolorder(dt, c("population", "region_level", "region_code", "region_name", "stadsdeel",
                  "year", "variable_name", "variable_value", "metric_name",
                  "metric_value", "n_totaal", "denominator", "split_var", "split_level"))

# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

message(sprintf("Writing %s rows to parquet ...", format(nrow(dt), big.mark = ".")))

pq_dir <- file.path(OUT_DIR, "indicators.parquet")
unlink(pq_dir, recursive = TRUE)
write_dataset(
  dt,
  path         = pq_dir,
  format       = "parquet",
  partitioning = c("population", "region_level"),
  compression  = "zstd"
)

sz <- sum(file.info(list.files(pq_dir, recursive = TRUE, full.names = TRUE))$size)
message(sprintf("Done. %s rows, %.1f MB on disk.", format(nrow(dt), big.mark = "."), sz / 1024^2))

message("\nSanity check -- Amsterdam totals, n_households, R_MPG_totaal, 2024:")
print(dt[population == "huishoudens met kinderen" & region_level == "gemeente" &
         year == 2024 & variable_name == "R_MPG_totaal" & metric_name == "n_households" &
         split_var == TOTAL_LABEL,
         .(variable_value, metric_value, n_totaal, denominator)])
