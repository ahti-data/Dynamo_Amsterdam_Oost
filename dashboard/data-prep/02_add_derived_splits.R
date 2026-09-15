# Werkt data/app_data/indicators.parquet bij met de afgeleide
# ondersteuningsuitsplitsingen, zonder de ruwe levering nodig te hebben.
#
#   Rscript data-prep/02_add_derived_splits.R
#
# 01_build_app_data.R doet dit al voor elke nieuwe levering. Dit script is er
# voor het geval de afleiding verandert terwijl de levering hetzelfde blijft:
# dan is de 330 MB CSV + 19 MB xlsx opnieuw inlezen (minuten) niet nodig en is
# de bestaande parquet genoeg (seconden). Beide routes roepen dezelfde
# add_support_derivations() aan, dus ze kunnen niet uit elkaar lopen.
#
# Idempotent: eerder afgeleide rijen gaan er eerst uit. De noemer wordt over
# alles opnieuw berekend, met exact dezelfde formule als in 01.
#
# Reads/Writes : data/app_data/indicators.parquet (ter plekke)

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
ROOT <- if (length(script_arg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[1])), ".."))
} else {
  normalizePath(".")
}

source(file.path(ROOT, "data-prep", "derive_support_splits.R"))

PQ_DIR <- file.path(ROOT, "data", "app_data", "indicators.parquet")
if (!dir.exists(PQ_DIR)) {
  stop("Niet gevonden: ", PQ_DIR, "\n  Draai eerst data-prep/01_build_app_data.R.")
}

message("Reading ", PQ_DIR, " ...")
dt <- as.data.table(collect(open_dataset(PQ_DIR)))
message(sprintf("  %s rows", format(nrow(dt), big.mark = ".")))

# open_dataset() geeft de partitiekolommen als factor terug; de afleiding
# vergelijkt ze met karakterwaarden (SUPPORT_COMBO_VAR[population]), en een
# factor zou dan stil op NA uitkomen.
for (cl in c("population", "region_level")) {
  if (is.factor(dt[[cl]])) set(dt, j = cl, value = as.character(dt[[cl]]))
}

n_voor <- nrow(dt)
dt <- add_support_derivations(dt)
message(sprintf("Derived support splits: %s -> %s rows (+%s)",
                format(n_voor, big.mark = "."), format(nrow(dt), big.mark = "."),
                format(nrow(dt) - n_voor, big.mark = ".")))

# Zelfde noemer als in 01_build_app_data.R: de som over de
# variable_value-categorieen binnen dezelfde slice.
message("Recomputing share denominators ...")
dt[, denominator := sum(metric_value, na.rm = TRUE),
   by = .(population, region_level, region_code, year,
          variable_name, metric_name, split_var, split_level)]

setcolorder(dt, c("population", "region_level", "region_code", "region_name", "stadsdeel",
                  "year", "variable_name", "variable_value", "metric_name",
                  "metric_value", "n_totaal", "denominator", "split_var", "split_level"))

message("Writing ...")
unlink(PQ_DIR, recursive = TRUE)
write_dataset(
  dt,
  path         = PQ_DIR,
  format       = "parquet",
  partitioning = c("population", "region_level"),
  compression  = "zstd"
)

sz <- sum(file.info(list.files(PQ_DIR, recursive = TRUE, full.names = TRUE))$size)
message(sprintf("Done. %s rows, %.1f MB on disk.", format(nrow(dt), big.mark = "."), sz / 1024^2))

message("\nSanity check -- Amsterdam 2024, aandeel met een ondersteuningssignaal:")
print(dt[population == "huishoudens met kinderen" & region_level == "gemeente" &
         year == 2024 & variable_name == "O_MPG_ondersteuning" &
         metric_name == "n_households",
         .(variable_value, metric_value, denominator,
           aandeel = round(100 * metric_value / denominator, 1))])
