# Dynamo Amsterdam Oost -- internal dashboard, iteratie 1.
#
# Reads data/app_data/, built by data-prep/01_build_app_data.R from the CBS RA
# delivery. Run that script first after a new delivery; the app does no
# aggregation of its own beyond filtering and the share calculation.

source("data/metadata/brand_colors.R")
source("data/metadata/variable_labels.R")

suppressPackageStartupMessages({
  library(shiny)
  library(dplyr)
  library(arrow)
  library(data.table)
  library(sf)
  library(leaflet)
  library(plotly)
  library(writexl)
})

source("utils/venn_diagram.R")

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

DATA_DIR <- "data/app_data"

if (!dir.exists(DATA_DIR)) {
  stop("data/app_data/ is missing. Run: Rscript data-prep/01_build_app_data.R")
}

ds  <- open_dataset(file.path(DATA_DIR, "indicators.parquet"))
geo <- readRDS(file.path(DATA_DIR, "geo.rds"))

TOTAL_LABEL <- "(totaal)"

# Small vocabulary table driving every selector, pulled once at startup so the
# cascading selectors never touch the 3.5M-row dataset just to list choices.
vocab <- ds |>
  select(population, region_level, year, variable_name, variable_value,
         metric_name, split_var, split_level) |>
  distinct() |>
  collect() |>
  as.data.table()

POPULATIONS   <- sort(unique(vocab$population))
REGION_LEVELS <- c("buurt", "wijk", "gebied", "stadsdeel")  # gemeente has no map
YEARS         <- sort(unique(vocab$year))

# Opening view: the city itself, not a default that includes Haarlem and Almere.
AMS_BBOX <- st_bbox(geo$stadsdeel)

# Region code -> name, per level, from the geometry (the delivery carries codes
# only).
region_choices <- lapply(geo, function(g) {
  d <- st_drop_geometry(g)
  setNames(d$region_code, d$region_name)[order(d$region_name)]
})

# Which split_var holds the O_MPG*/O_OUD* support-combination for each
# population, and the matching label vectors from variable_labels.R -- keyed
# the same way throughout so a lookup by input$populatie always works.
COMBO_SPLIT_VAR <- c(
  "huishoudens met kinderen" = "O_MPG_combination",
  "ouderen (65+)"            = "O_OUD_combination"
)
COMBO_GROUP_LABELS <- list(
  "huishoudens met kinderen" = ONDERSTEUNING_GROEP_LABELS_HHKIND,
  "ouderen (65+)"            = ONDERSTEUNING_GROEP_LABELS_OUD
)
COMBO_GROUP_UITLEG <- list(
  "huishoudens met kinderen" = ONDERSTEUNING_GROEP_UITLEG_HHKIND,
  "ouderen (65+)"            = ONDERSTEUNING_GROEP_UITLEG_OUD
)
# variable_name is disjoint between the two populations (R_MPG* vs R_OUD*),
# so one merged lookup is safe and simpler than branching on population.
RISICO_LABELS <- c(RISICO_LABELS_HHKIND, RISICO_LABELS_OUD)

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

# variable_name -> official Dutch description, from Outcomes.xlsx (see
# data/metadata/variable_labels.R) -- not guessed from the column name. Falls
# back to a cleaned-up version of the raw name for anything not in that
# lookup, so a future indicator the labels file hasn't caught up with still
# renders as something readable rather than breaking.
pretty_var <- function(x) {
  known <- RISICO_LABELS[x]
  fallback <- {
    s <- sub("^R_", "", x)
    s <- sub("_hh$", "", s)
    s <- sub("^(MPG|OUD)([0-9]*)_", "\\1\\2 - ", s)
    s <- sub("^(MPG|OUD)_", "\\1 ", s)
    gsub("_", " ", s)
  }
  unname(ifelse(is.na(known), fallback, known))
}

pretty_metric <- function(x) {
  out <- gsub("_", " ", sub("^n_", "aantal ", x))
  sub("aantal ouderen with var value", "aantal ouderen", out)
}

pretty_split <- function(x) {
  ifelse(x == TOTAL_LABEL, TOTAL_LABEL, gsub("_", " ", sub("_hh$", "", x)))
}

# "O_MPG1 + O_MPG2" -> "Jeugdhulp + Psychosociale zorg (volwassenen)": every
# token split on "+" gets its short group name from variable_labels.R. "none"
# is its own sentinel (never itself a "+"-joined token).
pretty_combo_level <- function(x, groep_labels) {
  vapply(x, function(v) {
    if (is.na(v) || v == "none") return("Geen ondersteuningssignaal")
    parts <- trimws(strsplit(v, "\\+")[[1]])
    labs <- groep_labels[parts]
    labs[is.na(labs)] <- parts[is.na(labs)]  # unknown token: show as-is rather than drop it
    paste(labs, collapse = " + ")
  }, character(1), USE.NAMES = FALSE)
}

# split_level formatting depends on which split_var it belongs to: the O_*
# combination fields need pretty_combo_level(), the binary split variables
# ("0"/"1") read as ja/nee, and categorical splits (herkomst7, geslacht)
# already carry readable values and are left alone. split_var/population are
# optional so this still works for split_var-less callers (e.g. a plain
# variable_value).
pretty_level <- function(x, split_var = NULL, population = NULL) {
  if (!is.null(split_var) && !is.null(population) &&
      isTRUE(split_var == COMBO_SPLIT_VAR[[population]])) {
    return(pretty_combo_level(x, COMBO_GROUP_LABELS[[population]]))
  }
  if (all(x %in% c("0", "1"))) {
    return(c("0" = "nee", "1" = "ja")[x])
  }
  x
}

named_levels <- function(values, split_var = NULL, population = NULL) {
  setNames(values, pretty_level(values, split_var, population))
}

named <- function(values, labeller) setNames(values, labeller(values))

# Keeps the user's current pick when it is still a valid choice, so changing an
# unrelated selector does not silently reset the rest of the form.
update_preserving <- function(session, id, choices, current) {
  sel <- if (!is.null(current) && current %in% choices) current else choices[1]
  updateSelectInput(session, id, choices = choices, selected = sel)
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

control_card <- function(...) div(class = "control-card", ...)

ui <- fluidPage(
  title = "Dynamo Amsterdam - dashboard",

  tags$head(tags$style(HTML(sprintf("
    body { background: #fff; }
    h2.app-title { font-weight: 600; color: %1$s; margin: 14px 0 2px; font-size: 24px; }
    .app-sub { color: %3$s; margin-bottom: 14px; font-size: 13px; }
    .popbar { background: %4$s; border-left: 4px solid %2$s;
              padding: 10px 14px; border-radius: 4px; margin-bottom: 16px; }
    .popbar .form-group { margin-bottom: 0; }
    .control-card { background: %4$s; border-radius: 4px; padding: 12px 14px; margin-bottom: 12px; }
    .control-card .form-group { margin-bottom: 10px; }
    .note { font-size: 12px; color: %3$s; line-height: 1.45; }
    .chart-title { font-weight: 600; font-size: 15px; margin-bottom: 8px; color: %1$s; }
    .nav-tabs > li.active > a { border-top: 2px solid %2$s !important; }
  ", ahti_branding$colors$grijs_blauw,
     ahti_branding$colors$helder_blauw,
     ahti_branding$colors$midden_grijs,
     ahti_branding$colors$licht_grijs)))),

  h2("Dynamo Amsterdam", class = "app-title"),
  div("Risicostapeling bij huishoudens met kinderen en ouderen, 2018-2024. ",
      "Bron: CBS microdata via de Remote Access-omgeving.", class = "app-sub"),

  tabsetPanel(
    id = "hoofdtab",
    tabPanel(
      "Iteratie 1",
      br(),

      div(class = "popbar",
          fluidRow(
            column(5, selectInput("populatie", "Populatie", choices = POPULATIONS, width = "100%")),
            column(7, div(class = "note", style = "padding-top: 26px;",
                          "De populatiekeuze geldt voor beide tabbladen hieronder."))
          )),

      tabsetPanel(
        id = "subtab",

        # ---------------------------------------------------------------- Kaart
        tabPanel(
          "Kaart",
          br(),
          sidebarLayout(
            sidebarPanel(
              width = 3,
              control_card(
                selectInput("k_jaar", "Jaar", choices = YEARS, selected = max(YEARS)),
                selectInput("k_niveau", "Regioniveau", choices = REGION_LEVELS, selected = "wijk")
              ),
              control_card(
                selectInput("k_var", "Risicoscore (R_...)", choices = NULL),
                div(class = "note", style = "margin: -6px 0 10px;",
                    "Alle scores hieronder zijn risico-indicatoren: waarde één betekent",
                    " dat dit risico aanwezig is bij het huishouden/de oudere."),
                selectInput("k_val", "Waarde van de indicator", choices = NULL),
                selectInput("k_metric", "Metric", choices = NULL)
              ),
              control_card(
                selectInput("k_split", "Splits uit naar", choices = NULL),
                conditionalPanel(
                  "input.k_split != '(totaal)'",
                  selectInput("k_level", "Toon welk niveau", choices = NULL)
                ),
                uiOutput("k_combo_legend")
              ),
              control_card(
                radioButtons("k_weergave", "Weergave",
                             c("Absoluut" = "abs", "Aandeel (%)" = "rel"),
                             selected = "rel")
              ),
              downloadButton("k_dl", "Download data (xlsx)", class = "btn-default"),
              div(class = "note", style = "margin-top: 10px;",
                  "Grijze gebieden hebben geen cijfer: door de CBS-uitvoerregels zijn ",
                  "aantallen onder de 10 onderdrukt. Dat is niet hetzelfde als nul.")
            ),
            mainPanel(
              width = 9,
              div(textOutput("k_titel"), class = "chart-title"),
              leafletOutput("kaart", height = 680)
            )
          )
        ),

        # ------------------------------------------------------------ Per regio
        tabPanel(
          "Per regio",
          br(),
          sidebarLayout(
            sidebarPanel(
              width = 3,
              control_card(
                selectInput("r_niveau", "Regioniveau", choices = REGION_LEVELS, selected = "stadsdeel"),
                selectizeInput("r_regio", "Regio", choices = NULL)
              ),
              control_card(
                selectInput("r_var", "Risicoscore (R_...)", choices = NULL),
                div(class = "note", style = "margin: -6px 0 10px;",
                    "Alle scores hieronder zijn risico-indicatoren: waarde één betekent",
                    " dat dit risico aanwezig is bij het huishouden/de oudere."),
                selectInput("r_val", "Waarde van de indicator", choices = NULL),
                selectInput("r_metric", "Metric", choices = NULL)
              ),
              control_card(
                selectInput("r_split", "Splits de lijn uit naar", choices = NULL)
              ),
              control_card(
                radioButtons("r_weergave", "Weergave",
                             c("Absoluut" = "abs", "Aandeel (%)" = "rel"),
                             selected = "rel")
              ),
              downloadButton("r_dl", "Download data (xlsx)", class = "btn-default"),
              div(class = "note", style = "margin-top: 10px;",
                  "Een onderbroken lijn betekent dat het cijfer in dat jaar onderdrukt is.")
            ),
            mainPanel(
              width = 9,
              div(textOutput("r_titel"), class = "chart-title"),
              plotlyOutput("lijn", height = 620),

              hr(),
              fluidRow(
                column(9, div("Risicostapeling naar ondersteuningscombinatie", class = "chart-title")),
                column(3, selectInput("r_venn_jaar", "Jaar", choices = YEARS, selected = max(YEARS)))
              ),
              div(class = "note", style = "margin-bottom: 10px;",
                  "Combinatie van ondersteuningsgroepen voor de gekozen regio/risicoscore/waarde/",
                  "metric hierboven, voor het gekozen jaar. Dode ruimte buiten de cirkels = geen",
                  " van de drie groepen; het overlappende gebied = beide/alle groepen tegelijk."),
              uiOutput("venn"),
              uiOutput("venn_legenda")
            )
          )
        )
      )
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  # -- Shared vocabulary for the selected population --------------------------

  pop_vocab <- reactive({
    req(input$populatie)
    vocab[population == input$populatie]
  })

  # Within one population the indicator / metric / split vocabulary is fixed, so
  # these only ever need refreshing when the population changes. "Waarde van
  # de indicator" (k_val/r_val) is handled separately below: it depends on
  # which indicator is selected, not just the population -- the individual
  # risk factors are binary (0/1) but the totaalscore is a stapeling (0/1/2/
  # 3plus), so a fixed population-wide list would offer values that don't
  # apply to the chosen indicator.
  observeEvent(input$populatie, {
    v <- pop_vocab()

    vars    <- sort(unique(v$variable_name))
    metrics <- sort(unique(v$metric_name))
    splits  <- unique(v$split_var)
    splits  <- c(TOTAL_LABEL, sort(setdiff(splits, TOTAL_LABEL)))

    ids <- paste0(rep(c("k", "r"), each = 3), c("_var", "_metric", "_split"))

    # Read the current picks BEFORE freezing: a frozen input throws a silent
    # error when read, which would abort this observer before it sends any
    # choices at all.
    current <- lapply(ids, function(i) isolate(input[[i]]))
    names(current) <- ids

    # Freeze, because updateSelectInput() is a round trip to the browser:
    # input$k_var still holds the OLD population's variable for one flush after
    # the update is sent. Freezing halts the downstream reactives until the new
    # value lands, instead of querying the new population with the old
    # population's indicator. k_val/r_val are frozen too even though they are
    # not updated here: they depend on k_var/r_var (see below), which is
    # itself mid-change, so any stale read of k_val this same flush must also
    # be halted rather than paired with the wrong population's indicator.
    for (i in c(ids, "k_val", "r_val")) freezeReactiveValue(input, i)

    for (p in c("k", "r")) {
      update_preserving(session, paste0(p, "_var"),    named(vars, pretty_var),
                        current[[paste0(p, "_var")]])
      update_preserving(session, paste0(p, "_metric"), named(metrics, pretty_metric),
                        current[[paste0(p, "_metric")]])
      update_preserving(session, paste0(p, "_split"),  named(splits, pretty_split),
                        current[[paste0(p, "_split")]])
    }
  }, ignoreInit = FALSE)

  # "Waarde van de indicator": which values actually occur for the CURRENTLY
  # selected risicoscore, not the population as a whole -- see the comment
  # above. req(k_var %in% ...) guards the one flush where k_var can still be
  # stale for a population that was just switched away from: skip rather
  # than compute choices against the wrong population's indicator.
  observeEvent(list(input$populatie, input$k_var), {
    req(input$k_var)
    req(input$k_var %in% pop_vocab()$variable_name)
    vals <- sort(unique(pop_vocab()[variable_name == input$k_var]$variable_value))
    cur <- isolate(input$k_val)
    freezeReactiveValue(input, "k_val")
    update_preserving(session, "k_val", vals, cur)
  })
  observeEvent(list(input$populatie, input$r_var), {
    req(input$r_var)
    req(input$r_var %in% pop_vocab()$variable_name)
    vals <- sort(unique(pop_vocab()[variable_name == input$r_var]$variable_value))
    cur <- isolate(input$r_val)
    freezeReactiveValue(input, "r_val")
    update_preserving(session, "r_val", vals, cur)
  })

  # Levels of the chosen split variable (map tab only -- the line chart draws
  # every level at once).
  observeEvent(list(input$populatie, input$k_split), {
    req(input$k_split)
    if (input$k_split == TOTAL_LABEL) return()
    cur <- isolate(input$k_level)  # read before freezing (see above)
    lv <- sort(unique(pop_vocab()[split_var == input$k_split]$split_level))
    freezeReactiveValue(input, "k_level")
    update_preserving(session, "k_level", named_levels(lv, input$k_split, input$populatie), cur)
  })

  # Legend explaining O_MPG1/2/3 (or O_OUD1/2/3) whenever that's the chosen
  # map split -- otherwise NULL (hidden). The venn panel on the Per regio tab
  # carries the same legend permanently, since it always shows this split.
  output$k_combo_legend <- renderUI({
    req(input$populatie, input$k_split)
    if (!isTRUE(input$k_split == COMBO_SPLIT_VAR[[input$populatie]])) return(NULL)
    gl <- COMBO_GROUP_UITLEG[[input$populatie]]
    tags$div(class = "note", style = "margin-top: -4px;",
             HTML(paste(sprintf("<b>%s</b> %s", names(gl), gl), collapse = "<br/>")))
  })

  # Region picker follows the region level.
  observeEvent(input$r_niveau, {
    req(input$r_niveau)
    ch <- region_choices[[input$r_niveau]]
    cur <- isolate(input$r_regio)
    freezeReactiveValue(input, "r_regio")
    updateSelectizeInput(session, "r_regio", choices = ch,
                         selected = if (!is.null(cur) && cur %in% ch) cur else ch[1],
                         server = TRUE)
  }, ignoreInit = FALSE)

  # -- Shared slice logic -----------------------------------------------------

  # metric_value is the count; denominator is the total across the
  # variable_value categories within the same slice, so a share stays a valid
  # percentage for the n_kinderen_* metrics too (those count children against a
  # household n_totaal, which is why n_totaal is not the denominator here).
  # Always adds `waarde`, including on an empty slice -- a selection that has no
  # rows must still produce a table the map and chart can render as "geen data",
  # not one that errors on a missing column.
  add_display <- function(d, weergave) {
    if (nrow(d) == 0) {
      d[, waarde := numeric()]
      return(d[])
    }
    d[, waarde := if (weergave == "rel") {
        fifelse(denominator > 0, metric_value / denominator * 100, NA_real_)
      } else as.numeric(metric_value)]
    d[]
  }

  eenheid <- function(weergave) if (weergave == "rel") "%" else "aantal"

  # ---------------------------------------------------------------- Kaart -----

  kaart_data <- reactive({
    req(input$populatie, input$k_jaar, input$k_niveau,
        input$k_var, input$k_val, input$k_metric, input$k_split)

    lvl <- if (input$k_split == TOTAL_LABEL) TOTAL_LABEL else req(input$k_level)

    d <- ds |>
      filter(population   == !!input$populatie,
             region_level == !!input$k_niveau,
             year          == !!as.integer(input$k_jaar),
             variable_name == !!input$k_var,
             variable_value== !!input$k_val,
             metric_name   == !!input$k_metric,
             split_var     == !!input$k_split,
             split_level   == !!lvl) |>
      collect() |>
      as.data.table()

    add_display(d, input$k_weergave)
  })

  kaart_titel <- reactive({
    req(input$k_var, input$k_metric, input$k_jaar)
    sp <- if (input$k_split == TOTAL_LABEL) "" else
      sprintf(" | %s: %s", pretty_split(input$k_split),
              pretty_level(input$k_level %||% "", input$k_split, input$populatie))
    sprintf("%s = %s | %s (%s) | %s %s%s",
            pretty_var(input$k_var), input$k_val,
            pretty_metric(input$k_metric), eenheid(input$k_weergave),
            input$k_jaar, input$k_niveau, sp)
  })

  output$k_titel <- renderText(kaart_titel())

  output$kaart <- renderLeaflet({
    # Esri's grey canvas is keyless; CartoDB.Positron now watermarks its tiles
    # with "API KEY REQUIRED", which would show up on a deployed dashboard.
    leaflet(options = leafletOptions(minZoom = 10)) |>
      addProviderTiles(providers$Esri.WorldGrayCanvas) |>
      fitBounds(AMS_BBOX[["xmin"]], AMS_BBOX[["ymin"]],
                AMS_BBOX[["xmax"]], AMS_BBOX[["ymax"]])
  })

  # Redraw only the polygons, via a proxy, so changing a selector does not reset
  # the user's pan/zoom.
  observe({
    d <- kaart_data()
    req(input$k_niveau)
    g <- geo[[input$k_niveau]]

    m <- merge(g, d[, .(region_code, waarde, metric_value, n_totaal)],
               by = "region_code", all.x = TRUE)

    proxy <- leafletProxy("kaart") |> clearShapes() |> clearControls()

    if (all(is.na(m$waarde))) {
      proxy |> addPolygons(data = m, fillColor = "#e0e0e0", fillOpacity = 0.7,
                           color = "#fff", weight = 1,
                           label = "Geen data voor deze selectie")
      return()
    }

    pal <- colorBin("YlOrRd", domain = m$waarde, bins = 6,
                    na.color = "#e0e0e0", pretty = TRUE)

    fmt <- function(x) {
      if (is.na(x)) return("onvoldoende waarnemingen")
      if (input$k_weergave == "rel") sprintf("%.1f%%", x) else format(round(x), big.mark = ".")
    }

    labels <- mapply(function(nm, w, mv, nt) {
      HTML(sprintf(
        "<b>%s</b><br/>%s: %s%s",
        nm, pretty_metric(input$k_metric), fmt(w),
        if (is.na(w)) "" else sprintf("<br/><span style='color:#666'>n = %s van %s</span>",
                                      format(mv, big.mark = "."),
                                      format(nt, big.mark = "."))
      ))
    # USE.NAMES = FALSE matters: mapply() would otherwise key the result by
    # region_name, and leaflet serialises a *named* list as one JS object that
    # every polygon then shares -- which renders as an empty tooltip.
    }, m$region_name, m$waarde, m$metric_value, m$n_totaal,
       SIMPLIFY = FALSE, USE.NAMES = FALSE)

    proxy |>
      addPolygons(
        data = m,
        fillColor = ~pal(waarde), fillOpacity = 0.8,
        color = "#ffffff", weight = 1,
        label = labels,
        labelOptions = labelOptions(direction = "auto", textsize = "13px"),
        highlightOptions = highlightOptions(weight = 3, color = "#272727",
                                            fillOpacity = 0.9, bringToFront = TRUE)
      ) |>
      addLegend(position = "bottomright", pal = pal, values = m$waarde,
                title = eenheid(input$k_weergave), opacity = 0.9,
                na.label = "onvoldoende")
  })

  # ------------------------------------------------------------ Per regio -----

  regio_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio,
        input$r_var, input$r_val, input$r_metric, input$r_split)

    d <- ds |>
      filter(population    == !!input$populatie,
             region_level  == !!input$r_niveau,
             region_code   == !!input$r_regio,
             variable_name == !!input$r_var,
             variable_value== !!input$r_val,
             metric_name   == !!input$r_metric,
             split_var     == !!input$r_split) |>
      collect() |>
      as.data.table()

    d <- add_display(d, input$r_weergave)
    if (nrow(d) == 0) return(d)
    setorder(d, split_level, year)
    d[]
  })

  regio_titel <- reactive({
    req(input$r_var, input$r_metric, input$r_regio)
    nm <- names(region_choices[[input$r_niveau]])[
      match(input$r_regio, region_choices[[input$r_niveau]])]
    sp <- if (input$r_split == TOTAL_LABEL) "" else
      sprintf(" | uitgesplitst naar %s", pretty_split(input$r_split))
    sprintf("%s = %s | %s (%s) | %s%s",
            pretty_var(input$r_var), input$r_val,
            pretty_metric(input$r_metric), eenheid(input$r_weergave),
            nm %||% input$r_regio, sp)
  })

  output$r_titel <- renderText(regio_titel())

  output$lijn <- renderPlotly({
    d <- regio_data()
    validate(need(nrow(d) > 0, "Geen data voor deze selectie."))

    pal <- rep(ahti_branding$scale_discrete, length.out = uniqueN(d$split_level))

    p <- plot_ly(source = "lijn")
    lv <- unique(d$split_level)
    lv_lab <- pretty_level(lv, input$r_split, input$populatie)
    for (i in seq_along(lv)) {
      di <- d[split_level == lv[i]]
      p <- add_trace(
        p, data = di, x = ~year, y = ~waarde,
        type = "scatter", mode = "lines+markers",
        name = lv_lab[i], line = list(color = pal[i], width = 2.5),
        marker = list(color = pal[i], size = 7),
        hovertemplate = paste0(
          "<b>", lv_lab[i], "</b><br>%{x}<br>",
          if (input$r_weergave == "rel") "%{y:.1f}%" else "%{y:,.0f}",
          "<extra></extra>")
      )
    }

    p |>
      layout(
        title = list(text = ""),
        xaxis = list(title = "", dtick = 1, tickmode = "linear"),
        yaxis = list(title = eenheid(input$r_weergave),
                     rangemode = "tozero",
                     ticksuffix = if (input$r_weergave == "rel") "%" else ""),
        hovermode = "x unified",
        legend = list(orientation = "h", y = -0.12),
        showlegend = uniqueN(d$split_level) > 1,
        margin = list(t = 20)
      ) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("select2d", "lasso2d", "autoScale2d"))
  })

  # -- Risicostapeling naar ondersteuningscombinatie (venn) --------------------
  # Always shows the O_MPG_combination/O_OUD_combination split for the region
  # + risicoscore + waarde + metric already chosen above -- independent of
  # whatever input$r_split happens to be set to, and for one chosen year
  # (r_venn_jaar) since a venn diagram is a single-year snapshot, unlike the
  # line chart above it.

  venn_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio,
        input$r_var, input$r_val, input$r_metric, input$r_venn_jaar)

    combo_var <- COMBO_SPLIT_VAR[[input$populatie]]

    d <- ds |>
      filter(population    == !!input$populatie,
             region_level  == !!input$r_niveau,
             region_code   == !!input$r_regio,
             variable_name == !!input$r_var,
             variable_value== !!input$r_val,
             metric_name   == !!input$r_metric,
             split_var     == !!combo_var,
             year          == !!as.integer(input$r_venn_jaar)) |>
      collect() |>
      as.data.table()

    add_display(d, input$r_weergave)
  })

  output$venn <- renderUI({
    d <- venn_data()

    codes <- names(COMBO_GROUP_LABELS[[input$populatie]])  # e.g. O_MPG1/2/3
    get_val <- function(level) {
      row <- d[split_level == level]
      if (nrow(row) == 0) NA_real_ else row$waarde[1]
    }
    vals <- c(
      none = get_val("none"),
      A    = get_val(codes[1]),
      B    = get_val(codes[2]),
      C    = get_val(codes[3]),
      AB   = get_val(paste(codes[1], codes[2], sep = " + ")),
      AC   = get_val(paste(codes[1], codes[3], sep = " + ")),
      BC   = get_val(paste(codes[2], codes[3], sep = " + ")),
      ABC  = get_val(paste(codes, collapse = " + "))
    )

    HTML(venn_svg(vals, input$r_weergave, codes, COMBO_GROUP_LABELS[[input$populatie]]))
  })

  output$venn_legenda <- renderUI({
    req(input$populatie)
    gl <- COMBO_GROUP_UITLEG[[input$populatie]]
    tags$div(class = "note", style = "margin-top: 8px; text-align: center;",
             HTML(paste(sprintf("<b>%s</b> %s", names(gl), gl), collapse = "&nbsp;&nbsp;&middot;&nbsp;&nbsp;")))
  })

  # -------------------------------------------------------------- Downloads ---
  # Raw data export only for now; the think-cell / favorites layer in utils/ is
  # deliberately not wired up yet (see PLAN.md).

  export_cols <- function(d) {
    d[, .(populatie = population, regioniveau = region_level,
          regiocode = region_code, regionaam = region_name, stadsdeel,
          jaar = year, indicator = variable_name, waarde_indicator = variable_value,
          metric = metric_name, aantal = metric_value,
          n_totaal, noemer = denominator, weergegeven_waarde = waarde,
          splitsvariabele = split_var, splitsniveau = split_level)]
  }

  output$k_dl <- downloadHandler(
    filename = function() sprintf("dynamo_kaart_%s.xlsx", Sys.Date()),
    content  = function(file) write_xlsx(export_cols(kaart_data()), file)
  )

  output$r_dl <- downloadHandler(
    filename = function() sprintf("dynamo_regio_%s.xlsx", Sys.Date()),
    content  = function(file) write_xlsx(export_cols(regio_data()), file)
  )
}

shinyApp(ui, server)
