# Shiny Dashboard Template

This repository is a starter template for Shiny dashboards.

Use it as follows:

1. Put your input files in `data/`.
2. Keep shared metadata and branding helpers in `data/metadata/`.
3. Add reusable functions to `utils/`.
4. Replace the scaffold in `app.R` with your dashboard UI and server logic.

## Included Helpers

- [data/metadata/brand_colors.R](data/metadata/brand_colors.R) contains the branding palette.
- [utils/format_thinkcell_download.R](utils/format_thinkcell_download.R) contains a helper for formatting data exports for Think-Cell.

## Run Locally

From an R session in the project folder:

```r
shiny::runApp("app.R")
```

If needed, set the working directory first:

```r
setwd("c:/Users/MarcoGriepAHTI/Git Repos/shiny_dashboard_template")
shiny::runApp("app.R")
```

## Notes

- The template app sources the shared helper files from `app.R`.
- Keep the README updated if you add new helper files or data conventions.
