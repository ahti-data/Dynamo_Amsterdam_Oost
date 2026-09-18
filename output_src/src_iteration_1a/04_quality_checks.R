perform_external_checks_statline <- function(dt_huishoudens_with_vars, dt_agg_OT_HHKIND, dt_rins_agg_OT_OUD) {
  # @outcome OT_HHKIND, OT_OUD

  # first, load in the quality checks sheets
  dt_statline_checks <- format_data(fread("data/quality_checks/qualitychecks_wijkenbuurten_2023.csv"), rin_num=F)
  
  # clean the external data to fit our data
  dt_statline_checks[, c("regio_naam") := NULL]
  
  dt_statline_checks[, region_code := fifelse(
    substr(region_code, 1, 2) %in% c("BU", "WK"),
    substr(region_code, 3, 999),
    region_code
  )]
  
  setnames(dt_statline_checks, "region_type", "region_agg_level")

  dt_statline_checks[, region_agg_level := fcase(
    region_agg_level == "Wijk", "wc",
    region_agg_level == "Buurt", "bc"
  )]
  
  dt_statline_checks <- dt_statline_checks[region_agg_level %in% c("wc", "bc")]
  col_dict_vars <- list(
    "n_huishoudens_totaal" = "n_huishoudens_totaal",
    "bevolking|particuliere huishoudens|eenpersoonshuishoudens" = "n_huishoudens_eenpersoons",
    "bevolking|particuliere huishoudens|huishoudens zonder kinderen" = "n_huishoudens_zonder_kind",
    "bevolking|particuliere huishoudens|huishoudens met kinderen" = "n_huishoudens_met_kind",
    "zorg|jongeren met jeugdzorg in natura" = "n_jongeren_met_jeugdzorg",
    "zorg|percentage jongeren met jeugdzorg" = "perc_jongeren_met_jeugdzorg",
    "zorg|wmo-cliënten" = "n_wmo_clienten",
    "zorg|wmo-cliënten relatief"= "n_wmo_clienten_relatief"
  )
  for (col in names(col_dict_vars)) setnames(dt_statline_checks, col, col_dict_vars[[col]])
  
  # melt the statline table
  dt_statline_checks <- melt(
    dt_statline_checks, 
    variable.names = names(col_dict_vars),
    id.vars = c("region_agg_level", "region_code")
    )[, year := 2023]
  
  dt_agg_check_hh <- dt_rins_with_vars[, .(
    eenpersoonshuishouden = as.integer(any(typehh == "Eenpersoonshuishouden", na.rm=T)),
    huishouden_zonder_kind = as.integer(any(aantkindhh == 0), na.rm=T),
    huishouden_met_kind = as.integer(any(aantkindhh > 0, na.rm=T))
  ), by = .(huishoudnr, bc, wc, year)]
  
  # melt
  region_levels <- c("wc", "bc")
  dt_agg_check_hh <- rbindlist(lapply(region_levels, function(region_level) {
    dt_agg_check_hh_region_level <- dt_agg_check_hh[, .(
      n_huishoudens_totaal = .N,
      n_huishoudens_eenpersoons = sum(eenpersoonshuishouden == 1, na.rm=T),
      n_huishoudens_zonder_kind = sum(huishouden_zonder_kind == 1 & eenpersoonshuishouden == 0, na.rm=T),
      n_huishoudens_met_kind = sum(huishouden_met_kind == 1, na.rm=T)
    ), by = c(region_level, "year")]
    
    setnames(dt_agg_check_hh_region_level, region_level, "region_code")
    dt_agg_check_hh_region_level[, region_agg_level := region_level]
    
  }))
  
  dt_agg_check_hh <- melt(
    dt_agg_check_hh, 
    measure.vars = c("n_huishoudens_totaal", "n_huishoudens_eenpersoons", "n_huishoudens_zonder_kind", "n_huishoudens_met_kind")
    )
  setnames(dt_agg_check_hh, "value", "value_internal")
  
  
  # now, we merge
  dt_statline_checks_merged <- merge_with_validate(
    dt_statline_checks,
    dt_agg_check_hh,
    all.x=T
    # validate = "one_to_one"
  )
  dt_statline_checks_merged <- dt_statline_checks_merged[!is.na(value_internal)]
  dt_statline_checks_merged[, ':='(
    abs_diff = value - value_internal,
    rel_diff = value / value_internal - 1
  )]
  
}


perform_external_checks_OS <- function(dt_rins_with_vars, dt_agg_OT_OUD) {
  # @outcome OT_OUD

  # first, load in the quality checks sheets
  dt_OS_checks <- format_data(openxlsx2::read_xlsx("data/quality_checks/externe_checks_OSams.xlsx"), rin_num=F)

  # drop the NL col
  dt_OS_checks[, `nederland (in december voorgaande jaar)` := NULL]
  # melt for same format
  
  dt_OS_checks <- melt(
    dt_OS_checks, 
    measure.vars= c("amsterdam", "amsterdam-oost"),
    variable.name = "region"
    )
  
  dt_OS_checks[, variable := fcase(
    variable == 'Bijstand', 'bijstand',
    variable == 'Lage inkomens <130% sm', 'armoede_hh',
    variable == 'Wmo: beschermd wonen en verblijf 18-65-jarigen', '',
    variable == 'Wmo: beschermd wonen en verblijf 65+', '',
    variable == 'WMO: dagbesteding (18-65)', '',
    variable == 'WMO: dagbesteding (65+)', '',
    variable == 'WMO: hulp bij huishouding (18-65)', '',
    variable == 'WMO: hulp bij huishouding (65+)', '',
    variable == 'Wmo: voorzieningen gebruik (18-65)', '',
    variable == 'WMO: voorziengen gebruik 66+', '',
    variable == 'Bevolking 0-3 jarigen', 'n_totaal',
    variable == 'Geregistreerde werkloosheid (18-67)', ''
  )]
  
  # create new leeftijd_cat based on OS
  dt_rins_with_vars [, leeftijd_cat := fcase(
    leeftijd %in% 0:3, "0-3",
    leeftijd %in% 18:65, "18-65",
    leeftijd > 65, "65plus"
  )]
  
  # make the similar categories in OS the same
  dt_OS_checks[leeftijd_cat == "66plus", leeftijd_cat := "65_plus"]
  dt_OS_checks[leeftijd_cat == "18-67", leeftijd_cat := "18-65"]
  
  
  region_agg_levels = c("amsterdam", "amsterdam-oost")
  
  split_vars <- c("leeftijd_cat", "all")
  
  dt_rins_agg_split <- rbindlist(lapply(split_vars, function(split_var) {
    if (split_var == "all") by = c("year") else by = c("year", split_var)
    
    dt_rins_agg <- rbindlist(lapply(region_agg_levels, function(region_level) {
      if(region_level == "amsterdam") dt_rins_agg_level <- dt_rins_with_vars else dt_rins_agg_level <- dt_rins_with_vars[stadsdeel == "Oost"]
      dt_rins_agg_level <- dt_rins_agg_level[, .(
        bijstand = sum(bijstand == 1, na.rm=T),
        armoede_hh = sum(armoede_hh ==1, na.rm=T),
        n_totaal = .N
      ), by = by]
      
      dt_rins_agg_level[, region:= region_level]
      
      return(dt_rins_agg_level)
    }))
    
    return(dt_rins_agg)
    
  }), use.names=T, fill=T)
  
  # fill NA with all for split vars
  for (split_var in setdiff(split_vars, "all")) {
    na_rows <- is.na(dt_rins_agg_split[[split_var]])
    dt_rins_agg_split[na_rows, (split_var) := "all"]
  }
  
  
  dt_rins_agg_split <- melt(dt_rins_agg_split, measure.vars = c("bijstand", "armoede_hh", "n_totaal"))
  setnames(dt_rins_agg_split, "value", "value_internal")
  
  # finally, merge
  dt_OS_checks_merged <- merge_with_validate(
    dt_OS_checks,
    dt_rins_agg_split,
    all.x=T,
    by = c("year", "variable", "leeftijd_cat", "region"),
    verbose=T
  )
  
  dt_OS_checks_merged <- dt_OS_checks_merged[!is.na(value_internal)]
  dt_OS_checks_merged[, ':='(
    abs_diff = value - value_internal,
    rel_diff = value / value_internal - 1
  )]
  
  
}