# Template Shiny app
#
# Put project data in the data/ folder and replace the placeholders below
# with your dashboard logic.

source("data/metadata/brand_colors.R")
source("utils/format_thinkcell_download.R")

library(shiny)

# Add any project-specific data import helpers here.
load_project_data <- function() {
  NULL
}

ui <- fluidPage(
  titlePanel("Dashboard template"),
  fluidRow(
    column(
      width = 12,
      h3("Start here"),
      p("Replace this template with your dashboard UI and server logic."),
      p("Shared helpers are sourced from data/metadata/brand_colors.R and utils/format_thinkcell_download.R."),
      p("Drop your data files into data/ and load them in load_project_data().")
    )
  )
)

server <- function(input, output, session) {
  data <- load_project_data()

  # Add server logic here.
  invisible(data)
}

shinyApp(ui = ui, server = server)
