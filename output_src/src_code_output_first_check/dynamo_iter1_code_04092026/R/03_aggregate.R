aggregate_OT_HHKIND <- function(dt_huishoudens_with_vars) {
  # @outcome OT_HHKIND

  # for this output table, our population is huishoudens with children.
  dt_huishoudens_with_vars <- dt_huishoudens_with_vars[n_kinderen_hh > 0]
  
  score_cols_to_agg <- grep("^R_MPG", names(dt_huishoudens_with_vars), value=T)
  
  # fix some types before melting/aggregating
  score_cols_to_agg_numeric <- setdiff(score_cols_to_agg, "R_MPG_totaal")
  dt_huishoudens_with_vars[, (score_cols_to_agg_numeric):= lapply(.SD, as.numeric), .SDcols = score_cols_to_agg_numeric]
  
  # create the cols that categorize into the ondersteunings categories
  O_MPG_cols <- c("O_MPG1_totaal", "O_MPG2_totaal", "O_MPG3_totaal")
  O_MPG_labels <- c("O_MPG1", "O_MPG2", "O_MPG3")
  
  dt_huishoudens_with_vars[, O_MPG_combination := apply(.SD > 0, 1, function(active) {
    if (!any(active)) "none"else paste(O_MPG_labels[active], collapse = " + ")
  }), .SDcols = O_MPG_cols]
  
  split_vars_OT_HHKIND <- union(split_vars_OT_HHKIND, "O_MPG_combination")
  
  aggregation_levels = c("wc", "bc", "stadsdeel", "gebiedcode", "gemeente")
  
  dt_scores <- rbindlist(lapply(aggregation_levels, function(agg_level) {
    
    # first melt, then aggregate
    dt_long <- melt(
      dt_huishoudens_with_vars,
      id.vars = c("huishoudnr", "n_kinderen_hh", "n_kinderen_0tot2_hh", 
                  "n_kinderen_2tot4_hh", "n_kinderen_4tot12_hh", "n_kinderen_12tot18_hh", 
                  agg_level, "year", split_vars_OT_HHKIND),
      measure.vars = score_cols_to_agg,
      variable.name = "variable_name", 
      value.name = "variable_value"
    )
    
    # aggregate, and add percentage within region vars
    # first create the n_totaal var, this shouldn't be grouped by variable value
    dt_long[, n_totaal_population_in_region := fndistinct(huishoudnr), 
            by = c(agg_level, "year")]
    
    # then we aggregate and split
    dt_long_summary_split <- rbindlist(lapply(c(split_vars_OT_HHKIND, "no_split"), function(split_var) {
      print(split_var)
      by = c(agg_level, "year", "variable_name", "variable_value", "n_totaal_population_in_region")
      if (split_var != "no_split") by <- union(by, split_var)
      
      
      dt_long_summary <- dt_long[, .(
        n_households = fndistinct(huishoudnr),
        n_kinderen_hh = sum(n_kinderen_hh, na.rm=T),
        n_kinderen_0tot2_hh = sum(n_kinderen_0tot2_hh, na.rm=T),
        n_kinderen_2tot4_hh = sum(n_kinderen_2tot4_hh, na.rm=T),
        n_kinderen_4tot12_hh = sum(n_kinderen_4tot12_hh, na.rm=T),
        n_kinderen_12tot18_hh = sum(n_kinderen_12tot18_hh, na.rm=T)
      ), by = by]
      
      # melt again
      dt_long_summary_melt <- melt(
        dt_long_summary,
        measure.vars = c(
          "n_households", 
          "n_kinderen_hh",
          "n_kinderen_0tot2_hh",
          "n_kinderen_2tot4_hh",
          "n_kinderen_4tot12_hh",
          "n_kinderen_12tot18_hh"
        ),
        variable.name = "metric_name",
        value.name = "metric_value"
      )
      
      return(dt_long_summary_melt)

    }), use.names=T, fill=T)
    
    # fill the splits variable columns with "all" where NA
    dt_long_summary_split[, (split_vars_OT_HHKIND) := lapply(.SD, function(x) fifelse(is.na(x), "all", as.character(x))),
                 .SDcols = split_vars_OT_HHKIND]
    

    dt_long_summary_split[, region_agg_level := agg_level]
    setnames(dt_long_summary_split, agg_level, "region_code")
    
    setorder(dt_long_summary_split, region_code, -year, variable_name, metric_name, variable_value)
    return(dt_long_summary_split)
    
  }))
  
  # clarify population
  dt_scores[, population:= "huishoudens_met_kinderen"]

  # save intermediate excel
  save_processed(dt_scores, "OT_HHKIND_aggregations_huishoudens", ".csv")

  return(dt_scores)
}

aggregate_OT_OUD <- function(dt_rins_with_vars) {
  # @outcome OT_OUD

  # our population for this table is ouderen (65+), let's filter
  dt_rins_with_vars <- dt_rins_with_vars[leeftijd >= 65]
  
  region_levels = c("wc", "bc", "stadsdeel", "gebiedcode", "gemeente")
  R_cols_to_agg <- sort(grep("^R_OUD", names(dt_rins_with_vars), value=T))
  O_cols_to_groupby <- sort(grep("^O_OUD", names(dt_rins_with_vars), value=T))
  
  # create the cols that categorize into the ondersteunings categories
  O_OUD_cols <- c("O_OUD1_totaal", "O_OUD2_totaal", "O_OUD3_totaal")
  O_OUD_labels <- c("O_OUD1", "O_OUD2", "O_OUD3")
  
  dt_rins_with_vars[, O_OUD_combination := apply(.SD > 0, 1, function(active) {
    if (!any(active)) "none" else paste(O_OUD_labels[active], collapse = " + ")
  }), .SDcols = O_OUD_cols]
  
  split_vars_OT_OUD <- union(split_vars_OT_OUD, "O_OUD_combination")
  
  # filter only the relevant vars, to save RAM
  dt_rins_with_vars <- dt_rins_with_vars[, .SD, .SDcols = c(
    "rinpersoon", region_levels, split_vars_OT_OUD, "year", R_cols_to_agg
  )]
  gc()
  
  # fix some types before melting/aggregating
  R_cols_to_agg_numeric <- setdiff(R_cols_to_agg, "R_OUD_totaal")
  dt_rins_with_vars[, (R_cols_to_agg_numeric):= lapply(.SD, as.numeric), .SDcols = R_cols_to_agg_numeric]
  
  ## finally, aggregate
  dt_aggregated <- rbindlist(lapply(region_levels, function(region_level) {
    
    # first melt, then aggregate
    dt_long <- melt(
      dt_rins_with_vars,
      id.vars = c("rinpersoon", region_level, "year", split_vars_OT_OUD),
      measure.vars = R_cols_to_agg,
      variable.name = "variable_name", 
      value.name = "variable_value"
    )
    
    # now, we aggregate
    dt_agg_level <- rbindlist(lapply(c(split_vars_OT_OUD, "no_split"), function(split_var){
      
      print(split_var)

      # create n_totaal col first
      dt_long[, n_totaal_population_in_region := fndistinct(rinpersoon), by = c("year",region_level)]
      
      by = c(region_level, "year", "variable_name", "variable_value", "n_totaal_population_in_region")

      if (split_var != "no_split") by <- union(by, split_var)
      
      dt_agg <- dt_long[, .(
        n_ouderen_with_var_value = fndistinct(rinpersoon)
      ), by = by]

      # melt again
      dt_long_agg <- melt(
        dt_agg,
        measure.vars = c(
          "n_ouderen_with_var_value"        
          ),
        variable.name = "metric_name",
        value.name = "metric_value"
      )
      
      return(dt_long_agg)
    }), fill = TRUE, use.names=T)
    
    # fill the splits variable columns with "all"
    dt_agg_level[, (split_vars_OT_OUD) := lapply(.SD, function(x) fifelse(is.na(x), "all", x)),
                                         .SDcols = split_vars_OT_OUD]
    
    
    # adjust column naming for regions
    dt_agg_level[, region_agg_level := region_level]
    setnames(dt_agg_level, region_level, "region_code")
    setorder(dt_agg_level, region_code, -year, variable_name)
    
  }))
  
  # clarify population
  dt_aggregated[, population:= "ouderen (65+)"]
  
  save_processed(dt_aggregated, "OT_OUD_aggregations_rins", ".csv")
  
  return(dt_aggregated)
}


