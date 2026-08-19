source("data/metadata/brand_colors.R")

library(shiny)
library(leaflet)
library(sf)
library(data.table)

# Load aggregated data from CBS environment
hh   <- dt_huishoudens_agg_OT1
rins <- dt_rins_agg_OT2

# Load and reproject shapefiles
shp_wc <- st_read("wc.shp") |> st_transform(4326) |> st_make_valid()
shp_bc <- st_read("bc.shp") |> st_transform(4326) |> st_make_valid()

ui <- fluidPage(
  titlePanel("Dynamo Oost — Dashboard"),
  sidebarLayout(
    sidebarPanel(
      selectInput("bron", "Aggregatieniveau data", c("huishoudens", "rins")),
      selectInput("jaar", "Jaar", choices = NULL),
      selectInput("varnaam", "Variabele", choices = NULL),
      conditionalPanel(
        "input.bron=='huishoudens'",
        selectInput("scoreval", "Score waarde", choices = NULL)
      ),
      selectInput("metriek", "Metric", choices = NULL),
      selectInput("regionlvl", "Regionaal niveau", c("wc", "bc")),
      uiOutput("split_var_filters"),
      hr(),
      p("Hover over gebieden voor waarden • Klik voor meer detail", class = "help-text")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Kaart", leafletOutput("kaart", height = 700)),
        tabPanel("Debug: filtdata", verbatimTextOutput("debug_filt")),
        tabPanel("Debug: merge/sf", verbatimTextOutput("debug_sf"))
      )
    )
  ),
  tags$style(HTML("
    .help-text { font-size: 12px; color: #666; margin-top: 1em; }
    .leaflet-popup-content-wrapper { font-size: 13px; }
  "))
)

server <- function(input, output, session) {

  # Data reactives
  dt <- reactive({
    if (input$bron == "huishoudens") hh else rins
  })

  shp <- reactive({
    if (input$regionlvl == "wc") shp_wc else shp_bc
  })

  # Get split_vars (should be defined in environment)
  split_vars_cols <- reactive({
    if (input$bron == "rins" && exists("split_vars")) {
      split_vars
    } else {
      character(0)
    }
  })

  # Dynamic UI for split variable filters (rins only)
  output$split_var_filters <- renderUI({
    svars <- split_vars_cols()
    if (length(svars) == 0) return(NULL)

    lapply(svars, function(svar) {
      selectInput(
        inputId = paste0("split_", svar),
        label = svar,
        choices = NULL
      )
    })
  })

  # Update year choices when data source changes
  observeEvent(input$bron, {
    updateSelectInput(
      session, "jaar",
      choices = sort(unique(dt()$year), decreasing = TRUE)
    )
  })

  # Update variable choices when year changes
  observeEvent(list(input$bron, input$jaar), {
    req(input$jaar)
    d <- dt()[year == as.numeric(input$jaar)]
    updateSelectInput(session, "varnaam", choices = sort(unique(d$variable_name)))
  })

  # Update score value choices (huishoudens only)
  observeEvent(list(input$varnaam, input$jaar), {
    req(input$varnaam, input$jaar)
    if (input$bron == "huishoudens") {
      sub <- hh[variable_name == input$varnaam & year == as.numeric(input$jaar)]
      updateSelectInput(session, "scoreval", choices = sort(unique(sub$variable_value)))
    }
  })

  # Update split variable choices (rins only)
  observeEvent(list(input$varnaam, input$jaar), {
    req(input$varnaam, input$jaar)
    if (input$bron != "rins") return()

    svars <- split_vars_cols()
    d <- rins[variable_name == input$varnaam & year == as.numeric(input$jaar)]

    for (svar in svars) {
      choices <- sort(unique(d[[svar]][!is.na(d[[svar]])]))
      updateSelectInput(session, paste0("split_", svar), choices = choices)
    }
  })

  # Update metric choices
  observeEvent(list(input$varnaam, input$scoreval, input$bron, input$jaar), {
    req(input$varnaam, input$jaar)
    if (input$bron == "huishoudens") req(input$scoreval)
    d <- dt()[variable_name == input$varnaam & year == as.numeric(input$jaar)]
    if (input$bron == "huishoudens") d <- d[variable_value == input$scoreval]
    updateSelectInput(session, "metriek", choices = sort(unique(d$metric_name)))
  })

  # Filtered data for map
  filtdata <- reactive({
    req(input$varnaam, input$metriek, input$regionlvl, input$jaar)
    if (input$bron == "huishoudens") req(input$scoreval)

    d0 <- dt()[year == as.numeric(input$jaar)]
    if (!(input$varnaam %in% d0$variable_name)) return(d0[0])
    if (input$bron == "huishoudens" &&
        !(input$scoreval %in% d0[variable_name == input$varnaam]$variable_value)) {
      return(d0[0])
    }

    d <- d0[
      variable_name == input$varnaam &
      metric_name == input$metriek &
      region_agg_level == input$regionlvl
    ]
    if (input$bron == "huishoudens") {
      d <- d[variable_value == input$scoreval]
    } else if (input$bron == "rins") {
      # Filter by split variables for rins
      svars <- split_vars_cols()
      for (svar in svars) {
        split_val <- input[[paste0("split_", svar)]]
        if (!is.null(split_val)) {
          d <- d[get(svar) == split_val]
        }
      }
    }

    d[, metric_value := as.numeric(metric_value)]
    d <- unique(d, by = "region_code")
    d
  })

  # Debug output: filtered data
  output$debug_filt <- renderPrint({
    d <- filtdata()
    cat("nrow:", nrow(d), "\n")
    print(summary(d$metric_value))
    cat("\nAantal negatief:", sum(d$metric_value < 0, na.rm = TRUE), "\n")
    print(sort(unique(d$metric_value[d$metric_value < 0])))
    print(head(d, 20))
  })

  # Debug output: merged sf object
  output$debug_sf <- renderPrint({
    d <- filtdata()
    s <- shp()
    m <- merge(s, d[, .(region_code, metric_value)],
               by.x = "regioncode", by.y = "region_code", all.x = TRUE)
    m <- st_as_sf(m)

    cat("CRS:", st_crs(s)$input, "\n")
    cat("nrow s:", nrow(s), " nrow m:", nrow(m), "\n")
    cat("unieke regiocodes in m:", length(unique(m$regioncode)), "\n")
    cat("regiocodes met >1 rij:\n")
    print(table(m$regioncode)[table(m$regioncode) > 1])
    cat("ongeldige geometrieen:", sum(!st_is_valid(m)), "\n")
    cat("lege geometrieen:", sum(st_is_empty(m)), "\n")
    cat("class(m$metric_value):", class(m$metric_value), "\n")
    cat("niet-NA metric_value:", sum(!is.na(m$metric_value)), "van", nrow(m), "\n")
    print(head(st_drop_geometry(m), 20))
  })

  # Main map
  output$kaart <- renderLeaflet({
    d <- filtdata()
    s <- shp()

    # Merge data with shapes (include n_totaal)
    m <- merge(s, d[, .(region_code, metric_value, n_totaal)],
               by.x = "regioncode", by.y = "region_code", all.x = TRUE)
    m <- st_as_sf(m)

    # Create color palette
    pal <- colorNumeric(
      "YlOrRd",
      domain = m$metric_value,
      na.color = "grey90"
    )

    # Build hover labels (plain text for tooltips)
    labels <- lapply(seq_len(nrow(m)), function(i) {
      region <- m$regioncode[i]
      value <- m$metric_value[i]
      n_tot <- m$n_totaal[i]

      if (is.na(value)) {
        label_text <- paste0(region, " — Geen data")
      } else {
        label_text <- paste0(region, ": ", round(value, 2))
      }

      if (!is.na(n_tot)) {
        label_text <- paste0(label_text, " (n=", n_tot, ")")
      }

      label_text
    })

    # Build popups for click
    popups <- lapply(seq_len(nrow(m)), function(i) {
      region <- m$regioncode[i]
      value <- m$metric_value[i]
      n_tot <- m$n_totaal[i]
      metric <- input$metriek
      jaar <- input$jaar

      popup_html <- paste0(
        "<b>", region, "</b><br/>",
        "Metriek: ", metric, "<br/>",
        "Jaar: ", jaar, "<br/>"
      )

      if (is.na(value)) {
        popup_html <- paste0(popup_html, "Waarde: Geen data")
      } else {
        popup_html <- paste0(
          popup_html,
          "Waarde: <strong>", round(value, 2), "</strong>"
        )
      }

      if (!is.na(n_tot)) {
        popup_html <- paste0(popup_html, "<br/>n: ", n_tot)
      }

      HTML(popup_html)
    })

    # Render map
    leaflet(m) |>
      addTiles() |>
      addPolygons(
        fillColor = ~pal(metric_value),
        fillOpacity = 0.8,
        color = "white",
        weight = 1,
        label = labels,
        popup = popups,
        highlightOptions = highlightOptions(
          weight = 2,
          color = "#333",
          bringToFront = TRUE
        )
      ) |>
      addLegend(
        pal = pal,
        values = ~metric_value,
        title = paste0(input$metriek, " (", input$jaar, ")"),
        position = "bottomright"
      )
  })
}

shinyApp(ui = ui, server = server)
