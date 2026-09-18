# Build the app's data from a CBS RA delivery.
#
# One-off prep step: re-run by hand after each new delivery. De ruwe levering
# onder data/output_data/ blijft lokaal (gitignored); de parquet-uitvoer onder
# data/app_data/ wordt wel gecommit -- de CI-runner bouwt hem niet zelf (PLAN.md 6).
#
#   Rscript data-prep/01_build_app_data.R
#
# Reads  : data/output_data/output_1b/{OT_HHKIND*,OT_OUD*}  (.csv of .xlsx)
#          data/geo/GM0363_{buurten,wijken,gebieden}.geojson
#          data-prep/derive_support_splits.R  (afgeleide ondersteuningsvormen)
#          utils/splits.R, utils/metrics.R    (gedeeld met de app)
# Writes : data/app_data/indicators.parquet  (partitioned by population/region_level)
#          data/app_data/geo.rds
#          data/app_data/source_info.rds     (welke levering hier in zit)

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

# De codering van een samengestelde uitsplitsing en de soorten metrics staan in
# utils/, want de app leest ze terug en moet er exact hetzelfde over denken.
source(file.path(ROOT, "utils", "splits.R"))
source(file.path(ROOT, "utils", "metrics.R"))

# Welke levering hier in gaat. Staat ook in de uitvoer (source_info.rds), zodat
# de app en elke export kunnen zeggen waar hun cijfers vandaan komen zonder dat
# iemand die naam op twee plekken moet bijwerken.
DELIVERY_ID <- "output_1b"

RAW_DIR  <- file.path(ROOT, "data", "output_data", DELIVERY_ID)
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

TOTAL_LABEL <- SPLIT_TOTAL_LABEL

# De vaste kolommen van de levering: alles wat *geen* splitsvariabele is. Elke
# andere kolom wordt als splitsvariabele behandeld, zodat een levering met meer
# uitsplitsingen (output_1b heeft er flink wat bij) geen codewijziging vraagt.
# Komt er een nieuwe vaste kolom bij, dan valt dat hieronder hard om -- die
# hoort dan hier in de lijst, niet in de keuzelijst van het dashboard.
#
# Ze zijn tegelijk de verplichte kolommen: zonder een ervan valt er niets te
# bouwen, en dat hoort meteen om te vallen in plaats van pas in het dashboard.
DELIVERY_FIXED_COLS <- c(
  "region_code", "region_agg_level", "year",
  "variable_name", "variable_value",
  "n_totaal_population_in_region", "n_totaal_region_split",
  "metric_name", "metric_value"
)

# De waarde waarmee de levering "niet naar deze variabele uitgesplitst" codeert.
SPLIT_ALL <- "all"

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

#' Zoekt het bestand van een populatie in de levering.
#'
#' Op naam, niet op een vast pad: de bestandsnaam en de extensie zijn per
#' levering anders geweest (csv voor huishoudens, xlsx voor ouderen), en dat is
#' geen reden om de prep-stap te moeten aanpassen.
vind_levering <- function(prefix) {
  f <- list.files(RAW_DIR, pattern = sprintf("^%s.*\\.(csv|xlsx)$", prefix),
                  ignore.case = TRUE, full.names = TRUE)
  if (length(f) == 0L) {
    stop(sprintf("Geen bestand dat begint met \"%s\" in %s.\n  Aanwezig: %s",
                 prefix, RAW_DIR, paste(list.files(RAW_DIR), collapse = ", ")))
  }
  if (length(f) > 1L) {
    stop(sprintf("Meerdere bestanden beginnen met \"%s\" in %s: %s.\n  Laat er een staan.",
                 prefix, RAW_DIR, paste(basename(f), collapse = ", ")))
  }
  f
}

lees_levering <- function(pad) {
  message(sprintf("Reading %s (%.0f MB) ...", basename(pad), file.size(pad) / 1024^2))
  d <- if (grepl("\\.csv$", pad, ignore.case = TRUE)) {
    fread(pad, showProgress = FALSE)
  } else {
    as.data.table(read_xlsx(pad, sheet = 1, guess_max = 100000))
  }
  message(sprintf("  %s rows, %d columns", format(nrow(d), big.mark = ".", decimal.mark = ","), ncol(d)))
  d
}

#' Zet een leveringstabel om naar het lange schema.
#'
#' **Wat er veranderde met output_1b.** De vorige levering kruiste nooit twee
#' splitsvariabelen: elke rij was of een totaalrij (alle splitskolommen "all")
#' of een marginaal van een enkele variabele, en daarom kon `split_var` een
#' enkele naam zijn. Dat geldt niet meer. Een rij draagt nu de *verzameling*
#' variabelen waarnaar hij is uitgesplitst, gecodeerd zoals utils/splits.R
#' beschrijft: de namen alfabetisch aan elkaar geplakt, de waarden in dezelfde
#' volgorde. Een enkelvoudige uitsplitsing is daar het bijzondere geval van, dus
#' elke bestaande filter op `split_var == "O_MPG_combination"` blijft precies
#' doen wat hij deed.
#'
#' Welke kolommen splitsvariabelen zijn, komt uit de kop van het bestand en niet
#' uit een lijst hier: zo hoeft een levering met meer uitsplitsingen geen
#' codewijziging. Een kolom telt als splitsvariabele als hij ergens de waarde
#' "all" heeft -- dat is het merkteken van "op deze rij niet uitgesplitst".
reshape_delivery <- function(dt, population_label) {
  setDT(dt)

  ontbreekt <- setdiff(DELIVERY_FIXED_COLS, names(dt))
  if (length(ontbreekt)) {
    stop(sprintf("De levering mist kolommen: %s.\n  Aanwezig: %s",
                 paste(ontbreekt, collapse = ", "), paste(names(dt), collapse = ", ")))
  }

  # Radix, niet de locale-collatie: de volgorde hier bepaalt de sleutel in de
  # parquet, en die moet dezelfde zijn als die split_key() in de app bouwt.
  split_cols <- sort(setdiff(names(dt), DELIVERY_FIXED_COLS), method = "radix")
  if (length(split_cols) == 0L) {
    stop("Geen enkele splitskolom gevonden; dan klopt DELIVERY_FIXED_COLS niet meer.")
  }

  # Lege cellen als "all" lezen: sommige exports schrijven een niet-uitgesplitste
  # cel leeg weg in plaats van met het woord.
  for (cl in split_cols) {
    v <- as.character(dt[[cl]])
    set(dt, j = cl, value = fifelse(is.na(v) | !nzchar(v), SPLIT_ALL, v))
  }

  # Een kolom zonder enkele "all" is geen splitsvariabele maar een vaste kolom
  # die hier nog niet bekend is. Die zou anders als uitsplitsing in het
  # dashboard belanden, dus liever hier stoppen.
  geen_all <- split_cols[vapply(split_cols, function(cl) !any(dt[[cl]] == SPLIT_ALL), logical(1))]
  if (length(geen_all)) {
    stop(sprintf(paste("Kolom(men) zonder de waarde \"%s\": %s.",
                       "Dat lijken vaste kolommen, geen uitsplitsingen --",
                       "zet ze in DELIVERY_FIXED_COLS."),
                 SPLIT_ALL, paste(geen_all, collapse = ", ")))
  }

  # De hele codering staat of valt ermee dat geen naam of waarde het
  # scheidingsteken bevat.
  split_check_sep(split_cols, "Een splitskolomnaam")
  for (cl in split_cols) {
    split_check_sep(unique(dt[[cl]]), sprintf("Een waarde van %s", cl))
  }

  message(sprintf("  %d splitsvariabelen: %s", length(split_cols),
                  paste(split_cols, collapse = ", ")))

  keep <- DELIVERY_FIXED_COLS
  n_nonall <- Reduce(`+`, lapply(split_cols, function(cl) as.integer(dt[[cl]] != SPLIT_ALL)))
  message(sprintf("  uitsplitsingsdiepte: %s",
                  paste(sprintf("%d var -> %s rijen", as.integer(names(table(n_nonall))),
                                format(as.integer(table(n_nonall)), big.mark = ".", decimal.mark = ",")),
                        collapse = " | ")))

  totals <- dt[n_nonall == 0L, ..keep]
  totals[, `:=`(split_var = TOTAL_LABEL, split_level = TOTAL_LABEL)]

  marg <- dt[n_nonall > 0L, c(keep, split_cols), with = FALSE]
  marg[, .rid := .I]

  lang <- melt(marg[, c(".rid", split_cols), with = FALSE], id.vars = ".rid",
               variable.name = "svar", value.name = "slevel", variable.factor = FALSE)
  lang <- lang[slevel != SPLIT_ALL]
  # Sorteren op (rij, variabelenaam) maakt de sleutel alfabetisch -- de volgorde
  # waarop split_key() in utils/splits.R hem ook bouwt, zodat de app dezelfde
  # rijen vindt hoe de gebruiker zijn keuzes ook aanklikt.
  setorder(lang, .rid, svar)
  sleutels <- lang[, .(split_var   = paste(svar,   collapse = SPLIT_SEP),
                       split_level = paste(slevel, collapse = SPLIT_SEP)), by = .rid]

  marg <- merge(marg[, c(".rid", keep), with = FALSE], sleutels, by = ".rid")
  marg[, .rid := NULL]

  out <- rbind(totals, marg, use.names = TRUE)

  setnames(out, "n_totaal_population_in_region", "n_totaal")
  setnames(out, "n_totaal_region_split", "n_split")
  out[, `:=`(
    population   = population_label,
    region_level = unname(LEVEL_LABELS[region_agg_level]),
    year         = as.integer(year),
    metric_value = as.numeric(metric_value),
    n_totaal     = as.numeric(n_totaal),
    n_split      = as.numeric(n_split)
  )]
  out[, region_agg_level := NULL]
  out[]
}

# ---------------------------------------------------------------------------
# Read the two deliveries
# ---------------------------------------------------------------------------

bestand_hh  <- vind_levering("OT_HHKIND")
bestand_oud <- vind_levering("OT_OUD")

hh <- lees_levering(bestand_hh)
hh_long <- reshape_delivery(hh, population_label = "huishoudens met kinderen")
rm(hh); invisible(gc())

oud <- lees_levering(bestand_oud)
oud_long <- reshape_delivery(oud, population_label = "ouderen (65+)")
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

# De levering levert n_totaal_region_split nu zelf; op een totaalrij hoort dat
# hetzelfde te zijn als n_totaal. Dat is de goedkoopste controle dat de kolom
# betekent wat we denken dat hij betekent -- en de aanname waarop de hele
# afleiding hieronder staat.
controle <- dt[split_var == TOTAL_LABEL & !is.na(n_split) & !is.na(n_totaal)]
if (nrow(controle) > 0L) {
  afwijkend <- controle[abs(n_split - n_totaal) > 0]
  message(sprintf("n_split-controle op de totaalrijen: %s van %s rijen wijken af van n_totaal.",
                  format(nrow(afwijkend), big.mark = ".", decimal.mark = ","),
                  format(nrow(controle), big.mark = ".", decimal.mark = ",")))
  if (nrow(afwijkend) > 0L) {
    warning("n_totaal_region_split wijkt op totaalrijen af van n_totaal_population_in_region; ",
            "controleer of de kolom betekent wat de afleiding aanneemt.")
    print(head(afwijkend[, .(population, region_level, region_code, year,
                             variable_name, metric_name, n_totaal, n_split)], 10))
  }
}

# ---------------------------------------------------------------------------
# Afgeleide ondersteuningsuitsplitsingen
# ---------------------------------------------------------------------------

# "Wel/geen ondersteuningssignaal" en "hoeveel vormen tegelijk" zitten niet als
# kolom in de levering, maar zijn er exact uit af te leiden -- zie
# data-prep/derive_support_splits.R. Draait voor de noemerberekening hieronder,
# zodat die in een keer ook over de nieuwe rijen gaat.
source(file.path(ROOT, "data-prep", "derive_support_splits.R"))

message("Deriving support splits ...")
n_voor <- nrow(dt)
dt <- add_support_derivations(dt)
message(sprintf("  +%s rows", format(nrow(dt) - n_voor, big.mark = ".", decimal.mark = ",")))

# ---------------------------------------------------------------------------
# Noemer
# ---------------------------------------------------------------------------

# Twee soorten noemer, en de levering geeft de belangrijkste nu zelf:
#
#  - Telt de metric de populatie-eenheid (huishoudens, ouderen), dan is de
#    noemer het aantal eenheden in deze regio x uitsplitsing -- en dat is
#    exact `n_split`. Tot output_1a moest dat teruggerekend worden door de
#    categorieen van de indicator op te tellen, wat te laag uitviel zodra er een
#    categorie onderdrukt was. Die terugrekening is hier weg.
#  - Telt de metric iets anders (de `n_kinderen_*`-metrics tellen kinderen tegen
#    een huishoudnoemer), dan is `n_split` de verkeerde eenheid en blijft de som
#    over de variable_value-categorieen binnen dezelfde slice de enige noemer
#    die klopt (PLAN.md 6).
#  - Een gemiddelde heeft geen noemer: optellen van gemiddelden geeft geen
#    totaal, dus elk "aandeel" ervan zou verzonnen zijn.
message("Computing share denominators ...")
dt[, denominator_som := sum(metric_value, na.rm = TRUE),
   by = .(population, region_level, region_code, year,
          variable_name, metric_name, split_var, split_level)]
dt[, denominator := fifelse(metric_telt_populatie(metric_name) & !is.na(n_split),
                            n_split, denominator_som)]
dt[metric_is_gemiddelde(metric_name), denominator := NA_real_]

# Hoeveel de oude terugrekening scheelde, zodat het effect van deze levering in
# de logregels staat in plaats van alleen in de commit.
verschil <- dt[metric_telt_populatie(metric_name) & !is.na(n_split) &
               abs(denominator_som - n_split) > 0]
message(sprintf("  exacte noemer i.p.v. categoriesom: %s van %s rijen kregen een ander getal",
                format(nrow(verschil), big.mark = ".", decimal.mark = ","),
                format(dt[metric_telt_populatie(metric_name), .N], big.mark = ".", decimal.mark = ",")))
dt[, denominator_som := NULL]

setcolorder(dt, c("population", "region_level", "region_code", "region_name", "stadsdeel",
                  "year", "variable_name", "variable_value", "metric_name",
                  "metric_value", "n_totaal", "n_split", "denominator",
                  "split_var", "split_level", "afgeleid"))

# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

message(sprintf("Writing %s rows to parquet ...", format(nrow(dt), big.mark = ".", decimal.mark = ",")))

pq_dir <- file.path(OUT_DIR, "indicators.parquet")
unlink(pq_dir, recursive = TRUE)
write_dataset(
  dt,
  path         = pq_dir,
  format       = "parquet",
  partitioning = c("population", "region_level"),
  compression  = "zstd"
)

# Welke levering hier in zit, naast de data in plaats van als constante in
# app.R: de app stempelt dit in elke export, en zo hoeft niemand bij een
# volgende levering twee plekken bij te werken.
saveRDS(
  list(output_id = DELIVERY_ID,
       files     = c("huishoudens met kinderen" = basename(bestand_hh),
                     "ouderen (65+)"            = basename(bestand_oud)),
       built     = Sys.time()),
  file.path(OUT_DIR, "source_info.rds")
)

sz <- sum(file.info(list.files(pq_dir, recursive = TRUE, full.names = TRUE))$size)
message(sprintf("Done. %s rows, %.1f MB on disk.", format(nrow(dt), big.mark = ".", decimal.mark = ","), sz / 1024^2))

message("\nSanity check -- Amsterdam totals, n_households, R_MPG_totaal, 2024:")
print(dt[population == "huishoudens met kinderen" & region_level == "gemeente" &
         year == 2024 & variable_name == "R_MPG_totaal" & metric_name == "n_households" &
         split_var == TOTAL_LABEL,
         .(variable_value, metric_value, n_totaal, n_split, denominator)])

message("\nSanity check -- welke uitsplitsingen zitten er in de parquet:")
print(dt[, .N, by = .(population, split_var)][order(population, -N)][, head(.SD, 12), by = population])
