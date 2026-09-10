setwd("H:/_Current_projects/dynamo")
library(targets); library(shiny); library(leaflet); library(sf)
tar_source()
options(shiny.fullstacktrace = TRUE)

# load datasets
tar_load(c(dt_huishoudens_agg_OT1, dt_rins_agg_OT_OUD))

hh <- dt_huishoudens_agg_OT1
rins <- dt_rins_agg_OT_OUD
shp_bc <- load_shapefile(2025, "buurt") |> st_transform(4326)
shp_bc$regioncode <- shp_bc$bu_code
shp_bc$regionname <- shp_bc$bu_naam
shp_bc <- shp_bc |> filter(gm_naam == "Amsterdam")

shp_wc <- load_shapefile(2025, "wijk") |> st_transform(4326)
shp_wc$regioncode <- shp_wc$wk_code
shp_wc$regionname <- shp_wc$statnaam
shp_wc <- shp_wc |> filter(gm_naam == "Amsterdam")

ui <- fluidPage(
  titlePanel("Dynamo intermediate"),
  sidebarLayout(
    sidebarPanel(
      selectInput("bron", "Aggregatieniveau data", c("huishoudens", "rins")),
      selectInput("jaar", "Jaar", choices = NULL),
      selectInput("varnaam", "Variabele", choices = NULL),
      conditionalPanel("input.bron == 'huishoudens'",
                       selectInput("scoreval", "Score waarde", choices = NULL)),
      conditionalPanel("input.bron == 'rins'",
                      selectInput(paste0("split_", split_vars_OT_OUD[1]), label = split_vars_OT_OUD[1], choices = NULL, selected = "all"),
                      selectInput(paste0("split_", split_vars_OT_OUD[2]), label = split_vars_OT_OUD[2], choices = NULL, selected = "all"),
                      selectInput(paste0("split_", split_vars_OT_OUD[3]), label = split_vars_OT_OUD[3], choices = NULL, selected = "all"),
                      selectInput(paste0("split_", split_vars_OT_OUD[4]), label = split_vars_OT_OUD[4], choices = NULL, selected = "all")
                      ),
      selectInput("metriek", "Metric", choices = NULL),
      selectInput("regionlvl", "Regionaal niveau", c("wc", "bc")),
      uiOutput("split_var_filters"),
      hr(),
      p("Hover over gebieden voor waarden", class = "help-text")
      
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Kaart", leafletOutput("kaart", height = 700)),
        tabPanel("Debug: filtdata", verbatimTextOutput("debug_filt")),
        tabPanel("Debug: merge/sf", verbatimTextOutput("debug_sf")),
        
        )
      )
      
  )
)

server <- function(input, output, session) {
  dt <- reactive(if (input$bron == "huishoudens") hh else rins)
  
  split_vars_list <- reactive({
    if(input$bron == "rins") {
      split_vars <- split_vars_OT_OUD
    } else {
      character(0)
    }
  })
  
  observeEvent(input$bron, {
    freezeReactiveValue(input, "jaar")
    updateSelectInput(session, "jaar", choices = sort(unique(dt()$year), decreasing = TRUE))
  })
  
  observeEvent(list(input$bron, input$jaar), {
    req(input$jaar)
    d <- dt()[year==as.numeric(input$jaar)]
    freezeReactiveValue(input, "varnaam")
    updateSelectInput(session, "varnaam", choices = sort(unique(d$variable_name)))
  })
  
  observeEvent(list(input$varnaam, input$jaar), {
    req(input$varnaam, input$jaar)
    if (input$bron=="huishoudens") {
    sub <- hh[variable_name == input$varnaam & year == as.numeric(input$jaar)]
    freezeReactiveValue(input, "scoreval")
    updateSelectInput(session, "scoreval", choices = sort(unique(sub$variable_value)))
  }})
  
  
  observeEvent(list(input$varnaam, input$scoreval, input$bron, input$jaar), {
    req(input$varnaam, input$scoreval, input$bron, input$jaar)
    d <- dt()[variable_name == input$varnaam & year == as.numeric(input$jaar)]
    if (input$bron == "huishoudens"&& !is.null(input$scoreval))
      d <- d[variable_value == input$scoreval]
    freezeReactiveValue(input, "metriek")
    
    updateSelectInput(session, "metriek", choices = sort(unique(d$metric_name)))
  })
  
  
  # update the split vars
  observeEvent(list(input$bron, input$varnaam, input$jaar), {
    if (input$bron != "rins") return()
    req(input$varnaam, input$jaar)
    
    # browser()
    
    d <- rins[variable_name == input$varnaam & year == as.numeric(input$jaar)]

    for (svar in split_vars_OT_OUD) {
      if(svar %in% names(d)) {
        vals <- d[[svar]]
        choices <- sort(unique(vals[!is.na(vals)]))
        freezeReactiveValue(input, paste0("split_", svar))
        updateSelectInput(session, paste0("split_", svar), choices = as.character(choices), selected = "all")
      }
    }
    
  })
  

  filtdata <- reactive({
    req(input$varnaam, input$metriek, input$regionlvl, input$jaar)
    d <- dt()[variable_name == input$varnaam & metric_name == input$metriek & 
                region_agg_level == input$regionlvl & year == as.numeric(input$jaar)]
    if (input$bron=="huishoudens") {
      d <- d[variable_value == input$scoreval]
    } else if (input$bron == "rins") {

      svars <- split_vars_list()
      for (svar in svars) {
        req(input[[paste0("split_", svar)]])
        
        split_val <- input[[paste0("split_", svar)]]
        if (!is.null(split_val)) {
          d <- d[get(svar) == split_val]
        }
        if (!is.null(split_val) && split_val != "") {
          d <- d[d[[svar]] == split_val]
        }
      }
    }
    d
  })
  
  shp <- reactive(if(input$regionlvl == "wc") shp_wc else shp_bc)
  
  output$debug_filt <- renderPrint({
    d <- filtdata()
    cat("nrow:", nrow(d), "\n")
    print(summary(d$metric_value))
  })
  
  output$debug_sf <- renderPrint({
    d <- filtdata(); s <- shp()
    m <- merge(s, d, by.x = "regioncode", by.y = "region_code")
    print(head(m))
  })
  
  output$kaart <- renderLeaflet({
    d <- filtdata(); s <- shp()
    m <- merge(s, d, by.x = "regioncode", by.y = "region_code")
    m <- st_as_sf(m)
    
    
    pal <- colorNumeric("BuPu", m$metric_value, na.color = "grey90")
    
    labels <- lapply(seq_len(nrow(m)), function(i) {
      region <- m$regionname[i]
      value <- m$metric_value[i]
      if  ("n_totaal_hh_region" %in% names(m)){
        n_totaal <- m$n_totaal_hh_region[i]
        paste0(region, ": ", round(value, 2), "; total huishoudens in region: ", n_totaal)
      } else {
        n_totaal <- m$n_totaal[i]
        paste0(region, ": ", round(value, 2), "; total persons in region/group: ", n_totaal)
      }
    })
    
    popups <- lapply(seq_len(nrow(m)), function(i) {
      region <- m$regionname[i]
      value <- m$metric_value[i]
      metric <- input$metriek
      jaar <- input$jaar
      
      if(is.na(value)) {
        HTML(paste0(
          "<b>", region, "</b><br/>",
          "Metriek:", metric, "<br/>",
          "Jaar: ", jaar, "<br/>",
          "Waarde: Geen data"
        ))
      } else {
        HTML(paste0(
          "<b>", region, "</b><br/>",
          "Metriek:", metric, "<br/>",
          "Jaar: ", jaar, "<br/>",
          "Waarde: <strong>", round(value,2), "</strong>"
        ))
      }
    })
    

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
      addLegend(pal = pal, values=~metric_value, title=input$metriek)
  })
}

shinyApp(ui, server)
