library(testthat)
library(leaflet)   # venn_diagram.R builds its colour ramp with colorNumeric()

source("../data/metadata/brand_colors.R")
source("../utils/venn_diagram.R")
source("../utils/format_thinkcell_download.R")
source("../utils/slide_download.R")
source("../utils/template_admin.R")
source("../utils/favorites.R")
source("../utils/export_history.R")
source("../utils/auth.R")

test_dir("testthat")
