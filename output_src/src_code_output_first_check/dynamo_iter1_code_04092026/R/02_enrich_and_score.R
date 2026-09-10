create_huisarts_usage_col <- function(dt_huisarts, dt_zvw) { # TODO: fix because now we load other years for zvw
  
  # we bind together
  dt_huisarts <- rbindlist(list(dt_huisarts, dt_zvw), fill=TRUE, use.names=TRUE)
  
  return(dt_huisarts)
}

enrich_stapeling <- function(dt_stapeling_filtered_clean) {
  # @outcome OT_HHKIND, OT_OUD

  # create the burgstaat change var
  setorder(dt_stapeling_filtered_clean, rinpersoon, year)
  dt_stapeling_filtered_clean[, burgstaat_prev := shift(burgstaat, type = "lag"), by = rinpersoon]
  
  # define rin level variables
  dt_stapeling_filtered_clean[, stapeling_jeugdhulp_temp := rowSums(.SD, na.rm=T), .SDcols = jeugdzorg_cols_stapeling]
  dt_stapeling_filtered_clean <- dt_stapeling_filtered_clean[, ':='(
    burgstaat_change = as.integer(burgstaat_prev == "Gehuwd of geregist. partnerschap" & burgstaat %in% c("Verweduwd", "Gescheiden", "Ongehuwd")), 
    gebruikt_jeugdhulp = as.integer(stapeling_jeugdhulp_temp > 0),
    eenoudergezin = as.integer(typehh == "Eenouderhuishouden"),
    leeftijd_cat = fcase(
      leeftijd %in% 0:3,"kind_tot_4_jaar",
      leeftijd %in% 4:11,"kind_4_tot_12_jaar",
      leeftijd %in% 12:17,"kind_12_tot_18_jaar",
      leeftijd %in% 18:20,"meerderjarig_kind",
      leeftijd %in% 21:27,"21_tot_28_jaar", 
      leeftijd %in% 28:64,"28_tot_65_jaar",
      leeftijd %in% 65:999, "65+_jaar"
    )
  )][, stapeling_jeugdhulp_temp := NULL]
  
  # create a "nieuwkomers" var, based on whether the parents were present in stapeling 5 years ago
  dt_rins_min_5 <- load_dataset(
      base_years-5-1,  # 5 years earlier, minus 1 for the stapeling fix
      "stapelingsmonitor",
      cols = "rinpersoon",
      rinpersoon_set = unique(dt_stapeling_filtered_clean$rinpersoon),
      lock_dataset=T,
      overwrite_lock = T,
      stop_on_mismatch = F,
      create_year_col = T
    )[, year := year+1]
  
  # adjust the years, to create binary col
  dt_rins_min_5[, ':='(
    present_in_stapeling_min5 = 1,
    year = year+5
    )]
  
  dt_stapeling_filtered_clean <- merge_with_validate(
    dt_stapeling_filtered_clean,
    dt_rins_min_5,
    by = c("rinpersoon", "year"),
    validate = "one_to_one", 
    all.x=T,
    verbose = T
  )
  
  dt_stapeling_filtered_clean[is.na(present_in_stapeling_min5), present_in_stapeling_min5 := 0]
  
  # create nieuwkomers col
  dt_stapeling_filtered_clean[, nieuwkomer_in_hh := any(
                                present_in_stapeling_min5 == 0 & leeftijd >= 18, na.rm=T), 
                              by = .(huishoudnr)]
  
  
  # add the zorgtoeslag/huurtoeslag threshold vars
  dt_thresholds <- fread("data/toeslagen_thresholds.csv")
  
  dt_stapeling_filtered_clean <- merge_with_validate(
    dt_stapeling_filtered_clean,
    dt_thresholds,
    all.x=T,
    validate = "many_to_one",
    require_match = "both",
    verbose = T,
    by = "year"
  )
  
  
  return(dt_stapeling_filtered_clean)
  
}

process_ggz_usage <- function(dt_ggzdeclvektis, dt_ggzzpm, dt_huisarts) {
  # @outcome OT_HHKIND, OT_OUD

  # first, process dt_ggzdeclvektis
  # transform date to year
  dt_ggzdeclvektis[, ':='(
    beginjaar = substr(begindatum_prestatie, 1, 4),
    eindjaar = substr(einddatum_prestatie, 1, 4)
  )][, c("begindatum_prestatie", "einddatum_prestatie") := NULL]

  # we first expand, to get all possible years
  dt_ggzdeclvektis <- dt_ggzdeclvektis[, .(year = beginjaar:eindjaar), 
                                       by = .(rinpersoon, productcode, beginjaar, eindjaar)]
  
  
  dt_ggzdeclvektis[, ':='(
    is_spec_ggz = as.integer(productcode %in% 20:21),
    is_basis_ggz = as.integer(productcode %in% c(30, 80))
  )]
  
  # define usage by year
  dt_ggzdeclvektis <- dt_ggzdeclvektis[, .(
    uses_spec_ggz = as.integer(any(is_spec_ggz == 1, na.rm=T)),
    uses_basis_ggz = as.integer(any(is_basis_ggz == 1, na.rm=T))
  ), by = .(rinpersoon, year)]
  
  ## secondly, process dt_ggzzpm
  dt_ggzzpm[, ':='(
    is_spec_ggz = as.integer(substr(zpmdiagnose, 1, 2) == "SG"),
    is_basis_ggz = as.integer(substr(zpmdiagnose, 1, 2) == "BG")
  )]  
  
  # define usage by year
  dt_ggzzpm <- dt_ggzzpm[, .(
    uses_spec_ggz = as.integer(any(is_spec_ggz == 1, na.rm=T)),
    uses_basis_ggz = as.integer(any(is_basis_ggz == 1, na.rm=T))
  ), by = .(rinpersoon, year)]
  
  
  ## finally, bind/merge all the datasets
  dt_ggz_usage <- rbindlist(list(dt_ggzzpm, dt_ggzdeclvektis))
  setorder(dt_ggz_usage, rinpersoon, year)
  to_num(dt_ggz_usage, "year")
  
  # fill NAs
  dt_ggz_usage[is.na(uses_spec_ggz), uses_spec_ggz := 0]
  dt_ggz_usage[is.na(uses_basis_ggz), uses_basis_ggz := 0]
  
  return(dt_ggz_usage)
  
}

process_kindouder <- function(dt_kindouder, dt_rins, dt_gbapersoontab, dt_rins_unsampled) {
  
  # Filter gbapersoontab for children
  dt_gbapersoontab <- dt_gbapersoontab[rinpersoon %in% unique(dt_kindouder$rinpersoon)]
  
  # first, merge age into kindouder
  dt_kindouder <- merge_with_validate(
    dt_kindouder, 
    dt_gbapersoontab[, .(rinpersoon, gbageboortejaar)],
    by = "rinpersoon",
    validate = "one_to_one"
  )
  
  # create year-based dt_kindouder, based on geboortedatum
  dt_kindouder_rins <- unique(dt_kindouder$rinpersoon)
  dt_grid <- as.data.table(CJ(year = base_years, rinpersoon = dt_kindouder_rins))
  
  dt_kindouder_years <- merge_with_validate(
    dt_grid,
    dt_kindouder,
    by = "rinpersoon",
    validate = "many_to_one",
    require_match = "both"
  )
  
  # now filter for only where born in year or before
  dt_kindouder_years <- dt_kindouder_years[gbageboortejaar <= year]
  
  # create var for is_ouder
  for (yr in base_years) {
    dt_kindouder_yr <- dt_kindouder_years[year == yr]
    
    rin_set_yr <- unique(dt_rins_unsampled[year == yr]$rinpersoon)
    ouder_set_yr <- union(unique(dt_kindouder_yr$rinpersoonma), unique(dt_kindouder_yr$rinpersoonpa))
    children_set_yr <- unique(dt_kindouder_yr$rinpersoon)
    
    children_in_stapeling_yr <- intersect(rin_set_yr, children_set_yr)
    parents_with_children_in_stapeling_yr <- union(
      unique(dt_kindouder_yr[rinpersoon %in% rin_set_yr]$rinpersoonma),
      unique(dt_kindouder_yr[rinpersoon %in% rin_set_yr]$rinpersoonpa)
    )
    
    dt_rins[year == yr, ':='(
      is_ouder = as.integer(rinpersoon %in% ouder_set_yr),
      kind_in_nl = as.integer(rinpersoon %in% parents_with_children_in_stapeling_yr)
      )]
  }
  
  return(dt_rins)
}

add_regional_cols <- function(dt_rins, dt_adresobjectbus, dt_vslgwbtab) {
  # @outcome OT_HHKIND, OT_OUD

  # merge vsl with adres
  dt_adresobjectbus <- merge_with_validate(
    dt_adresobjectbus,
    dt_vslgwbtab,
    by = "rinobjectnummer",
    require_match = "left",
    validate = "many_to_one",
    verbose = TRUE
  )
   
  # overlap with rinpersonen, take the address that is present at the end of the year of stapeling minus 1
  dt_rins[,year_start := as.numeric(paste0(year - 1, "1231"))]
  dt_rins[,year_end := as.numeric(paste0(year - 1, "1231"))]

  setorder(dt_adresobjectbus, "gbadatumaanvangadreshouding")
  
  setkey(dt_rins, rinpersoon, year_start, year_end)
  setkey(dt_adresobjectbus, rinpersoon, gbadatumaanvangadreshouding, gbadatumeindeadreshouding)
  
  dt_rins_with_regions <- foverlaps(
    dt_rins,
    dt_adresobjectbus,
    type = "any",
    mult = "last"
  )
  
  # for people who for some reason don't have an entry at the end of the year, overlap for the whole year, and take the last overlap
  # split the dt for NA and non-NA
  dt_rins_with_regions_na <- dt_rins_with_regions[is.na(bc)]
  dt_rins_with_regions <- dt_rins_with_regions[!is.na(bc)]
  
  dt_rins_with_regions_na[,year_start := as.numeric(paste0(year - 1, "0101"))]
  dt_rins_with_regions_na[,year_end := as.numeric(paste0(year - 1, "1231"))]
  dt_rins_with_regions_na[, c("rinobjectnummer", "gbadatumaanvangadreshouding", 
                              "gbadatumeindeadreshouding", "bc", "wc") := NULL]
  setkey(dt_rins_with_regions_na, rinpersoon, year_start, year_end)
  
  dt_rins_with_regions_na <- foverlaps(
    dt_rins_with_regions_na,
    dt_adresobjectbus,
    type = "any",
    mult = "last"
  )
  
  # bind the two together again
  dt_rins_with_regions <- rbindlist(list(dt_rins_with_regions, dt_rins_with_regions_na))

  # drop cols
  dt_rins_with_regions[, c("rinobjectnummer", "gbadatumaanvangadreshouding", 
                           "gbadatumeindeadreshouding", "year_start", "year_end") := NULL]
  
  ## finally, we create a variable if a person has lived for 10+ years in the same wijk as they live in 2024 
  dt_adresobjectbus <- fast_as_date(dt_adresobjectbus, "gbadatumaanvangadreshouding")
  dt_adresobjectbus <- fast_as_date(dt_adresobjectbus, "gbadatumeindeadreshouding")
  
  dt_year_def <- rbindlist(lapply(base_years, function(yr) {

    dt_wijken_year <- dt_adresobjectbus[
      gbadatumaanvangadreshouding <= as.Date(glue("{yr}-01-01")) & gbadatumeindeadreshouding >= as.Date(glue("{yr}-01-01"))][, .(
        rinpersoon, wc)]
    setnames(dt_wijken_year, "wc", glue("wc_year"))
    
    dt_wijken_year_min10 <- dt_adresobjectbus[
      gbadatumaanvangadreshouding <= as.Date(glue("{yr-10}-01-01")) & gbadatumeindeadreshouding >= as.Date(glue("{yr-10}-01-01"))][, .(
        rinpersoon, wc)]
    setnames(dt_wijken_year_min10, "wc", glue("wc_year_min10"))
    
    # merge the two
    dt_wijken_year <- merge_with_validate(
      dt_wijken_year, 
      dt_wijken_year_min10, 
      validate = "one_to_one", 
      by = "rinpersoon",
      all.x=T
      )
    dt_wijken_year <- dt_wijken_year[, ten_plus_years := as.integer(
      wc_year == wc_year_min10
    )][, .(rinpersoon, ten_plus_years)]
    
    # fill NAs zero (usually means there was no address registered in t-10)
    dt_wijken_year[is.na(ten_plus_years), ten_plus_years := 0]
    dt_wijken_year[, year := yr]
    
    return(dt_wijken_year)
  }))
  
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_year_def,
    validate = "many_to_one",
    all.x=T
  )
  
  
  ## finally, add the stadsdelen & gebieden
  # first, filter for only gemeente amsterdam wijken: this is verified, there are a 
  #lot of wijken with very low counts, outside of ams. Likely some noise with the vsl and adresobjectbus
  dt_rins_with_regions <- dt_rins_with_regions[substr(wc, 1, 4) == "0363"]
  cw_stadsdelen <- format_data(fread("H:/data/crosswalks/INDELING_WIJK_AMS_032026.csv")[, .(
    CBS_Wijkcode, Gebiedcode, Stadsdeel
  )], rin_num = F)
  setnames(cw_stadsdelen, "cbs_wijkcode", "wc")
  
  #remove WK prefix
  cw_stadsdelen[, wc := substr(wc, 3, 9999)]
  
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    cw_stadsdelen,
    validate = "many_to_one",
    # require_match = "left", #checked: all match except the "0363--"
    all.x=T
  )
  
  #add gemeente to aggregate for all ams
  dt_rins_with_regions[, gemeente := "Amsterdam"]
  
  return(dt_rins_with_regions)
}

merge_into_rins <- function(dt_rins_with_regions, dt_stapeling_enriched,
                             dt_huisarts_enriched, dt_kindouder_processed, dt_gbapersoontab,
                             dt_wmobus, dt_indicwlztab, dt_inhatab, dt_ggz_usage,
                            dt_medicijn) {
  # @outcome OT_HHKIND, OT_OUD

  ## 01: clean, process, merge stapeling
  # merge the stapeling into dt_rins
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_stapeling_enriched,
    require_match = "left",
    validate = "one_to_one",
    verbose = TRUE
  )
  
  ## 02: merge & process huisarts
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_huisarts_enriched,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    verbose = TRUE
  )
  
  ## 03: process & merge wmobus
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_wmobus,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    verbose = TRUE,
  )
  
  ## 04: process & merge kindoudertab
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_kindouder_processed,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    require_match = "left",
    verbose = TRUE,
  )
  
  ## 05: process & merge gbapersoontab
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_gbapersoontab[, .SD, .SDcols = c("rinpersoon", "jonge_moeder_geboorte", "jonge_vader_geboorte")],
    by = "rinpersoon",
    all.x=TRUE,
    validate = "many_to_one",
    require_match = "left",
    verbose = TRUE
  )
  
  ## 06: process & merge indicwlztab
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_indicwlztab,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    verbose = TRUE
  )
  
  ## 07: process & merge dt_inhatab
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_inhatab,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    verbose = TRUE
  )
  
  ## 08: process & merge specggz usage
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_ggz_usage,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    verbose = TRUE
  )
  
  ## 09: process & merge dt_medicijn
  dt_rins_with_regions <- merge_with_validate(
    dt_rins_with_regions,
    dt_medicijn,
    all.x=TRUE,
    by = c("rinpersoon", "year"),
    validate = "one_to_one",
    verbose = TRUE
  )
  
  return(dt_rins_with_regions)
}

define_variables_by_rin <- function(dt_rins_merged) {
  # @outcome OT_HHKIND, OT_OUD

  # define some vars
  armoedegrens_percsm <- 130
  
  typehh_partner <- c("Niet-gehuwd paar met kinderen","Gehuwd paar zonder kinderen",
                      "Niet-gehuwd paar zonder kinderen","Gehuwd paar met kinderen")
  
  # Create the variables by person, in two steps to prevent long definition lines
  # @outcome R_OUD1, R_MPG1 (armoede_hh)
  # @outcome R_OUD2 (migratieachtergrond)
  # @outcome R_OUD3, R_MPG8 (burgstaat_change)
  # @outcome R_OUD4, R_MPG4 (eenpersoonshuishouden)
  # @outcome R_OUD5 (kind_in_nl)
  # @outcome R_MPG2 (startkwalificatie)
  # @outcome R_MPG3 (present_in_stapeling_min5)
  # @outcome R_MPG5 (is_werkloze_ouder)
  # @outcome R_MPG6, R_MPG7 (jonge_moeder/vader_geboorte)
  # @outcome R_MPG9 (wanbetaler_zorgverzekering)
  dt_rins_merged[, ':='(
    armoede_hh = as.integer(inharmsoc < armoedegrens_percsm),
    # uses_any_ggz = as.integer(uses_basis_ggz == 1| uses_spec_ggz == 1 | uses_poh_ggz == 1),
    # veelvuldig_ha_gebruik = as.integer(n_huisarts_visits >= 15),
    # recht_huurtoeslag_proxy_hh = as.integer(
    #   (typehh %chin% typehh_partner & woonsituatie == "Huurwoning zonder huurtoeslag" & vermogenhhexcl <= vermogensgrens_met_toeslagpartner_ht) |
    #     (!typehh %chin% typehh_partner & woonsituatie == "Huurwoning zonder huurtoeslag" & vermogenhhexcl <= vermogensgrens_met_toeslagpartner_ht) # TODO: dit moet zonder zijn
    # ),
    # recht_zorgtoeslag_proxy_hh = as.integer(
    #   (typehh %chin% typehh_partner & vermogenhhexcl <= vermogensgrens_met_toeslagpartner_zt & inhbrutinkh <= inkomensgrens_met_toeslagpartner_zt) |
    #     (!typehh %chin% typehh_partner & vermogenhhexcl <= vermogensgrens_alleenstaand_zt & inhbrutinkh <= inkomensgrens_alleenstaand_zt)
    # ),
    is_child = as.integer(leeftijd <= max_age_children),
    is_werkloze_ouder = as.integer(!belanginkbronpers %in% c("Werknemer", "Directeur-grootaandeelhouder", "Zelfstandig ondernemer", "Ontvanger pensioenuitkering", "Overige zelfstandige") & is_ouder == 1)
  )]
  
  dt_rins_merged[, ':='(
    # V1_afdoening = as.integer(afdoening_om == 1 | afdoening_rechter ==1),
    # V2_armoede_hh = armoede_hh,
    # V3_basis_poh_ggz = as.integer(uses_poh_ggz == 1 | uses_basis_ggz == 1),
    # V4_chronische_ziekte = has_chronische_ziekte,
    # V5_gebruikt_huurtoeslag = huurtoeslag,
    # V6_gebruikt_zorgtoeslag = zorgtoeslag,
    # V7_geen_startkwalificatie_ouder = as.integer(startkwalificatie == 0 & is_ouder == 1),
    # V8_gemist_huurtoeslag = as.integer(huurtoeslag == 0 & recht_huurtoeslag_proxy_hh == 1),
    # V9_gemist_zorgtoeslag = as.integer(zorgtoeslag == 0 & recht_zorgtoeslag_proxy_hh == 1),
    # V10_bijstand = bijstand,
    # V11_lang_werkloosheid = as.integer(werknemer == 0 & zelfstandig_ondernemer_met_personeel == 0 & zelfstandig_ondernemer_zonder_personeel == 0), #TODO: add typeonderwijs
    # V12_recht_huurtoeslag_proxy_hh = recht_huurtoeslag_proxy_hh,
    # V13_recht_zorgtoeslag_proxy_hh = recht_zorgtoeslag_proxy_hh,
    # V14_schulden_hh = smalle_schuld_huishouden,
    # V15_spec_ggz = uses_spec_ggz,
    # V16_veelvuldig_ha = veelvuldig_ha_gebruik,
    # V17_armoede_ggz = as.integer(armoede_hh == 1 & uses_any_ggz == 1),
    # V18_wmo_gebruik = uses_wmo,
    # V19_schulden_ggz = as.integer(smalle_schuld == 1 & uses_any_ggz == 1),
    # V20_chronische_aandoening_ggz = as.integer(has_chronische_ziekte == 1 & uses_any_ggz == 1),
    # V21_eenoudergezin_laagink = as.integer(eenoudergezin == 1 & armoede_hh == 1), # TODO: change according to discussed definition
    # V22_geenstart_bijstand = as.integer(startkwalificatie == 0 & is_ouder == 1 & bijstand == 1),
    # V23_veelha_bijstand = as.integer(veelvuldig_ha_gebruik == 1 & bijstand == 1),
    # V24_veelha_schulden = as.integer(veelvuldig_ha_gebruik == 1 & smalle_schuld == 1)
    # @outcome R_OUD1, R_OUD2, R_OUD3, R_OUD4, R_OUD5
    R_OUD1_armoede = armoede_hh,
    R_OUD2_migratieachtergrond = as.integer(herkomst3 != "Nederlandse herkomst"),
    R_OUD3_hhwijziging = burgstaat_change,
    R_OUD4_alleenwonend = as.integer(typehh == "Eenpersoonshuishouden"),
    R_OUD5_geenkind = as.integer(kind_in_nl == 0),
    # @outcome O_OUD.1.1, O_OUD.1.2, O_OUD.1.3, O_OUD.2.1, O_OUD.2.2, O_OUD.3.1, O_OUD.3.2
    O_OUD11_wlz = uses_wlz,
    O_OUD12_wmo = uses_wmo,
    O_OUD13_wvp = uses_wvp,
    O_OUD21_sggz = uses_spec_ggz,
    O_OUD22_psychofarma = medicijn_psychofarmaca,
    O_OUD31_bijzbijstand = bijzondere_bijstand,
    O_OUD32_wsnp = wsnp
  )]
  
  # create total scores
  scoring_cols <- list(
    "R_OUD" = grep("^R_OUD", names(dt_rins_merged), value=T),
    "O_OUD1" = grep("^O_OUD1", names(dt_rins_merged), value=T),
    "O_OUD2" = grep("^O_OUD2", names(dt_rins_merged), value=T),
    "O_OUD3" = grep("^O_OUD3", names(dt_rins_merged), value=T)
  )
  
  for (score_letter in names(scoring_cols)) {
    scoring_cols_letter <- scoring_cols[[score_letter]]
    total_score_col_name <- paste0(score_letter, "_totaal")
    

    #fill NAs with zeroes
    for (col in scoring_cols_letter) {
      dt_rins_merged[is.na(get(col)), (col) := 0]
    }
    
    dt_rins_merged[, (total_score_col_name) := rowSums(.SD, na.rm=T), 
                             .SDcols = scoring_cols_letter]
    
    # fill NA with zeroes
    dt_rins_merged[is.na(get(total_score_col_name)), (total_score_col_name) := 0]
  }
  
  # turn the R_totaal col into buckets
  dt_rins_merged[, R_OUD_totaal := fcase(
    R_OUD_totaal == 0, "0",
    R_OUD_totaal == 1, "1",
    R_OUD_totaal == 2, "2",
    R_OUD_totaal >= 3, "3plus"
  )]
  
  return(dt_rins_merged)
}

aggregate_to_huishoudens <- function(dt_rins_with_vars) {
  # @outcome OT_HHKIND

  # finally, we aggregate by huishouden
  dt_huishoudens_with_vars <- dt_rins_with_vars[, .(
    # Z1_jeugdhulp_gebruik = as.integer(any(gebruikt_jeugdhulp == 1, na.rm=T)),
    # Z2_wmo_gebruik = as.integer(any(uses_wmo == 1, na.rm=T)),
    # Z3_geen_kinderopvang = as.integer(any(kinderopvangtoeslag == 0), na.rm=T),
    # # 
    # R1_armoede = as.integer(any(V2_armoede_hh, na.rm=T)),
    # R2_laagopl_ouders = as.integer(any(V7_geen_startkwalificatie_ouder), na.rm=T),
    # R3_nieuwkomer_nl = as.integer(any(nieuwkomer_in_hh == 1 & is_ouder == 1, na.rm=T)),
    # R4_eenoudergezin = as.integer(any(eenoudergezin == 1, na.rm=T)),
    # R5_werkloosheid = as.integer(any(!werknemer == 1 & !zelfstandig_ondernemer_met_personeel == 1 & ! zelfstandig_ondernemer_zonder_personeel == 1 & is_ouder == 1)),
    # R6_kind_met_jonge_moeder = as.integer(any(jonge_moeder_geboorte & is_child == 1, na.rm=T)),
    # R7_kind_met_jonge_vader = as.integer(any(jonge_vader_geboorte & is_child == 1, na.rm=T)),
    # R8_ggz_gebruik = as.integer(any(uses_any_ggz == 1, na.rm=T)),
    # R9_veranderingen_hh = as.integer(any(burgstaat_change == 1, na.rm=T)),

    n_kinderen_hh = sum(leeftijd < 18, na.rm=T),
    n_kinderen_0tot2_hh = sum(leeftijd %in% 0:1, na.rm=T),
    n_kinderen_2tot4_hh = sum(leeftijd %in% 2:3, na.rm=T),
    n_kinderen_4tot12_hh = sum(leeftijd %in% 4:11, na.rm=T),
    n_kinderen_12tot18_hh = sum(leeftijd %in% 12:17, na.rm=T),

    # @outcome R_MPG1, R_MPG2, R_MPG3, R_MPG4, R_MPG5, R_MPG6, R_MPG7, R_MPG8, R_MPG9
    R_MPG1_armoede_hh = as.integer(any(armoede_hh == 1), na.rm=T),
    R_MPG2_laagopl_hh = as.integer(any(is_ouder == 1 & startkwalificatie == 0)),
    R_MPG3_nieuwenederlander_hh = as.integer(any(is_ouder == 1 & present_in_stapeling_min5 == 0)),
    R_MPG4_eenoudergezin = as.integer(any(typehh == "Eenouderhuishouden")),
    R_MPG5_werkloosheid_hh = as.integer(any(is_werkloze_ouder == 1, na.rm=T)),
    R_MPG6_kind_met_jonge_moeder_hh = as.integer(any(jonge_moeder_geboorte & is_child == 1, na.rm=T)),
    R_MPG7_kind_met_jonge_vader_hh = as.integer(any(jonge_vader_geboorte & is_child == 1, na.rm=T)),
    R_MPG8_veranderingen_hh = as.integer(any(burgstaat_change == 1, na.rm=T)),
    R_MPG9_wanbet_zv_hh = as.integer(any(wanbetaler_zorgverzekering == 1, na.rm=T)), # TODO: add this var
    # @outcome O_MPG1.1, O_MPG1.2, O_MPG1.3, O_MPG2.1, O_MPG2.2, O_MPG2.3, O_MPG3.1, O_MPG3.2, O_MPG3.3
    O_MPG11_jhzambulant_hh = as.integer(any(jhzambulant == 1, na.rm=T)),
    O_MPG12_jhzverblijf_hh = as.integer(any(jhmgesloten == 1 | jhmgezin == 1 | jhmov == 1 | jhmpleeg == 1, na.rm=T)),
    O_MPG13_jhzbescherming_hh = as.integer(any(jbots == 1 | jbvoogdij == 1, na.rm=T)),
    O_MPG21_sggz_hh = as.integer(any(uses_spec_ggz == 1, na.rm=T)),
    O_MPG22_wmo_hh = as.integer(any(uses_wmo == 1, na.rm=T)),
    O_MPG23_medverslaaf_hh = as.integer(any(medicijn_verslaving == 1, na.rm=T)),
    O_MPG31_combination_hulp_hh = as.integer(any(bijstand == 1 | ww == 1 | ao == 1, na.rm=T)),
    O_MPG32_wsnp_hh = as.integer(any(wsnp == 1, na.rm=T)),
    O_MPG33_ziektewet_hh = as.integer(any(ziektewet == 1, na.rm=T)),
    
    # the split variables
    kinderopvangtoeslag_hh = as.integer(any(kinderopvangtoeslag == 1, na.rm=T)),
    migratieachtergrond_hh = as.integer(any(herkomst3 != "Nederlandse herkomst", na.rm=T)),
    langwonende_hh = as.integer(any(ten_plus_years == 1, na.rm=T))
    
    ), by = .(year, huishoudnr, bc, wc, gebiedcode, stadsdeel, gemeente)]
  
  # create total scores
  scoring_cols <- list(
    "R_MPG" = grep("^R_MPG", names(dt_huishoudens_with_vars), value=T),
    "O_MPG1" = grep("^O_MPG1", names(dt_huishoudens_with_vars), value=T),
    "O_MPG2" = grep("^O_MPG2", names(dt_huishoudens_with_vars), value=T),
    "O_MPG3" = grep("^O_MPG3", names(dt_huishoudens_with_vars), value=T)
  )
  
  for (score_letter in names(scoring_cols)) {
    scoring_cols_letter <- scoring_cols[[score_letter]]
    total_score_col_name <- paste0(score_letter, "_totaal")
    
    #fill NAs with zeroes
    for (col in scoring_cols_letter) {
      dt_huishoudens_with_vars[is.na(get(col)), (col) := 0]
    }
    
    
    dt_huishoudens_with_vars[, (total_score_col_name) := rowSums(.SD, na.rm=T), 
                              .SDcols = scoring_cols_letter]
  }
  
  # turn the R_totaal col into buckets
  dt_huishoudens_with_vars[, R_MPG_totaal := fcase(
    R_MPG_totaal == 0, "0",
    R_MPG_totaal == 1, "1",
    R_MPG_totaal == 2, "2",
    R_MPG_totaal >= 3, "3plus"
  )]
  
  return(dt_huishoudens_with_vars)
}

