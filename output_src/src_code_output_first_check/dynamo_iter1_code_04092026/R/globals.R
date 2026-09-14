#### libraries and sources ####
source("H:/utils/demog_functions.R")
source("H:/_Personal_folders/Marco/loading function/src/m_functions.R")

#### globals ####
mode <- "ams"

use_sample <- switch(mode,
                     sample = 10000,
                     ams = "ams", 
                     full = FALSE)

base_years <- 2018:2024

# output/iterations stuff
current_output_name <- "1a"
processed_data_folder <- "data/processed/"
output_data_folder <- "data/output/"

suppressWarnings(dir.create(processed_data_folder)) ; suppressWarnings(dir.create(output_data_folder))

save_processed <- function(data, name, filetype = ".xlsx") {
  
  destination_name <- paste0(processed_data_folder, name, filetype)
  if (filetype == ".xlsx") {
    writexl::write_xlsx(
      data,
      destination_name
    )
  } else if (filetype == ".csv") {
    fwrite(
      data,
      destination_name
    )
  }
  
  print(paste(name, "saved under", destination_name))
}

save_output <- function(data, name, filetype = ".xlsx") {
 
  destination_name <- paste0(
    output_data_folder, 
    glue("output_{current_output_name}/"),
    name, filetype)
  
  suppressWarnings(dir.create(dirname(destination_name)))
  
  
  if (filetype == ".xlsx") {
    writexl::write_xlsx(
      data,
      destination_name
    )
  } else if (filetype == ".csv") {
    fwrite(
      data,
      destination_name
    )
  }
}

#### functions ####

# define custom tar_make that loads the visnetwork
run_pipeline <- function(target = "all", mode = c("sample", "full", "ams")) {
  network <- tar_visnetwork(targets_only = T)
  print(network)
  
  mode <- match.arg(mode)
  # project <- if(mode == "sample") "sample" else "full"
  
  # Sys.setenv(PIPELINE_MODE = mode, TAR_PROJECT = project)
  
  
  # if (run_tar_watch) {
  #   watcher_alive <- !is.null(tryCatch(suppressWarnings(socketConnection(host="127.0.0.1", port = 8080, timeout=1)), 
  #                             error = function(e) NULL))
  #   
  #   if (!watcher_alive) {
  #     message("launching tar_watch()...")
  #     tar_watch(seconds = 60, port = 8080, targets_only = T, outdated = T, label = "time")
  #     } else{
  #     message("tar_watch already online")
  #   }
  # }
  
  if (target == "all") tar_make() else tar_make(target)
  
  network <- tar_visnetwork(targets_only = T)
  print(network)
  }

#### definitions ####
poh_ggz_codes <- c(12111:12113, 12116:12118, 11609, 31201, 31280, 31281, 31282, 31330)
max_age_children <- 18
#### cleaning params ####
jeugdzorg_cols_stapeling <- tolower(c(
  "JBots", 
  "JBvoogdij", 
  "JHmgesloten", 
  "JHmgezin", 
  "JHmov", 
  "JHmpleeg", 
  "JHzambulant", 
  "JHzdag", 
  "JHznetwerk", 
  "JHzwijk", 
  "JR", 
  "JeugdPGB", 
  "juridische_ouder_kind_jeugdzorg"
))

unlabelled_cols_stapeling <- c(
  jeugdzorg_cols_stapeling,
  
  # binary cols
  "werknemer",
  "zelfstandig_ondernemer_met_personeel",
  "zelfstandig_ondernemer_zonder_personeel",
  "smalle_schuld",
  "smalle_schuld_huishouden",
  "wanbetaler_zorgverzekering",
  # "laagink",
  # "langlaagink",
  "startkwalificatie",
  "kinderopvangtoeslag",
  "huurtoeslag",
  "zorgtoeslag",
  "bijstand",
  "wsnp",
  "afdoening_om",
  "afdoening_rechter",
  "medicijn_psychofarmaca",
  "bijzondere_bijstand",
  "ww",
  "ao", 
  "ziektewet",
  "medicijn_verslaving",
  
  # numeric cols
  "leeftijd",
  "aantkindhh",
  # "aantvolwhh",
  # "aant65plushh",
  # "aantpphh",
  # "gewichtopl",
  "vermogenhhexcl",
  
  # other unlabeled/categorical
  "datumaanvanghh"
)

labelled_cols_stapeling = c(
  # "wijzigingcbs",
  # "geboorteland",
  # "herkomstouders",
  # "herkomstland", 
  "huishoudnr",
  "typehh",
  "typeonderwijs",
  "belanginkbronpers",
  # "leeftijdjongkind",
  # "leeftijdoudkind",
  "burgstaat",
  "herkomst",
  # "hbopl",
  # "hgopl",
  "woonsituatie",
  # "typeonderwijs",
  # "huishsamstsocec",
  "typehh",
  "geslacht"
)

all_cols_to_load_stapeling =c(
  labelled_cols_stapeling,
  unlabelled_cols_stapeling
)

cols_to_load_wmobus <- c(
  "rinpersoon",
  "typearrangement"
)


cols_to_load_inhatab <- c(
  "inharmsoc",
  "inhbrutinkh",
  "inhgestinkh"
)


split_vars_OT_OUD <-c(
  "herkomst7", "geslacht"
)

split_vars_OT_HHKIND <-c(
  "kinderopvangtoeslag_hh", "migratieachtergrond_hh", "langwonende_hh"
)

target_align_yr <- 2026
