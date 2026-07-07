source("src/00_inputs.R")
library(glue)
library(dplyr)

#### load dt_overlijden ####
# Load in general dataset
dt_overlijden_with_matched <- r_parquet_get_dt("data/raw/overlijden_with_matched.parquet")
rinpersoon_set <- unique(dt_overlijden_with_matched$rinpersoon)

cost_years_to_load <- 2016:2023


#### MSZ costs ####
# load in filtered prestaties, chunk because of large size
n_chunks <- 20
rinpersoon_set_chunks <- split(rinpersoon_set, cut(seq_along(rinpersoon_set), n_chunks, labels = FALSE))

dt_mszprest_costs <- lapply(seq_along(rinpersoon_set_chunks), function(i) {
  rinpersoon_set_chunk <- rinpersoon_set_chunks[[i]]
  print(glue("Currently processing chunk {i}/{n_chunks} for mszprestaties"))
  dt_mszprest_chunk <- lapply(cost_years_to_load, function(yr) {
    cols <- c(
      "rinpersoon",
      "vektmszkoppelidprestza",
      "vektmszbegindatumprest",
      "vektmszeinddatumprest",
      "vektmszvergoedbedragzvw",
      "vektmszvergoedbedragav"
    )

    filepath <- get_newest_parquet_check(
      folder_h_parquet = "H:/data/Parquet_files_G_drive/MSZPrestaties/parquet_files",
      folder_g_parquet = "G:/GezondheidWelzijn/MSZPRESTATIESVEKTTAB/geconverteerde data/",
      folder_g_sav = "G:/GezondheidWelzijn/MSZPRESTATIESVEKTTAB",
      string_pattern_parquet = yr,
      string_pattern_sav = yr,
    )

    ds <- arrow::open_dataset(filepath)

    dt_mszprest_chunk_year <- ds |>
      filter(RINPERSOON %in% rinpersoon_set_chunk) |>
      select(c(dplyr::starts_with(cols))) |>
      collect()

    return(format_data(dt_mszprest_chunk_year))
  })

  dt_mszprest_chunk <- rbindlist(dt_mszprest_chunk)

  # set "M"values to NA in columns vektmszvergoedbedragav
  dt_mszprest_chunk[vektmszvergoedbedragav == "M", vektmszvergoedbedragav := NA]

  dt_overlijden_with_matched_chunk <- dt_overlijden_with_matched[rinpersoon %in% rinpersoon_set_chunk]

  dt_mszprest_chunk_costs_monthly <- calculate_costs_by_bin_size(
    dt_mszprest_chunk,
    dt_overlijden_with_matched_chunk,
    cost_columns = c("vektmszvergoedbedragzvw", "vektmszvergoedbedragav"),
    cost_date_col = c("vektmszbegindatumprest"),
    bin_size = "months33",
    convert_cost_date_col = TRUE
  )

  return(dt_mszprest_chunk_costs_monthly)
})

dt_mszprest_costs <- rbindlist(dt_mszprest_costs)

# make gebruikt column
dt_mszprest_costs[, gebruikt_vektmszvergoedbedragzvw := as.integer(vektmszvergoedbedragzvw > 0)]
dt_mszprest_costs[, gebruikt_vektmszvergoedbedragav := as.integer(vektmszvergoedbedragav > 0)]

# save dataset
arrow::write_parquet(dt_mszprest_costs, "data/processed/vektmszkosten_monthly.parquet")

rm(dt_mszprest_costs)
gc()

#### HuisartsDECLTAB ####
# huisartsdecl_years_to_load <- 2021:2023
# n_chunks <- 15
# rinpersoon_set_chunks <- split(rinpersoon_set, cut(seq_along(rinpersoon_set), n_chunks, labels = FALSE))
# 
# dt_huisarts_costs <- lapply(seq_along(rinpersoon_set_chunks), function(i) {
#   rinpersoon_set_chunk <- rinpersoon_set_chunks[[i]]
#   print(glue("Currently processing chunk {i}/{n_chunks} for huisartsdecltab"))
# 
#   dt_huisarts_chunk <- lapply(huisartsdecl_years_to_load, function(yr) {
#     cols <- c("RINPERSOON", "HADECLBegindatumPrest", "HADECLVergoedbedrag", "HADECLPrestatiecode")
# 
#     filepath <- get_newest_parquet_check(
#       folder_h_parquet = "H:/data/Parquet_files_G_drive/HUISARTSDECLTAB/parquet_files",
#       folder_g_parquet = "G:/GezondheidWelzijn/HUISARTSDECLTAB",
#       folder_g_sav = "G:/GezondheidWelzijn/HUISARTSDECLTAB",
#       string_pattern_parquet = yr,
#       string_pattern_sav = yr,
#     )
# 
#     ds <- arrow::open_dataset(filepath)
# 
#     dt_huisarts_chunk_year <- ds |>
#       filter(RINPERSOON %in% rinpersoon_set_chunk) |>
#       select(c(dplyr::all_of(cols))) |>
#       collect()
# 
#     return(format_data(dt_huisarts_chunk_year))
#   })
# 
#   dt_huisarts_chunk <- rbindlist(dt_huisarts_chunk)
# 
#   # create costs, seperate by code
#   dt_huisarts_chunk[, hadeclprestatiecode := trimws(hadeclprestatiecode)]
# 
#   dt_huisarts_chunk[as.numeric(substr(hadeclprestatiecode, 1, 2)) == 11, hadeclvergoedbedrag_inschrijving := hadeclvergoedbedrag]
#   dt_huisarts_chunk[as.numeric(substr(hadeclprestatiecode, 1, 2)) == 12, hadeclvergoedbedrag_consulatations := hadeclvergoedbedrag] 
#   dt_huisarts_chunk[as.numeric(substr(hadeclprestatiecode, 1, 2)) > 12, hadeclvergoedbedrag_others := hadeclvergoedbedrag]
# 
# 
#   dt_overlijden_with_matched_chunk <- dt_overlijden_with_matched[rinpersoon %in% rinpersoon_set_chunk]
# 
#   dt_huisarts_chunk_costs_monthly <- calculate_costs_by_bin_size(
#     dt_huisarts_chunk,
#     dt_overlijden_with_matched_chunk,
#     cost_columns = c("hadeclvergoedbedrag", "hadeclvergoedbedrag_inschrijving", "hadeclvergoedbedrag_consulatations", "hadeclvergoedbedrag_others"),
#     cost_date_col = c("hadeclbegindatumprest"),
#     bin_size = "months33",
# convert_cost_date_col = TRUE

#   )
# 
#   return(dt_huisarts_chunk_costs_monthly)
# })
# 
# dt_huisarts_costs <- rbindlist(dt_huisarts_costs)
# 
# 
# # calculate the actual number of days, since we don't have year 2020
# dt_huisarts_costs[, n_days_available := ifelse(cohort == 2023,
#   365 * 2 + yday(as.Date(as.character(gbadatumoverlijden), format = "%Y%m%d")),
#   0
# )]
# 
# # make gebruikt column
# dt_huisarts_costs[, gebruikt_hadeclvergoedbedrag := as.integer(hadeclvergoedbedrag > 0)]
# dt_huisarts_costs[, gebruikt_hadeclvergoedbedrag_inschrijving := as.integer(hadeclvergoedbedrag_inschrijving > 0)]
# dt_huisarts_costs[, gebruikt_hadeclvergoedbedrag_consulatations := as.integer(hadeclvergoedbedrag_consulatations > 0)]
# dt_huisarts_costs[, gebruikt_hadeclvergoedbedrag_others := as.integer(hadeclvergoedbedrag_others > 0)]
# 
# 
# # save dataset
# arrow::write_parquet(dt_huisarts_costs, "data/processed/huisarts_monthly.parquet")
# 
# rm(dt_huisarts_costs)
# gc()

#### WLZZINTAB ####
print("Processing WLZ costs")
dt_wlz <- lapply(cost_years_to_load, function(yr) {
  cols <- c("RINPERSOON", "BEGINWLZZIN", "BEDRAGWLZZIN")

  filepath <- get_path_newest("G:/GezondheidWelzijn/WLZZINTAB/", string_pattern = yr, extension = ".sav")
  dt <- format_data(haven::read_sav(filepath, col_select = cols))

  # return only relevant rinpersonen
  dt <- dt[rinpersoon %in% rinpersoon_set]

  return(dt)
})

dt_wlz <- rbindlist(dt_wlz)

# find overlaps per rinpersoon
# set column einddatum as same as startdatum

dt_wlz_costs_monthly <- calculate_costs_by_bin_size(
  dt_wlz,
  dt_overlijden_with_matched,
  cost_columns = c("bedragwlzzin"),
  cost_date_col = "beginwlzzin",
  bin_size = "months33",
  convert_cost_date_col = TRUE
)

dt_wlz_costs_monthly[, gebruikt_bedragwlzzin := as.integer(bedragwlzzin > 0)]

arrow::write_parquet(dt_wlz_costs_monthly, "data/processed/wlzkosten_monthly.parquet")

rm(dt_wlz, dt_wlz_costs_monthly)
gc()

#### wijkverpleging ####
print("Processing WVP costs")

dt_wvp <- lapply(cost_years_to_load, function(yr) {
  cols <- c("RINPERSOON", "BEGINZVWWVP", "BEDRAGZVWWVP")

  filepath <- get_path_newest("G:/GezondheidWelzijn/ZVWWVPTAB", string_pattern = yr, extension = ".sav")
  dt <- format_data(haven::read_sav(filepath, col_select = cols))

  # return only relevant rinpersonen
  dt <- dt[rinpersoon %in% rinpersoon_set]

  return(dt)
})

dt_wvp <- rbindlist(dt_wvp)

# find overlaps per rinpersoon
# set column einddatum as same as startdatum

dt_wvp_costs_monthly <- calculate_costs_by_bin_size(
  dt_wvp,
  dt_overlijden_with_matched,
  cost_columns = c("bedragzvwwvp"),
  cost_date_col = "beginzvwwvp",
  bin_size = "months33",
  convert_cost_date_col = TRUE
)

dt_wvp_costs_monthly[, gebruikt_bedragzvwwvp := as.integer(bedragzvwwvp > 0)]
arrow::write_parquet(dt_wvp_costs_monthly, "data/processed/wvpkosten_monthly.parquet")
