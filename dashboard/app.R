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

# The shared think-cell export stack from shiny_dashboard_template, in the order
# the files build on each other (same order as tests/testthat.R). Wiring
# conventions live in .claude/skills/thinkcell-export/SKILL.md; every chart that
# gets download buttons goes through chart_data_downloads_ui/server rather than
# growing its own handlers here.
source("utils/format_thinkcell_download.R")
source("utils/slide_download.R")
source("utils/template_admin.R")
source("utils/favorites.R")
source("utils/export_history.R")
source("utils/chart_downloads.R")
source("utils/tab_theme.R")

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

DATA_DIR <- "data/app_data"

if (!dir.exists(DATA_DIR)) {
  stop("data/app_data/ is missing. Run: Rscript data-prep/01_build_app_data.R")
}

ds  <- open_dataset(file.path(DATA_DIR, "indicators.parquet"))
geo <- readRDS(file.path(DATA_DIR, "geo.rds"))

# Provenance stamped into every export (tc_build_datasheet_log() in
# utils/slide_download.R): which RA delivery a chart's numbers came from, and
# when this app's own prepped copy of that delivery was last rebuilt. The raw
# delivery stays on the analyst's machine and is never deployed, so
# data-prep/01_build_app_data.R's parquet output -- what the app actually reads
# and what ships -- is the file whose date describes the numbers on screen.
RA_OUTPUT_ID   <- "output_1a"
RA_SOURCE_FILE <- c(
  "huishoudens met kinderen" = "OT_HHKIND.csv",
  "ouderen (65+)"            = "OT_OUD.xlsx"
)
APP_DATA_MTIME <- local({
  parts <- list.files(file.path(DATA_DIR, "indicators.parquet"),
                      pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
  if (length(parts) == 0) {
    ""
  } else {
    tc_format_source_mtime(parts[[which.max(file.info(parts)$mtime)]])
  }
})

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

# De twee afgeleide ondersteuningsuitsplitsingen uit de prep-stap
# (data-prep/derive_support_splits.R). Ze staan gewoon als rijen in de dataset,
# dus de keuzelijsten vinden ze vanzelf; de app hoeft ze alleen te kunnen
# benoemen, en te weten dat de indicatorvorm alleen op de totaalrij bestaat.
#
#   als splitsvariabele -> kruist met de risicoscore ("van de gezinnen met 2
#     vormen ondersteuning heeft x% drie of meer risicofactoren")
#   als indicator       -> de noemer is de hele populatie ("x% van de gezinnen
#     gebruikt een vorm van ondersteuning")
ONDERSTEUNING_SPLITS      <- names(ONDERSTEUNING_SPLIT_LABELS)
ONDERSTEUNING_INDICATOREN <- names(ONDERSTEUNING_INDICATOR_LABELS)

# variable_name -> omschrijving, voor alles wat in "Risicoscore" kan staan.
VAR_LABELS <- c(RISICO_LABELS, ONDERSTEUNING_INDICATOR_LABELS)

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

# variable_name -> official Dutch description, from Outcomes.xlsx (see
# data/metadata/variable_labels.R) -- not guessed from the column name. Falls
# back to a cleaned-up version of the raw name for anything not in that
# lookup, so a future indicator the labels file hasn't caught up with still
# renders as something readable rather than breaking.
pretty_var <- function(x) {
  known <- VAR_LABELS[x]
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
  known <- ONDERSTEUNING_SPLIT_LABELS[x]
  fallback <- ifelse(x == TOTAL_LABEL, TOTAL_LABEL, gsub("_", " ", sub("_hh$", "", x)))
  unname(ifelse(is.na(known), fallback, known))
}

# Categorielabel voor een afgeleide ondersteuningswaarde ("wel", "2"), in
# beide vormen: als variable_value van de indicator en als split_level van de
# splitsing zijn het dezelfde codes. Onbekende codes blijven zichzelf.
pretty_ondersteuning <- function(x) {
  x <- as.character(x)
  if (length(x) == 0L) return(character(0))  # ifelse() zou hier logical(0) geven
  lab <- ONDERSTEUNING_NIVEAU_LABELS[x]
  unname(ifelse(is.na(lab), x, lab))
}

# "Waarde van de indicator". De risicoscores houden hun ruwe waarde (0/1/2/
# 3plus, zie PLAN.md 6, open punt 2); bij de afgeleide indicatoren is de
# waarde zelf een categorie en krijgt hij zijn label mee.
pretty_value <- function(x, variable_name) {
  if (isTRUE(variable_name %in% ONDERSTEUNING_INDICATOREN)) return(pretty_ondersteuning(x))
  x
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
  # Dit gaat voor de 0/1-vuistregel hieronder: de niveaus van
  # aantal_ondersteuningsvormen zijn "0" t/m "3", en een slice waarin alleen
  # "0" en "1" overblijven zou anders als nee/ja gelezen worden.
  if (isTRUE(split_var %in% ONDERSTEUNING_SPLITS)) return(pretty_ondersteuning(x))
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
    .venn-tab { width: 100%%; border-collapse: collapse; font-size: 12.5px; }
    .venn-tab th, .venn-tab td { padding: 5px 9px; border-bottom: 1px solid #e6ebee; }
    .venn-tab thead th { color: %1$s; font-weight: 600; border-bottom: 1.5px solid %1$s; }
    .venn-tab th.venn-tab-span { text-align: center; }
    .venn-tab .venn-tab-groep { text-align: left; }
    .venn-tab .venn-tab-num, .venn-tab .venn-tab-n { text-align: right;
        font-variant-numeric: tabular-nums; white-space: nowrap; }
    .venn-tab td.venn-tab-n { color: %3$s; }
    .venn-tab tr.venn-tab-none td { background: %5$s; }
    .venn-tab tbody tr:hover td { background: %4$s; }
    .venn-tab-na { color: %3$s; cursor: help; }
  ", ahti_branding$colors$grijs_blauw,
     ahti_branding$colors$helder_blauw,
     ahti_branding$colors$midden_grijs,
     ahti_branding$colors$licht_grijs,
     VENN_NONE_FILL)))),

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
                selectInput("k_var", "Indicator", choices = NULL),
                uiOutput("k_var_note"),
                selectInput("k_val", "Waarde van de indicator", choices = NULL),
                selectInput("k_metric", "Metric", choices = NULL)
              ),
              control_card(
                selectInput("k_split", "Splits uit naar", choices = NULL),
                conditionalPanel(
                  "input.k_split != '(totaal)'",
                  selectInput("k_level", "Toon welk niveau", choices = NULL)
                ),
                uiOutput("k_split_note")
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
                selectInput("r_var", "Indicator", choices = NULL),
                uiOutput("r_var_note"),
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
              # Raw xlsx, think-cell xlsx, slide (.pptx) and the favorite star
              # for the line chart, all from the shared module -- see
              # chart_data_downloads_server("r_downloads", ...) below for the
              # data behind them.
              chart_data_downloads_ui(
                "r_downloads",
                chart_type      = "line",
                raw_label       = "Download data (ruw, xlsx)",
                thinkcell_label = "Download data (think-cell, xlsx)",
                slide_label     = "Download slide (PowerPoint)",
                favorite_label  = "\u2606 Bewaar als favoriet",
                # The plotlyOutput id below, deliberately un-namespaced: it is
                # what the client-side snapshot looks up to put a PNG of this
                # chart in a favorites/regenerate ZIP.
                plot_output_id  = "lijn"
              ),
              div(class = "note", style = "margin-top: 10px;",
                  "Een onderbroken lijn betekent dat het cijfer in dat jaar onderdrukt is.")
            ),
            mainPanel(
              width = 9,
              div(textOutput("r_titel"), class = "chart-title"),
              plotlyOutput("lijn", height = 620),

              hr(),
              fluidRow(
                column(5, div("Risicostapeling naar ondersteuningscombinatie", class = "chart-title")),
                column(3, selectInput("r_venn_jaar", "Jaar", choices = YEARS, selected = max(YEARS))),
                column(4, selectInput("r_venn_pal", "Kleurenschaal", choices = names(VENN_PALETTES)))
              ),
              div(class = "note", style = "margin-bottom: 10px;",
                  "Combinatie van ondersteuningsgroepen voor de gekozen regio/risicoscore/waarde/",
                  "metric hierboven, voor het gekozen jaar. Dode ruimte buiten de cirkels = geen",
                  " van de drie groepen; het overlappende gebied = beide/alle groepen tegelijk.",
                  " De kleurenschaal loopt over de zeven cirkelvlakken; de dode ruimte valt",
                  " erbuiten, anders bepaalt die in haar eentje de hele schaal."),
              uiOutput("venn"),
              uiOutput("venn_legenda"),
              uiOutput("venn_tabel"),
              uiOutput("venn_downloads")
            )
          )
        )
      )
    ),

    # The three shared panels every dashboard built from shiny_dashboard_template
    # carries (utils/favorites.R, utils/export_history.R, utils/template_admin.R).
    # Their titles stay English: the panels' own copy is English, and
    # tc_tab_color_theme() below keys its colour accents off this exact text.
    tabPanel("Favorites", br(), favorites_panel_ui("favorieten")),
    tabPanel("Export history", br(), export_history_panel_ui("exporthistorie")),
    tabPanel("Manage templates", br(), template_admin_ui("templates"))
  ),

  tc_tab_color_theme(ahti_branding)
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

  # Within one population the indicator and metric vocabulary is fixed, so
  # these only ever need refreshing when the population changes. "Waarde van
  # de indicator" (k_val/r_val) and "Splits uit naar" (k_split/r_split) are
  # handled separately below: both depend on which indicator is selected, not
  # just on the population -- the individual risk factors are binary (0/1) but
  # the totaalscore is a stapeling (0/1/2/3plus), and the derived
  # ondersteunings-indicators only exist on the total row, so a fixed
  # population-wide list would offer combinations that have no rows at all.
  observeEvent(input$populatie, {
    v <- pop_vocab()

    vars    <- sort(unique(v$variable_name))
    metrics <- sort(unique(v$metric_name))

    ids <- paste0(rep(c("k", "r"), each = 2), c("_var", "_metric"))

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
    for (i in c(ids, "k_val", "r_val", "k_split", "r_split")) freezeReactiveValue(input, i)

    for (p in c("k", "r")) {
      update_preserving(session, paste0(p, "_var"),    named(vars, pretty_var),
                        current[[paste0(p, "_var")]])
      update_preserving(session, paste0(p, "_metric"), named(metrics, pretty_metric),
                        current[[paste0(p, "_metric")]])
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
    update_preserving(session, "k_val",
                      setNames(vals, pretty_value(vals, input$k_var)), cur)
  })
  observeEvent(list(input$populatie, input$r_var), {
    req(input$r_var)
    req(input$r_var %in% pop_vocab()$variable_name)
    vals <- sort(unique(pop_vocab()[variable_name == input$r_var]$variable_value))
    cur <- isolate(input$r_val)
    freezeReactiveValue(input, "r_val")
    update_preserving(session, "r_val",
                      setNames(vals, pretty_value(vals, input$r_var)), cur)
  })

  # "Splits uit naar": which splits actually have rows for the CURRENTLY
  # selected indicator. The risk scores carry every split variable; the two
  # derived ondersteunings-indicators only exist on the total row, because the
  # delivery never has two splits at once and the ondersteuning already sits in
  # their variable_value. Offering them a split would produce an empty slice
  # that reads as a bug rather than as an impossible combination.
  observeEvent(list(input$populatie, input$k_var), {
    req(input$k_var)
    req(input$k_var %in% pop_vocab()$variable_name)
    sp <- unique(pop_vocab()[variable_name == input$k_var]$split_var)
    sp <- c(TOTAL_LABEL, sort(setdiff(sp, TOTAL_LABEL)))
    cur <- isolate(input$k_split)
    # k_level hangt aan k_split en moet dus mee bevriezen, net als hierboven.
    for (i in c("k_split", "k_level")) freezeReactiveValue(input, i)
    update_preserving(session, "k_split", named(sp, pretty_split), cur)
  })
  observeEvent(list(input$populatie, input$r_var), {
    req(input$r_var)
    req(input$r_var %in% pop_vocab()$variable_name)
    sp <- unique(pop_vocab()[variable_name == input$r_var]$split_var)
    sp <- c(TOTAL_LABEL, sort(setdiff(sp, TOTAL_LABEL)))
    cur <- isolate(input$r_split)
    freezeReactiveValue(input, "r_split")
    update_preserving(session, "r_split", named(sp, pretty_split), cur)
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

  # Vaste toelichting onder "Risicoscore". De R_-scores delen er een; de twee
  # afgeleide ondersteuningsindicatoren zijn geen risico-indicator en hebben
  # hun eigen kanttekening, want hun beschikbaarheid hangt aan de
  # CBS-onderdrukking en verschilt sterk per regioniveau (zie PLAN.md 6).
  var_note <- function(var_name) {
    if (isTRUE(var_name %in% ONDERSTEUNING_INDICATOREN)) {
      if (isTRUE(grepl("_aantal_vormen$", var_name))) {
        tags$div(class = "note", style = "margin: -6px 0 10px;",
                 "Afgeleid uit de ondersteuningscombinaties. De levering telt die",
                 " combinaties alleen gekruist met een risicoscore, en op buurtniveau",
                 " valt daarvan bijna altijd een cel onder de tien: reken op cijfers",
                 " voor gemeente, stadsdeel en gebied, ongeveer een kwart van de",
                 " wijken en nauwelijks buurten. Waar het cijfer er niet is, is het",
                 " onderdrukt \u2014 niet nul.")
      } else {
        tags$div(class = "note", style = "margin: -6px 0 10px;",
                 "Afgeleid uit de ondersteuningscombinaties: heeft dit huishouden/",
                 "deze oudere \u00fcberhaupt een ondersteuningssignaal? Bij",
                 " \u201cAandeel (%)\u201d is de noemer de hele populatie, dus dat",
                 " leest als het percentage dat een vorm van ondersteuning gebruikt.")
      }
    } else {
      tags$div(class = "note", style = "margin: -6px 0 10px;",
               "Alle scores hieronder zijn risico-indicatoren: waarde \u00e9\u00e9n betekent",
               " dat dit risico aanwezig is bij het huishouden/de oudere.")
    }
  }
  output$k_var_note <- renderUI(var_note(input$k_var))
  output$r_var_note <- renderUI(var_note(input$r_var))

  # Toelichting onder "Splits uit naar" op de Kaart-tab: de O_MPG1/2/3-legenda
  # bij de combinatiesplitsing, en bij de twee afgeleide splitsingen wat de
  # noemer daar betekent. Anders NULL (verborgen). Het vennpaneel op "Per
  # regio" draagt diezelfde legenda permanent, want het toont altijd die split.
  output$k_split_note <- renderUI({
    req(input$populatie, input$k_split)
    if (isTRUE(input$k_split == COMBO_SPLIT_VAR[[input$populatie]])) {
      gl <- COMBO_GROUP_UITLEG[[input$populatie]]
      return(tags$div(class = "note", style = "margin-top: -4px;",
                      HTML(paste(sprintf("<b>%s</b> %s", names(gl), gl), collapse = "<br/>"))))
    }
    if (isTRUE(input$k_split %in% ONDERSTEUNING_SPLITS)) {
      return(tags$div(class = "note", style = "margin-top: -4px;",
                      "Afgeleid uit de ondersteuningscombinaties. Bij",
                      " \u201cAandeel (%)\u201d is de noemer de gekozen groep zelf,",
                      " dus dat leest als: van de groep met dit ondersteuningsbeeld",
                      " heeft x% deze risicoscore. Kies de indicator",
                      " \u201cOndersteuningssignaal (wel/geen)\u201d voor het",
                      " omgekeerde: het aandeel van de hele populatie."))
    }
    NULL
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

  # Short headline for the exported slide. regio_titel() above is the figure's
  # own caption -- accurate but far too long for a slide title bar -- so the two
  # go to the template's separate SlideTitle and FigureTitle placeholders (see
  # tc_build_ppttc_slide_block() in utils/slide_download.R).
  regio_slide_titel <- reactive({
    req(input$r_var, input$r_regio, input$r_niveau)
    nm <- names(region_choices[[input$r_niveau]])[
      match(input$r_regio, region_choices[[input$r_niveau]])]
    sprintf("%s - %s, %s-%s", pretty_var(input$r_var), nm %||% input$r_regio,
            min(YEARS), max(YEARS))
  })

  # The figure's title stays an HTML heading above the plot rather than a plotly
  # layout(title=): the full selection string is too long for a plotly title bar,
  # and the Kaart tab titles its leaflet map the same way. It is still one
  # reactive shared by the figure and the export (figure_title below), which is
  # what lets a starred chart show its own title in Favorites instead of falling
  # back to the sub-tab name.
  output$r_titel <- renderText(regio_titel())

  # One source of truth for the line chart: the rows regio_data() returns plus
  # each line's legend label, as a factor in the order the chart draws them.
  # format_tc_data() inherits those factor levels, so an export lists its series
  # the way the figure does instead of alphabetically -- the reason the
  # thinkcell-export skill asks for factor-ordered data shared between plot and
  # download rather than a separately-built export table.
  regio_plot_data <- reactive({
    d <- copy(regio_data())  # copy: `:=` would otherwise mutate regio_data()'s cached value
    lv  <- unique(d$split_level)  # regio_data() is already ordered by split_level, year
    lab <- unname(pretty_level(lv, input$r_split, input$populatie))
    d[, reeks := factor(lab[match(split_level, lv)], levels = lab)]
    d[]
  })

  output$lijn <- renderPlotly({
    d <- regio_plot_data()
    validate(need(nrow(d) > 0, "Geen data voor deze selectie."))

    lv_lab <- levels(d$reeks)
    pal <- rep(ahti_branding$scale_discrete, length.out = length(lv_lab))

    p <- plot_ly(source = "lijn")
    for (i in seq_along(lv_lab)) {
      di <- d[reeks == lv_lab[i]]
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
        showlegend = length(lv_lab) > 1,
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

  # The 8 region values in the order venn_svg() wants them. Shared by the
  # figure on screen and by the SVG behind the download button, so the two can
  # never drift apart.
  venn_vals <- reactive({
    d <- venn_data()
    lev <- venn_levels(names(COMBO_GROUP_LABELS[[input$populatie]]))
    vapply(lev, function(level) {
      row <- d[split_level == level]
      if (nrow(row) == 0) NA_real_ else row$waarde[1]
    }, numeric(1))
  })

  # De venn hoort bij een risicoscore: hij kruist de ondersteuningscombinatie
  # met een waarde daarvan. Bij de twee afgeleide ondersteuningsindicatoren
  # bestaat die kruising niet (de ondersteuning zit daar zelf in
  # variable_value), en zou de figuur als volledig onderdrukt tekenen -- wat
  # als "geen waarnemingen" leest in plaats van als "niet van toepassing".
  venn_speelt <- reactive({
    req(input$r_var)
    !isTRUE(input$r_var %in% ONDERSTEUNING_INDICATOREN)
  })

  # Dezelfde slice als de venn, maar over alle waarden van de risicoscore. Dat
  # is precies wat de figuur niet kan tonen -- die staat per definitie op een
  # gekozen waarde -- en wat de tabel eronder toevoegt: per venn-vakje de hele
  # risicoverdeling.
  venn_matrix_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio,
        input$r_var, input$r_metric, input$r_venn_jaar)

    d <- ds |>
      filter(population    == !!input$populatie,
             region_level  == !!input$r_niveau,
             region_code   == !!input$r_regio,
             variable_name == !!input$r_var,
             metric_name   == !!input$r_metric,
             split_var     == !!COMBO_SPLIT_VAR[[input$populatie]],
             year          == !!as.integer(input$r_venn_jaar)) |>
      collect() |>
      as.data.table()

    add_display(d, input$r_weergave)
  })

  # De matrix achter de tabel: 8 deelgebieden x de waarden van de risicoscore,
  # plus per deelgebied zijn eigen noemer (n). Een ontbrekende rij blijft NA en
  # wordt "onvoldoende waarnemingen", nooit een nul.
  venn_matrix <- reactive({
    d   <- venn_matrix_data()
    lev <- venn_levels(names(COMBO_GROUP_LABELS[[input$populatie]]))
    # De waardenreeks komt uit de vocabulaire, niet uit de slice: zo krijgt een
    # regio waar een hele risicowaarde onderdrukt is toch die kolom, met
    # "onvoldoende waarnemingen" erin.
    waarden <- sort(unique(pop_vocab()[variable_name == input$r_var]$variable_value))

    m <- matrix(NA_real_, nrow = length(lev), ncol = length(waarden),
                dimnames = list(names(lev), waarden))
    n <- setNames(rep(NA_real_, length(lev)), names(lev))

    for (k in names(lev)) {
      rows <- d[split_level == lev[[k]] & variable_value %in% waarden]
      if (nrow(rows) == 0) next
      m[k, rows$variable_value] <- rows$waarde
      n[[k]] <- rows$denominator[1]
    }
    list(m = m, n = n, waarden = waarden)
  })

  # The venn is its own chart with its own year, so it needs its own title
  # rather than borrowing the line chart's -- and the downloaded SVG carries
  # it, which is what makes the file readable away from the dashboard.
  venn_titel <- reactive({
    req(input$r_var, input$r_val, input$r_metric, input$r_regio, input$r_venn_jaar)
    nm <- names(region_choices[[input$r_niveau]])[
      match(input$r_regio, region_choices[[input$r_niveau]])]
    sprintf("Risicostapeling naar ondersteuningscombinatie | %s = %s | %s (%s) | %s | %s",
            pretty_var(input$r_var), input$r_val,
            pretty_metric(input$r_metric), eenheid(input$r_weergave),
            nm %||% input$r_regio, input$r_venn_jaar)
  })

  output$venn <- renderUI({
    if (!venn_speelt()) {
      return(tags$div(class = "note", style = "text-align: center; padding: 28px 12px;",
                      "Het vennfiguur kruist de ondersteuningscombinatie met een",
                      " risicoscore. Bij ", tags$b(pretty_var(input$r_var)),
                      " zit de ondersteuning zelf al in de waarde, dus die kruising",
                      " bestaat niet. Kies hierboven een R-risicoscore om het",
                      " figuur en de tabel te zien."))
    }
    # No title: the heading above the figure already carries it on screen.
    HTML(venn_svg(venn_vals(), input$r_weergave,
                  names(COMBO_GROUP_LABELS[[input$populatie]]),
                  COMBO_GROUP_LABELS[[input$populatie]],
                  # Cosmetic input: fall back rather than block the figure on it.
                  palette = input$r_venn_pal %||% names(VENN_PALETTES)[1]))
  })

  output$venn_legenda <- renderUI({
    req(input$populatie)
    if (!venn_speelt()) return(NULL)
    gl <- COMBO_GROUP_UITLEG[[input$populatie]]
    tags$div(class = "note", style = "margin-top: 8px; text-align: center;",
             HTML(paste(sprintf("<b>%s</b> %s", names(gl), gl), collapse = "&nbsp;&nbsp;&middot;&nbsp;&nbsp;")))
  })

  # De figuur in tabelvorm: dezelfde acht deelgebieden, maar met de hele
  # risicoverdeling ernaast in plaats van een gekozen waarde.
  output$venn_tabel <- renderUI({
    if (!venn_speelt()) return(NULL)
    mm <- venn_matrix()
    tagList(
      div(class = "chart-title", style = "margin-top: 18px;",
          "Dezelfde acht groepen per risicoscore"),
      div(class = "note", style = "margin-bottom: 8px;",
          if (input$r_weergave == "rel")
            paste("Per rij verdeeld over de waarden van de risicoscore; elke rij telt op tot",
                  "100%. n is de omvang van die groep.")
          else
            "Aantallen per groep en risicowaarde. n is de omvang van die groep.",
          " Een streepje betekent onvoldoende waarnemingen, geen nul."),
      HTML(venn_matrix_html(mm$m, mm$n, input$r_weergave,
                            names(COMBO_GROUP_LABELS[[input$populatie]]),
                            COMBO_GROUP_LABELS[[input$populatie]],
                            var_label = pretty_var(input$r_var)))
    )
  })

  # De twee knoppen onder de venn horen bij een figuur dat er niet altijd is.
  output$venn_downloads <- renderUI({
    if (!venn_speelt()) return(NULL)
    div(style = "text-align: center; margin-top: 14px;",
        downloadButton("r_venn_dl", "Download figuur (svg)", class = "btn-default"),
        downloadButton("r_venn_dl_data", "Download data (xlsx)", class = "btn-default"))
  })

  # -------------------------------------------------------------- Downloads ---
  # The Kaart tab keeps its plain xlsx export (a choropleth has no think-cell
  # equivalent); the Per regio line chart is wired to the shared export layer in
  # utils/ -- raw xlsx, think-cell xlsx, slide .pptx, favorites and export
  # history (PLAN.md §4, stap 7). Wiring a second chart means repeating the
  # ui/server pair, never reimplementing any of it here.

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

  # The table behind every Per regio export: exactly the rows the line chart
  # draws, under the same Dutch column names the raw download has always used.
  # jaar / reeks / weergegeven_waarde are the category / series / value columns
  # the think-cell matrix is pivoted from; the rest rides along in the raw sheet
  # so n, noemer and the CBS codes stay checkable.
  regio_export_data <- reactive({
    d <- regio_plot_data()
    out <- export_cols(d)
    out[, reeks := d$reeks]
    out[]
  })

  # Registered once for the whole app: labels each export's provenance log with
  # the dashboard name and the active tab / sub-tab. dl_option_prefixes scopes
  # the "selected options" section per chart -- without it every input in the
  # app lands in the line chart's log, including the Kaart tab's k_* selectors
  # and the r_venn_* ones, which belong to the venn below the chart, not to the
  # line.
  tc_register_app_context(
    input,
    dashboard_title = "Dynamo Amsterdam",
    nav_id = "hoofdtab",
    subtab_by_tab = c("Iteratie 1" = "subtab"),
    dl_option_prefixes = c(
      "r_downloads" = "^(populatie|r_niveau|r_regio|r_var|r_val|r_metric|r_split|r_weergave)$"
    )
  )

  chart_data_downloads_server(
    id           = "r_downloads",
    data         = regio_export_data,
    chart_type   = "line",
    category_col = "jaar",
    series_col   = "reeks",
    value_col    = "weergegeven_waarde",
    filename_prefix = "dynamo_regio",
    # The delivery is already aggregated: one row per jaar x reeks, so there is
    # nothing left to aggregate and a duplicate pair would be a real bug.
    agg_fun      = NULL,
    slide_title  = regio_slide_titel,
    figure_title = regio_titel,
    source_output = RA_OUTPUT_ID,
    source_sheet  = reactive({
      req(input$populatie)
      f <- RA_SOURCE_FILE[input$populatie]
      if (is.na(f)) "" else unname(f)
    }),
    source_mtime = APP_DATA_MTIME
  )

  # The venn's own slice: a different year and a different split than the line
  # chart above it, so the export panel next to that chart does not cover it.
  # No think-cell route either -- like the choropleth, a venn has no template.
  # Twee tabbladen: de slice achter de figuur (een risicowaarde) en de slice
  # achter de tabel (alle risicowaarden). De tabel is strikt ruimer, maar de
  # figuur-slice apart houden scheelt de lezer het uitfilteren van de waarde
  # waar de figuur op staat.
  output$r_venn_dl_data <- downloadHandler(
    filename = function() sprintf("dynamo_venn_%s_%s.xlsx", input$r_venn_jaar, Sys.Date()),
    content  = function(file) write_xlsx(
      list(figuur = export_cols(venn_data()),
           risicomatrix = export_cols(venn_matrix_data())), file)
  )

  # Vector, not a bitmap: the figure is already an SVG, so the download is the
  # same drawing with a title, a source line and the bits a standalone file
  # needs. Written with useBytes so the file is byte-identical to what
  # venn_svg() produced, whatever locale the R process runs under.
  output$r_venn_dl <- downloadHandler(
    filename    = function() sprintf("dynamo_venn_%s_%s.svg", input$r_venn_jaar, Sys.Date()),
    contentType = "image/svg+xml",
    content = function(file) {
      svg <- venn_svg(venn_vals(), input$r_weergave,
                      names(COMBO_GROUP_LABELS[[input$populatie]]),
                      COMBO_GROUP_LABELS[[input$populatie]],
                      palette = input$r_venn_pal %||% names(VENN_PALETTES)[1],
                      title = venn_titel(),
                      caption = paste(
                        "Bron: CBS microdata via de Remote Access-omgeving.",
                        "Cellen onder de 10 zijn onderdrukt en tellen niet als nul;",
                        "waarden zijn afgerond op tientallen."),
                      standalone = TRUE)
      # base::file, spelled out: the handler's own argument is called `file`.
      con <- base::file(file, open = "wb")
      on.exit(close(con))
      writeLines(svg, con, useBytes = TRUE)
    }
  )

  # The three shared tabs. They read the same state/ files any chart writes to,
  # so nothing here needs to know which charts are wired up.
  favorites_panel_server("favorieten")
  export_history_panel_server("exporthistorie")
  template_admin_server("templates")
}

shinyApp(ui, server)
