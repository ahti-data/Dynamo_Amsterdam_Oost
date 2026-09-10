#### targets options ####
library(targets)

tar_option_set(
  packages = c(
    "data.table", 
    "glue", 
    "dplyr",
    "tarchetypes",
    "ggplot2",
    "sf",
    "collapse"
    ),
  workspace_on_error = TRUE
)

tar_source()

#### main pipeline ####
list(
  ## cleaning targets ##
  tar_target(
    name = dt_rins,
    command = get_base_population(
      base_years, 
      use_sample = use_sample
      ),
    description = "load and filter demog"
  ),
  tar_target( # necessary for some operations, also when sampling
    name = dt_rins_unsampled,
    command = get_base_population(
      base_years, 
      use_sample = FALSE
    ),
    description = "load and filter rinset"
  ),
  
  tar_target(
    name = dt_stapeling_filtered_clean,
    command = load_filter_clean_stapeling(dt_rins),
    description = "load, filter and clean the dataset for stapeling"
  ),
  tar_target(
    name = dt_kindouder,
    command = load_filter_kindoudertab(dt_rins)
    ),
  tar_target(
    name = dt_zvw,
    command = load_filter_clean_zvw(dt_rins, cols_to_load_zvw)
  ),
  tar_target(
    name = dt_wmobus,
    command = load_filter_clean_wmobus(dt_rins)
  ),
  tar_target(
    name = dt_gbapersoontab,
    command = load_filter_clean_gbapersoontab(cols_to_load_gbapersoontab)
  ),
  tar_target(
    name = dt_indicwlztab, 
    command = load_filter_clean_indicwlztab(dt_rins)
  ),
  tar_target(
    name = dt_adresobjectbus,
    command = load_filter_clean_adresobjectbus(dt_rins)
  ),
  tar_target(
    name = dt_vslgwbtab,
    command = load_filter_clean_vslgwbtab(target_align_yr, dt_adresobjectbus)
  ),
  tar_target(
    name = dt_inhatab,
    command = load_filter_clean_inhatab(dt_rins)
  ),
  tar_target(
    name = dt_ggzzpm,
    command = load_filter_clean_ggzzpm(dt_rins)
  ),  
  tar_target(
    name = dt_ggzdeclvektis,
    command = load_filter_clean_ggzdeclvektis(dt_rins)
  ),
  tar_target(
    name = dt_huisarts,
    command = load_filter_clean_huisarts(dt_rins)
  ),
  tar_target(
    name = dt_medicijn,
    command = load_filter_clean_medicijntab(dt_rins)
  ),
  
  ## processing targets ##
  tar_target(
    name = dt_huisarts_enriched,
    command = create_huisarts_usage_col(dt_huisarts, dt_zvw)
  ),
  tar_target(
    name = dt_stapeling_enriched,
    command = enrich_stapeling(dt_stapeling_filtered_clean)
  ),
  # tar_target(
  #   name = dt_kindouder_enriched,
  #   command = enrich_kindoudertab(dt_kindouder, dt_stapeling_enriched)
  # ),
  tar_target(
    name = dt_ggz_usage,
    command = process_ggz_usage(dt_ggzdeclvektis, dt_ggzzpm, dt_huisarts)
  ),
  tar_target(
    name = dt_kindouder_processed,
    command = process_kindouder(dt_kindouder, dt_rins, dt_gbapersoontab,dt_rins_unsampled)
  ),
  tar_target(
    name = dt_rins_with_regions,
    command = add_regional_cols(dt_rins, dt_adresobjectbus, dt_vslgwbtab)
  ),
  tar_target(
    dt_rins_merged,
    command = merge_into_rins(dt_rins_with_regions, dt_stapeling_enriched, 
                              dt_huisarts_enriched, dt_kindouder_processed, dt_gbapersoontab, 
                              dt_wmobus, dt_indicwlztab, dt_inhatab, dt_ggz_usage,
                              dt_medicijn)
  ),
  tar_target(
    name = dt_rins_with_vars,
    command = define_variables_by_rin(dt_rins_merged)
  ),

  # aggregations
  tar_target(
    name = dt_huishoudens_with_vars,
    command = aggregate_to_huishoudens(dt_rins_with_vars)
    ),
  tar_target(
    name = dt_agg_OT_HHKIND,
    command = aggregate_OT_HHKIND(dt_huishoudens_with_vars)
  ),
  tar_target(
    name = dt_agg_OT_OUD,
    command = aggregate_OT_OUD(dt_rins_with_vars)
  ),
  tar_target(
    name = OT_HHKIND_output,
    command = prepare_output_table_OT_HHKIND(dt_agg_OT_HHKIND)
  ),
  # output ready tables
  tar_target(
    name = OT_OUD_output,
    command = prepare_output_table_OT_OUD(dt_agg_OT_OUD)
  )
)
