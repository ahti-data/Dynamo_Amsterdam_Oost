library(testthat)
library(leaflet)   # venn_diagram.R builds its colour ramp with colorNumeric()
library(data.table)  # data-prep/derive_support_splits.R werkt op data.tables

source("../data/metadata/brand_colors.R")
source("../utils/venn_diagram.R")
source("../utils/map_download.R")
source("../utils/format_thinkcell_download.R")
source("../utils/slide_download.R")
source("../utils/template_admin.R")
source("../utils/favorites.R")
source("../utils/export_history.R")
source("../utils/auth.R")

# Niet uit utils/: de afleiding draait in de prep-stap, niet in de app. De
# regels die hij bewaakt (onderdrukking nooit als nul) zijn wel testwaardig.
source("../data-prep/derive_support_splits.R")

test_dir("testthat")
