#### create base populations ####
get_base_population <- function(base_years, use_sample = FALSE) {
  
  if (is.numeric(use_sample)) {
    dt_demog <- load_dataset(
      2018,
      "stapelingsmonitor",
      cols = c("rinpersoon"),
      create_year_col = TRUE,
      stop_on_mismatch = FALSE #TODO: use newest version when outputting
    )
    
    rin_set_sample <- sample(dt_demog$rinpersoon, use_sample)
  }
  
  # for development, we want a sample of rinpersonen to speed up. Disable for final output
  dt_rins <- rbindlist(lapply(base_years, function(yr) {
    
    # load rins
    dt_demog <- load_dataset(
      yr-1, # align to 1 jan of year
      "stapelingsmonitor",
      cols = c("rinpersoon", paste0("gem_", yr-1)),
      lock_dataset = TRUE,
      rinpersoon_set = if (is.numeric(use_sample)) rin_set_sample else NULL,
      stop_on_mismatch = FALSE #TODO: use newest version when outputting
    )
    
    dt_demog[, year := yr]
    
    if (use_sample == "ams") {
      dt_demog <- dt_demog[gem == "0363"]
    }
    
    # drop NA rins
    dt_demog <- dt_demog[!is.na(rinpersoon)]

    # return only relevant cols
    return(dt_demog[, .SD, .SDcols = c("rinpersoon", "year")])
  }))
  
  return(dt_rins)
}

#### load datasets ####
load_filter_kindoudertab <- function(dt_rins) {

  # load
  dt_kindouder <- load_dataset(
    2025, 
    "kindoudertab", 
    cols = c("rinpersoon", "rinpersoons", "rinpersoonpa", "rinpersoonma"), 
    labelled_cols = "xkoppelnummer",
    lock_dataset=TRUE
    )
  
  # filter for all rinpersoon cols
  dt_kindouder <- dt_kindouder[
    rinpersoon %in% unique(dt_rins$rinpersoon) |
      rinpersoonma %in% unique(dt_rins$rinpersoon) |
      rinpersoonpa %in% unique(dt_rins$rinpersoon)
  ]
  
  # clean col types
  suppressWarnings(to_num(dt_kindouder, c("rinpersoonpa", "rinpersoonma")))
  
  # filter by rinpersonen in children dataset
  # dt_kindouder <- filter_rinpersoon(dt_kindouder, unique(dt_rins_children$rinpersoon))
  
  # handle double rows
  dt_kindouder[, count := .N, by = rinpersoon]
  dt_kindouder <- dt_kindouder[count == 1 | (count > 1 & rinpersoons != "N")]
  
  # recount, and discard where count > 1 (with test this was only one row, where a doodgeborene somehow got matched in stapeling)
  dt_kindouder[, count := .N, by = rinpersoon]
  dt_kindouder <- dt_kindouder[count == 1]
  dt_kindouder[, count := NULL]
  
  
  return(dt_kindouder)
}

load_filter_clean_stapeling <- function(dt_rins) {
  
  dt_stapeling_filtered_clean <- rbindlist(lapply(base_years, function(yr) {
    
    dt_stapeling_yr <- load_dataset(
      yr-1, 
      "stapelingsmonitor",
      cols = c(paste0(all_cols_to_load_stapeling, glue("_{yr-1}")), "rinpersoon"),
      rinpersoon_set = unique(dt_rins$rinpersoon),
      lock_dataset=T,
      overwrite_lock = T,
      stop_on_mismatch = F
      )
    
    dt_stapeling_yr[, year := yr]
    return(dt_stapeling_yr)
  }), fill=T)
  
  # add herkomst
  dt_stapeling_filtered_clean <- add_herkomst(dt_stapeling_filtered_clean)
  
  # try to replace labels that didn't work
  for (col in labelled_cols_stapeling) {
    try(
      replace_values_by_haven_labels(
        dt_stapeling_filtered_clean,
        sav_path = get_path_newest(glue("G:/Maatwerk/STAPELINGSMONITOR/2023"), 2023, extension = ".sav"),
        cols = col,
        format=T
      )
    )
  }
  
  return(dt_stapeling_filtered_clean)
}

load_filter_clean_zvw <- function(dt_rins, cols_to_load_zvw) {
  
  proxy_costs_per_ha_visit <- data.table(
    year = 2018:2020, # up until huisarts for proxy
    costs_per_ha_visit = c(9.59, 9.97, 10.15)
  )
  
  dt_zvw <- load_dataset(
    base_years,
    "zvwzorgkostentab", 
    cols = c("rinpersoon", "zvwkhuisarts", "zvwkwykverpleging"), 
    lock_dataset=TRUE,
    create_year_col = TRUE,
    rinpersoon_set = unique(dt_rins$rinpersoon)
    )
  
  # merge in the costs
  dt_zvw <- merge_with_validate(
    dt_zvw, 
    proxy_costs_per_ha_visit,
    by = "year",
    validate = "many_to_one",
    require_match = "right"
  )
  
  dt_zvw <- dt_zvw[, .(
    n_huisarts_visits = fifelse(year %in% min(base_years):2020,
                                round(zvwkhuisarts / costs_per_ha_visit, 0),
                                NA
                                ), # proxy to use with huisartdecltab later
    uses_wvp = as.integer(any(zvwkwykverpleging > 0), na.rm=T)
  ), by = .(rinpersoon, year)]

  return(dt_zvw)
  
}

load_filter_clean_wmobus <- function(dt_rins) {
  dt_wmobus <- load_dataset(
    base_years, 
    "wmobus",
    lock_dataset=TRUE,
    cols = "rinpersoon",
    create_year_col = TRUE,
    rinpersoon_set = unique(dt_rins$rinpersoon)
    )
  
  # we just need to get the rinpersonen per year, to know if they used wlz
  dt_wmobus = unique(dt_wmobus)[, uses_wmo := 1]
  
  return(dt_wmobus)
}

load_filter_clean_gbapersoontab <- function(cols_to_load_gbapersoontab) {
  
  cols_to_load_gbapersoontab <- c(
    "rinpersoon",
    "gbageboortejaar",
    "gbageboortedatum",
    "gbageboortemaand",
    "gbageboortejaarmoeder",
    "gbageboortemaandmoeder",
    "gbageboortejaarvader",
    "gbageboortemaandvader"
  )
  
  dt_gbapersoontab <- load_dataset(
    max(base_years), 
    "gbapersoontab",
    lock_dataset=TRUE,
    cols = cols_to_load_gbapersoontab,
    )
  
  # turn the year/month cols into date cols
  for (suffix in c("", "vader", "moeder")) {
    dt_gbapersoontab[, (glue("gbageboortedatum{suffix}")) := 
      paste(get(glue("gbageboortejaar{suffix}")), 
                    get(glue("gbageboortemaand{suffix}")), 
                    "15", sep = "-")]
    dt_gbapersoontab[, (glue("gbageboortedatum{suffix}")) := fifelse(
      get(glue("gbageboortejaar{suffix}")) == "----",
      NA,
      as.Date(get(glue("gbageboortedatum{suffix}")), format = "%Y-%m-%d")
    )]
  }
  
  dt_gbapersoontab[, c("gbageboortemaand", 
                       "gbageboortejaarvader", "gbageboortemaandvader",
                       "gbageboortejaarmoeder", "gbageboortemaandmoeder") := NULL]
  
  
  dt_gbapersoontab[, ':=' (
    leeftijd_moeder_geboorte = fifelse(!is.na(gbageboortedatummoeder), as.numeric(gbageboortedatum - gbageboortedatummoeder), NA),
    leeftijd_vader_geboorte = fifelse(!is.na(gbageboortedatumvader), as.numeric(gbageboortedatum - gbageboortedatumvader), NA)
  )]
  
  dt_gbapersoontab[, ':=' (
    jonge_moeder_geboorte = as.integer(leeftijd_moeder_geboorte < (20*365.25)),
    jonge_vader_geboorte = as.integer(leeftijd_vader_geboorte < (20*365.25) | is.na(leeftijd_vader_geboorte))
  )]
  
  return(dt_gbapersoontab)
}

load_filter_clean_indicwlztab <- function(dt_rins) {
  
  dt_indicwlztab <- load_dataset(
    base_years,
    "indicwlztab",
    cols = "rinpersoon",
    rinpersoon_set = unique(dt_rins$rinpersoon),
    lock_dataset=TRUE,
    create_year_col = TRUE
  )

  # we just need to get the rinpersonen per year, to know if they used wlz
  dt_indicwlztab = unique(dt_indicwlztab)[, uses_wlz := 1]

  return(dt_indicwlztab)
}

load_filter_clean_vslgwbtab <- function(target_align_year, dt_adresobjectbus) {
  
  rinobjectnummer_set <- unique(dt_adresobjectbus$rinobjectnummer)
  
  # load both datasets
  bc_col_name <- glue("bc{target_align_year}")
  wc_col_name <- glue("wc{target_align_year}")
  
  dt_vslgwbtab <- load_dataset(
    target_align_year,
    "vslgwbtab",
    cols = c(
      "rinobjectnummer", 
      wc_col_name,
      bc_col_name
    )
  )
  
  dt_nietvslgwbtab <- load_dataset(
    target_align_year,
    "nietvslgwbtab",
    cols = c(
      "rinobjectnummer", 
      wc_col_name,
      bc_col_name
    )
  )
  dt_nietvslgwbtab <- haven::zap_labels(dt_nietvslgwbtab)
  
  # for entries in both datasets, we prefer the one in vslgwbtab, more detailed buurtcodes
  dt_nietvslgwbtab <- dt_nietvslgwbtab[!rinobjectnummer %in% unique(dt_vslgwbtab$rinobjectnummer)]
  
  dt_vsl_total <- rbindlist(list(
    dt_vslgwbtab,
    dt_nietvslgwbtab
  ))
  
  # filter for the subset 
  dt_vsl_total <- dt_vsl_total[rinobjectnummer %in% rinobjectnummer_set]
  
  # remove year suffix from dt
  setnames(dt_vsl_total, c(wc_col_name, bc_col_name), c("wc", "bc"))
  
  # return unique dataset, for the few weird cases where there are duplicated rows exactly
  dt_vsl_total <- unique(dt_vsl_total, by = "rinobjectnummer")
  
  return(dt_vsl_total)
}

load_filter_clean_adresobjectbus <- function(dt_rins) {
  dt_adresobjectbus <- load_dataset(
    2025,
    "gbaadresobjectbus",
    cols = c("rinpersoon", "rinobjectnummer", "gbadatumaanvangadreshouding", "gbadatumeindeadreshouding"),
    rinpersoon_set = unique(dt_rins$rinpersoon),
  )
  
  # convert date cols to numeric
  dt_adresobjectbus[, ':='(
    gbadatumaanvangadreshouding = as.numeric(gbadatumaanvangadreshouding),
    gbadatumeindeadreshouding = as.numeric(gbadatumeindeadreshouding)
  )]
  
  
  return(dt_adresobjectbus)
}

load_filter_clean_inhatab <- function(dt_rins) {
  dt_inhatab <- rbindlist(lapply(base_years, function(yr) {
    
    # then get the koppelpersoonhuishouden dataset
    path_csv_koppel <- get_path_newest(
      "G:/InkomenBestedingen/INHATAB",
      string_pattern = paste0("(?=.*KOPPEL)(?=.*", yr, ")"), #folder contains both inhatab files and KOPPELPERSOONHUISHOUDEN files
      extension = ".csv",
      lock_dataset = T,
      method = "newest"
    )
    
    ds_koppel <- arrow::open_csv_dataset(path_csv_koppel)
    
    dt_koppel<- ds_koppel |>
      mutate(RINPERSOON_num = cast(!!rlang::sym("RINPERSOON"), arrow::int64())) |>
      filter(RINPERSOON_num %in% unique(dt_rins$rinpersoon)) |>
      collect()
    
    dt_koppel <- format_data(dt_koppel, rin_num = FALSE, year = FALSE)
    
    dt_koppel[, year := yr]
    
    path_csv_inhatab <- get_path_newest(
      "G:/InkomenBestedingen/INHATAB",
      string_pattern = paste0("(?=.*INHA)(?=.*", yr, ")"), #folder contains both inhatab files and KOPPELPERSOONHUISHOUDEN files
      extension = ".csv",
      lock_dataset = T
    )

    ds_inhatab <- arrow::open_csv_dataset(path_csv_inhatab)
    
    dt_inhatab <- ds_inhatab |>
      mutate(RINPERSOONHKW_num = cast(!!rlang::sym("RINPERSOONHKW"), arrow::int64())) |>
      filter(RINPERSOONHKW_num %in% unique(dt_koppel$rinpersoonhkw)) |>
      rename_with(tolower) |>
      select(all_of(c(
        "rinpersoonhkw",
        cols_to_load_inhatab
      ))) |>
      collect()
    
    dt_inhatab <- format_data(dt_inhatab, rin_num = FALSE, year = FALSE)
    
    dt_inhatab[, year := yr]
    
    # now merge the two
    dt_inhatab <- merge_with_validate(
      dt_koppel,
      dt_inhatab,
      by = c("rinpersoonhkw"),
      validate = "many_to_one",
      require_match = "right",
      verbose = T,
      all.x=T
    )
    
    # add year col
    dt_inhatab[, year := yr]
    
    return(dt_inhatab)
    
  }))
  
  return(dt_inhatab)
}

load_filter_clean_ggzzpm <- function(dt_rins) {
  dt_ggzzpm <- load_dataset(
    2022:max(base_years),
    "ggzzpmprestatietab",
    cols = c("rinpersoon", "zpmdiagnose"),
    lock_dataset = TRUE,
    rinpersoon_set = unique(dt_rins$rinpersoon),
    create_year_col = TRUE
  )
  
}

load_filter_clean_ggzdeclvektis <- function(dt_rins) {
  dt_ggzdeclvektis <- load_dataset(
    min(base_years):2021,
    "ggzdeclvektis",
    cols = c("rinpersoon", "productcode", "begindatum_prestatie", "einddatum_prestatie"),
    lock_dataset = TRUE,
    rinpersoon_set = unique(dt_rins$rinpersoon)
  )
}

load_filter_clean_huisarts <- function(dt_rins) {
  
  dt_huisarts <- rbindlist(lapply(2021:max(base_years), function(yr) {
    dt <- load_dataset(
      yr,
      "huisartsdecltab",
      cols = c("rinpersoon", "hadeclprestatiecode"),
      lock_dataset = TRUE,
      rinpersoon_set = unique(dt_rins$rinpersoon),
      create_year_col = TRUE
    )
    # create var poh-ggz
    to_num(dt, "hadeclprestatiecode")
    
    # aggregate to rin, and create vars for n_visits & poh_ggz
    dt <- dt[, .(
      n_huisarts_visits = .N,
      uses_poh_ggz = as.integer(any(hadeclprestatiecode %in% poh_ggz_codes, na.rm=TRUE))
      ), by =.(rinpersoon, year)]
    
    return(dt)

  }))
  
  return(dt_huisarts)
}

load_filter_clean_medicijntab <- function(dt_rins) {
  
  ATC_codes_chronische_ziekte <- c(
    "A10", "C03A", "C03B", "C03D", "C03E", "C07A", "C07B","C07C", "C08C", "C08G", 
    "C09A", "C09B", "C09C", "C09D" , "C09X", "C10A", "C10B", "R03A", "R03B", 
    "R03C", "R03D", "N04", "N06D"
  )
  

  dt_medicijn <- rbindlist(lapply(base_years, function(yr) {
    
    dt <- load_dataset(
      yr,
      "medicijntab", 
      cols = c("rinpersoon", "atc4"),
      lock_dataset = TRUE,
      rinpersoon_set = unique(dt_rins$rinpersoon),
      create_year_col = TRUE
    )
    
    # filter for chronische ziekte
    return(dt[atc4 %in% ATC_codes_chronische_ziekte])
  }))
  
  # we want to create binary if someone has chronische ziekte
  dt_medicijn <- unique(dt_medicijn[, .SD, .SDcols = c("rinpersoon", "year")])
  dt_medicijn[, has_chronische_ziekte := 1]
  
  return(dt_medicijn)
}
