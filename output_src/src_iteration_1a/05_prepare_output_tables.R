prepare_output_table_OT_OUD <- function(dt_agg_OT_OUD) {
  # @outcome OT_OUD

  cols_to_mask<- c("metric_value", "n_totaal_population_in_region")
  
  cat(paste("nrows dt_agg_OT_OUD BEFORE removing below 10:", nrow(dt_agg_OT_OUD)))
  
  for (col in cols_to_mask) {
    # first: remove rows with value < 10
    dt_agg_OT_OUD <- dt_agg_OT_OUD[get(col) >= 10]
    
    ## then: round to 10
    dt_agg_OT_OUD[, metric_value := round(metric_value, digits = -1)]
  }
  cat(paste("nrows dt_agg_OT_OUD AFTER removing below 10:", nrow(dt_agg_OT_OUD)))
  
  save_output(dt_agg_OT_OUD, "OT_OUD")
  
  return(dt_agg_OT_OUD)
}

prepare_output_table_OT_HHKIND <- function(dt_agg_OT_HHKIND) {
  # @outcome OT_HHKIND

  cols_to_mask<- c("metric_value", "n_totaal_population_in_region")
  
  cat(paste("nrows dt_agg_OT_HHKIND BEFORE removing below 10:", nrow(dt_agg_OT_HHKIND)))
  
  for (col in cols_to_mask) {
    # first: remove rows with value < 10
    dt_agg_OT_HHKIND <- dt_agg_OT_HHKIND[get(col) >= 10]
    
    ## then: round to 10
    dt_agg_OT_HHKIND[, metric_value := round(metric_value, digits = -1)]
  }
  cat(paste("nrows dt_agg_OT_HHKIND AFTER removing below 10:", nrow(dt_agg_OT_HHKIND)))
  
  save_output(dt_agg_OT_HHKIND, "OT_HHKIND")
  
  return(dt_agg_OT_HHKIND)
}