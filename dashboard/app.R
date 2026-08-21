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

# The split columns carry their own total level; select it by default so the map
# shows totals until a subgroup is explicitly chosen.
ALL_LEVEL <- "all"

# Split-var choices are computed once from the full rins table and used as
# static UI choices, never refreshed via updateSelectInput. This is what makes
# a user's split selection persist across variable/year changes: Shiny only
# resets a selectInput's value when server code calls update*Input on it, so
# leaving these alone is what "sticky" filters require.
build_split_choices <- function(svar) {
  vals <- as.character(rins[[svar]])
  lvls <- sort(unique(vals[!is.na(vals)]))
  if (ALL_LEVEL %in% lvls) {
    lvls <- c(ALL_LEVEL, setdiff(lvls, ALL_LEVEL))  # keep the total on top
  } else {
    warning("no '", ALL_LEVEL, "' level in rins$", svar,
            "; defaulting to '", lvls[1], "'")
  }
  lvls
}
split_var_choices <- setNames(lapply(split_vars, build_split_choices), split_vars)
split_var_default <- function(svar) {
  lvls <- split_var_choices[[svar]]
  if (ALL_LEVEL %in% lvls) ALL_LEVEL else lvls[1]
}

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
      conditionalPanel("input.bron=='rins'",
        selectInput(paste0("split_", split_vars[1]), label = split_vars[1],
                    choices = split_var_choices[[split_vars[1]]],
                    selected = split_var_default(split_vars[1])),
        selectInput(paste0("split_", split_vars[2]), label = split_vars[2],
                    choices = split_var_choices[[split_vars[2]]],
                    selected = split_var_default(split_vars[2])),
        selectInput(paste0("split_", split_vars[3]), label = split_vars[3],
                    choices = split_var_choices[[split_vars[3]]],
                    selected = split_var_default(split_vars[3]))
      ),
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

  # The selectors form a cascade: bron -> jaar -> varnaam -> scoreval/split -> metriek.
  # updateSelectInput() is a round trip to the browser, so input$X keeps its OLD
  # value for one flush after the update is sent. freezeReactiveValue() marks the
  # input stale so downstream reactives halt (like req()) until the new value
  # arrives — without it, filtdata() runs the previous bron's varnaam against the
  # new table.

  # Update year choices when data source changes
  observeEvent(input$bron, {
    years <- suppressWarnings(as.numeric(as.character(dt()$year)))
    years <- sort(unique(years[!is.na(years)]), decreasing = TRUE)

    freezeReactiveValue(input, "jaar")
    updateSelectInput(session, "jaar", choices = years)
  })

  # Update variable choices when bron or year changes
  observeEvent(list(input$bron, input$jaar), {
    req(input$jaar)
    d <- dt()[suppressWarnings(as.numeric(as.character(year))) == as.numeric(input$jaar)]

    freezeReactiveValue(input, "varnaam")
    updateSelectInput(session, "varnaam", choices = sort(unique(d$variable_name)))
  })

  # Update score value choices (huishoudens only)
  observeEvent(list(input$bron, input$varnaam, input$jaar), {
    if (input$bron != "huishoudens") return()
    req(input$varnaam, input$jaar)

    sub <- hh[variable_name == input$varnaam &
              suppressWarnings(as.numeric(as.character(year))) == as.numeric(input$jaar)]

    freezeReactiveValue(input, "scoreval")
    updateSelectInput(session, "scoreval", choices = sort(unique(sub$variable_value)))
  })

  # Split-var selectors (split_<svar>) are static — see build_split_choices()
  # above — so there is deliberately no observer here to refresh them; that is
  # what keeps a user's pick fixed across variable/year changes.

  # Update metric choices
  observeEvent(list(input$bron, input$varnaam, input$scoreval, input$jaar), {
    req(input$varnaam, input$jaar)
    if (input$bron == "huishoudens") req(input$scoreval)

    d <- dt()[variable_name == input$varnaam &
              suppressWarnings(as.numeric(as.character(year))) == as.numeric(input$jaar)]
    if (input$bron == "huishoudens") d <- d[variable_value == input$scoreval]

    freezeReactiveValue(input, "metriek")
    updateSelectInput(session, "metriek", choices = sort(unique(d$metric_name)))
  })

  # Filtered data for map
  filtdata <- reactive({
    req(input$varnaam, input$metriek, input$regionlvl, input$jaar)
    if (input$bron == "huishoudens") req(input$scoreval)

    jaar_num <- suppressWarnings(as.numeric(as.character(input$jaar)))
    if (is.na(jaar_num)) return(dt()[0])

    # No `:=` on dt(): it is not a copy, so := would mutate hh/rins in place.
    d0 <- dt()[suppressWarnings(as.numeric(as.character(year))) == jaar_num]
    if (nrow(d0) == 0) return(d0)
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
      # ALL_LEVEL is a real level in the data (the total), so it is filtered on
      # like any other value. Only an unset selector is skipped.
      for (svar in split_vars) {
        split_val <- input[[paste0("split_", svar)]]
        if (is.null(split_val) || !nzchar(split_val)) next
        d <- d[as.character(get(svar)) == split_val]
      }
    }

    d <- copy(d)
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
