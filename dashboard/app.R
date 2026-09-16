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
source("utils/map_download.R")

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

# Westpoort is haven- en bedrijventerrein: twee wijken, nauwelijks huishoudens.
# Op de kaart kleurt het mee als een gewone wijk en trekt het door zijn kleine
# aantallen de schaal scheef, terwijl er inhoudelijk niets te zien is. Het
# stadsdeel blijft daarom overal buiten beeld -- kaart, regiokeuze, tabel en
# downloads. De data zelf blijft ongemoeid: dit is een weergavekeuze, geen
# correctie op de levering.
UITGESLOTEN_STADSDEEL <- "Westpoort"

geo <- lapply(geo, function(g) g[!(!is.na(g$stadsdeel) & g$stadsdeel == UITGESLOTEN_STADSDEEL), ])

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

POPULATIONS  <- sort(unique(vocab$population))
YEARS        <- sort(unique(vocab$year))

# De kaart kent geen gemeentevlak (dat is de buitenrand van alle stadsdelen
# samen, en als choropleth van een regio zinloos); de tabbladen die een regio
# uitkiezen kennen "Heel Amsterdam" wel -- dat is juist de vergelijkingsbasis.
MAP_LEVELS   <- c("buurt", "wijk", "gebied", "stadsdeel")
REGIO_LEVELS <- c(MAP_LEVELS, "gemeente")

GEMEENTE_CODE <- "Amsterdam"
GEMEENTE_NAAM <- "Heel Amsterdam"

# Stadsdeel om op in te zoomen, of de hele stad. Zo is een kaart van alleen
# Oost te maken, zonder de andere stadsdelen eromheen.
SCOPE_ALLES <- "Heel Amsterdam"
STADSDELEN  <- sort(unique(geo$stadsdeel$region_code))

# Opening view: the city itself, not a default that includes Haarlem and Almere.
AMS_BBOX <- st_bbox(geo$stadsdeel)

# Region code -> name, per level, from the geometry (the delivery carries codes
# only). Gemeente heeft geen geometrie en komt uit de data zelf.
region_choices <- lapply(geo, function(g) {
  d <- st_drop_geometry(g)
  setNames(d$region_code, d$region_name)[order(d$region_name)]
})
region_choices$gemeente <- setNames(GEMEENTE_CODE, GEMEENTE_NAAM)

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

# De combinatie als indicator: variable_value is dan het combinatieniveau zelf.
# Dat is wat de venn leest als er geen risicoscore gekozen is.
COMBO_INDICATOR <- c(
  "huishoudens met kinderen" = "O_MPG_combinatie",
  "ouderen (65+)"            = "O_OUD_combinatie"
)
# Sentinel voor "geen risicoscore" in de keuzelijst bij de venn.
VENN_GEEN_VAR <- "(alle)"

# De losse risicofactoren van een populatie, zonder de cumulatieve score: de
# kolommen van de risicofactor-tabel onder de venn.
RISICO_FACTOREN <- list(
  "huishoudens met kinderen" = setdiff(names(RISICO_LABELS_HHKIND), "R_MPG_totaal"),
  "ouderen (65+)"            = setdiff(names(RISICO_LABELS_OUD), "R_OUD_totaal")
)

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
# "R_MPG1_armoede_hh" -> "R1": een kolomkop die in een tabelcel past. De
# volledige omschrijving rijdt mee als hover-title en in de legenda eronder.
risico_code <- function(x) sub("^R_(MPG|OUD)([0-9]+)_.*$", "R\\2", x)

pretty_ondersteuning <- function(x) {
  x <- as.character(x)
  if (length(x) == 0L) return(character(0))  # ifelse() zou hier logical(0) geven
  lab <- ONDERSTEUNING_NIVEAU_LABELS[x]
  unname(ifelse(is.na(lab), x, lab))
}

# "Waarde van de indicator". De risicoscores houden hun ruwe waarde (0/1/2/
# 3plus, zie PLAN.md 6, open punt 2); bij de afgeleide indicatoren is de
# waarde zelf een categorie en krijgt hij zijn label mee.
pretty_value <- function(x, variable_name, population = NULL) {
  # De combinatie-indicator draagt het combinatieniveau als waarde, dus die
  # krijgt de groepsnamen; "onbekend" is de restcategorie en staat in
  # ONDERSTEUNING_NIVEAU_LABELS.
  if (!is.null(population) && isTRUE(variable_name == COMBO_INDICATOR[[population]])) {
    lab <- pretty_combo_level(x, COMBO_GROUP_LABELS[[population]])
    los <- ONDERSTEUNING_NIVEAU_LABELS[as.character(x)]
    return(unname(ifelse(is.na(los), lab, los)))
  }
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
                selectInput("k_niveau", "Regioniveau", choices = MAP_LEVELS, selected = "wijk"),
                selectInput("k_scope", "Toon", choices = c(SCOPE_ALLES, STADSDELEN))
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
              downloadButton("k_dl_fig", "Download kaart (png)", class = "btn-default"),
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
                selectInput("r_niveau", "Regioniveau", choices = REGIO_LEVELS, selected = "gemeente"),
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
                column(4, div("Ondersteuning naar combinatie", class = "chart-title")),
                column(4, selectInput("r_venn_var", "Kleur de venn naar", choices = NULL)),
                column(2, selectInput("r_venn_jaar", "Jaar", choices = YEARS, selected = max(YEARS))),
                column(2, selectInput("r_venn_pal", "Kleurenschaal", choices = names(VENN_PALETTES)))
              ),
              conditionalPanel(
                "input.r_venn_var != '(alle)'",
                fluidRow(column(4, selectInput("r_venn_val", "Waarde van de indicator", choices = NULL)))
              ),
              uiOutput("venn_uitleg"),
              uiOutput("venn"),
              uiOutput("venn_legenda"),
              uiOutput("venn_tabel"),
              uiOutput("risico_tabel"),
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
                      setNames(vals, pretty_value(vals, input$k_var, input$populatie)), cur)
  })
  observeEvent(list(input$populatie, input$r_var), {
    req(input$r_var)
    req(input$r_var %in% pop_vocab()$variable_name)
    vals <- sort(unique(pop_vocab()[variable_name == input$r_var]$variable_value))
    cur <- isolate(input$r_val)
    freezeReactiveValue(input, "r_val")
    update_preserving(session, "r_val",
                      setNames(vals, pretty_value(vals, input$r_var, input$populatie)), cur)
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
      if (isTRUE(grepl("_combinatie$", var_name))) {
        tags$div(class = "note", style = "margin: -6px 0 10px;",
                 "Afgeleid uit de ondersteuningscombinaties: welke van de drie",
                 " groepen tegelijk spelen. Bij \u201cAandeel (%)\u201d is de noemer",
                 " de hele populatie, dus dat leest als het percentage dat in dat",
                 " deelgebied van de venn valt. \u201cNiet toe te wijzen\u201d is het",
                 " deel dat door CBS-onderdrukking aan geen enkel deelgebied",
                 " toegewezen kon worden.")
      } else if (isTRUE(grepl("_aantal_vormen$", var_name))) {
        tags$div(class = "note", style = "margin: -6px 0 10px;",
                 "Afgeleid uit de ondersteuningscombinaties. De levering telt die",
                 " alleen gekruist met een risicoscore, dus lang niet elke categorie",
                 " is overal af te leiden. Wat overblijft staat als",
                 " \u201cNiet toe te wijzen\u201d in de waardelijst: de noemer is dus",
                 " altijd de hele populatie en de getoonde categorie\u00ebn kloppen,",
                 " ook waar die restcategorie groot is. Kijk er even naar voordat je",
                 " buurten onderling vergelijkt.")
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

  # De kaartlaag: de geometrie van het gekozen niveau, begrensd tot het gekozen
  # stadsdeel, met de cijfers eraan. Een reactive in plaats van inline in de
  # tekenstap, want de download tekent exact dezelfde laag.
  kaart_geo <- reactive({
    req(input$k_niveau)
    g <- geo[[input$k_niveau]]
    scope <- input$k_scope %||% SCOPE_ALLES
    if (!identical(scope, SCOPE_ALLES)) g <- g[!is.na(g$stadsdeel) & g$stadsdeel == scope, ]
    merge(g, kaart_data()[, .(region_code, waarde, metric_value, n_totaal)],
          by = "region_code", all.x = TRUE)
  })

  # De klassegrenzen worden hier berekend en niet aan colorBin() overgelaten,
  # zodat de kaart op het scherm en de gedownloade figuur aantoonbaar dezelfde
  # kleuren en dezelfde legenda hebben.
  kaart_bins <- reactive({
    w <- kaart_geo()$waarde
    if (all(is.na(w))) return(numeric(0))
    b <- unique(pretty(range(w, na.rm = TRUE), 6))
    if (length(b) < 2) b <- c(min(w, na.rm = TRUE) - 0.5, max(w, na.rm = TRUE) + 0.5)
    b
  })

  # Inzoomen als de gebruiker een stadsdeel kiest -- dat is de hele reden voor
  # die keuze. Alleen hierop, niet bij elke andere selector: dan zou de kaart
  # de pan/zoom van de gebruiker steeds terugzetten.
  observeEvent(input$k_scope, {
    req(input$k_scope)
    bb <- if (identical(input$k_scope, SCOPE_ALLES)) AMS_BBOX else {
      st_bbox(geo$stadsdeel[geo$stadsdeel$region_code == input$k_scope, ])
    }
    leafletProxy("kaart") |>
      fitBounds(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]])
  }, ignoreInit = TRUE)

  # Redraw only the polygons, via a proxy, so changing a selector does not reset
  # the user's pan/zoom.
  observe({
    m <- kaart_geo()
    req(input$k_niveau)

    proxy <- leafletProxy("kaart") |> clearShapes() |> clearControls()

    if (all(is.na(m$waarde))) {
      proxy |> addPolygons(data = m, fillColor = "#e0e0e0", fillOpacity = 0.7,
                           color = "#fff", weight = 1,
                           label = "Geen data voor deze selectie")
      return()
    }

    pal <- colorBin("YlOrRd", domain = m$waarde, bins = kaart_bins(),
                    na.color = "#e0e0e0")

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

  # -- Ondersteuning naar combinatie (venn) ------------------------------------
  # Toont altijd de O_MPG_combination/O_OUD_combination-verdeling voor de regio
  # + metric hierboven, voor een eigen gekozen jaar (een venn is een
  # momentopname, geen tijdreeks) en een eigen gekozen kleuring. Die kleuring
  # is los van het lijndiagram: bij "(alle)" is het de verdeling zelf -- welk
  # deel van de populatie in welk deelgebied zit -- en bij een risicoscore het
  # aandeel daarvan binnen elk deelgebied.

  # Keuzelijst: "(alle)" plus de risicoscores van deze populatie. De afgeleide
  # ondersteuningsindicatoren staan er niet in; die zeggen zelf al iets over de
  # ondersteuning en kruisen dus niet met de combinatie.
  observeEvent(input$populatie, {
    req(input$populatie)
    vars <- sort(intersect(unique(pop_vocab()$variable_name), names(RISICO_LABELS)))
    ch <- c(setNames(VENN_GEEN_VAR, "(alle) \u2013 de verdeling zelf"), named(vars, pretty_var))
    cur <- isolate(input$r_venn_var)
    for (i in c("r_venn_var", "r_venn_val")) freezeReactiveValue(input, i)
    update_preserving(session, "r_venn_var", ch, cur)
  }, ignoreInit = FALSE)

  observeEvent(list(input$populatie, input$r_venn_var), {
    req(input$r_venn_var)
    if (identical(input$r_venn_var, VENN_GEEN_VAR)) return()
    req(input$r_venn_var %in% pop_vocab()$variable_name)
    vals <- sort(unique(pop_vocab()[variable_name == input$r_venn_var]$variable_value))
    cur <- isolate(input$r_venn_val)
    freezeReactiveValue(input, "r_venn_val")
    update_preserving(session, "r_venn_val",
                      setNames(vals, pretty_value(vals, input$r_venn_var, input$populatie)), cur)
  })

  venn_zonder_score <- reactive(identical(input$r_venn_var %||% VENN_GEEN_VAR, VENN_GEEN_VAR))

  # Bij "(alle)" komt het cijfer uit de combinatie-indicator: daar is het
  # combinatieniveau de variable_value, dus is de noemer de hele populatie en
  # leest het percentage als "dit deel van de gezinnen zit in dit deelgebied".
  # Met een risicoscore komt het uit de combinatie-uitsplitsing en is de noemer
  # het deelgebied zelf.
  venn_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio, input$r_metric, input$r_venn_jaar)

    q <- ds |>
      filter(population   == !!input$populatie,
             region_level == !!input$r_niveau,
             region_code  == !!input$r_regio,
             metric_name  == !!input$r_metric,
             year         == !!as.integer(input$r_venn_jaar))

    d <- if (venn_zonder_score()) {
      q |> filter(variable_name == !!unname(COMBO_INDICATOR[[input$populatie]])) |>
        collect() |> as.data.table()
    } else {
      req(input$r_venn_val)
      q |> filter(variable_name  == !!input$r_venn_var,
                  variable_value == !!input$r_venn_val,
                  split_var      == !!COMBO_SPLIT_VAR[[input$populatie]]) |>
        collect() |> as.data.table()
    }
    # Het combinatieniveau zit in de ene vorm in variable_value en in de andere
    # in split_level. Een extra kolom in plaats van een hernoeming, want de
    # export heeft de oorspronkelijke kolommen nodig.
    if (nrow(d) > 0) {
      d[, niveau := if (venn_zonder_score()) variable_value else split_level]
    } else {
      d[, niveau := character()]
    }
    add_display(d, input$r_weergave)
  })

  # The 8 region values in the order venn_svg() wants them. Shared by the
  # figure on screen and by the SVG behind the download button, so the two can
  # never drift apart.
  venn_vals <- reactive({
    d <- venn_data()
    lev <- venn_levels(names(COMBO_GROUP_LABELS[[input$populatie]]))
    vapply(lev, function(level) {
      row <- d[niveau == level]
      if (nrow(row) == 0) NA_real_ else row$waarde[1]
    }, numeric(1))
  })

  # Dezelfde slice als de venn, maar over alle waarden van de gekozen
  # risicoscore -- wat de figuur per definitie niet kan tonen, want die staat op
  # een waarde. Bij "(alle)" is er niets uit te splitsen en vervalt de tabel.
  venn_matrix_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio, input$r_metric, input$r_venn_jaar)
    req(!venn_zonder_score(), input$r_venn_var)

    d <- ds |>
      filter(population    == !!input$populatie,
             region_level  == !!input$r_niveau,
             region_code   == !!input$r_regio,
             variable_name == !!input$r_venn_var,
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
    waarden <- sort(unique(pop_vocab()[variable_name == input$r_venn_var]$variable_value))

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

  # De tweede tabel: dezelfde acht deelgebieden, maar met de losse
  # risicofactoren als kolommen in plaats van de waarden van een score. Elke
  # cel is het aandeel van dat deelgebied waar die risicofactor speelt
  # (variable_value "1"), dus deze tabel staat los van de gekozen risicoscore.
  risico_matrix_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio, input$r_metric, input$r_venn_jaar)
    factoren <- RISICO_FACTOREN[[input$populatie]]

    d <- ds |>
      filter(population     == !!input$populatie,
             region_level   == !!input$r_niveau,
             region_code    == !!input$r_regio,
             variable_name %in% !!factoren,
             variable_value == "1",
             metric_name    == !!input$r_metric,
             split_var      == !!COMBO_SPLIT_VAR[[input$populatie]],
             year           == !!as.integer(input$r_venn_jaar)) |>
      collect() |>
      as.data.table()

    add_display(d, input$r_weergave)
  })

  risico_matrix <- reactive({
    d   <- risico_matrix_data()
    lev <- venn_levels(names(COMBO_GROUP_LABELS[[input$populatie]]))
    factoren <- RISICO_FACTOREN[[input$populatie]]

    m <- matrix(NA_real_, nrow = length(lev), ncol = length(factoren),
                dimnames = list(names(lev), factoren))
    n <- setNames(rep(NA_real_, length(lev)), names(lev))
    for (k in names(lev)) {
      rows <- d[split_level == lev[[k]] & variable_name %in% factoren]
      if (nrow(rows) == 0) next
      m[k, rows$variable_name] <- rows$waarde
      # De noemer van elke cel is het deelgebied zelf, en die is voor elke
      # risicofactor dezelfde -- dus dat is meteen de omvang van de groep.
      n[[k]] <- rows$denominator[1]
    }
    list(m = m, n = n)
  })

  # De venn is zijn eigen figuur met zijn eigen jaar en kleuring, dus hij heeft
  # ook zijn eigen titel -- en de gedownloade SVG draagt hem, wat het bestand
  # leesbaar maakt los van het dashboard dat hem maakte.
  venn_titel <- reactive({
    req(input$r_metric, input$r_regio, input$r_venn_jaar)
    nm <- names(region_choices[[input$r_niveau]])[
      match(input$r_regio, region_choices[[input$r_niveau]])]
    kleuring <- if (venn_zonder_score()) "verdeling over de ondersteuningscombinaties"
                else sprintf("%s = %s", pretty_var(input$r_venn_var), input$r_venn_val %||% "")
    sprintf("Ondersteuning naar combinatie | %s | %s (%s) | %s | %s",
            kleuring, pretty_metric(input$r_metric), eenheid(input$r_weergave),
            nm %||% input$r_regio, input$r_venn_jaar)
  })

  output$venn_uitleg <- renderUI({
    req(input$populatie)
    tags$div(class = "note", style = "margin-bottom: 10px;",
      "Dode ruimte buiten de cirkels = geen van de drie groepen; het overlappende",
      " gebied = beide/alle groepen tegelijk. De kleurenschaal loopt over de zeven",
      " cirkelvlakken; de dode ruimte valt erbuiten, anders bepaalt die in haar",
      " eentje de hele schaal. ",
      if (venn_zonder_score())
        tags$b("Nu gekleurd naar de verdeling zelf: welk deel van de populatie in welk deelgebied zit.")
      else
        tags$b(sprintf("Nu gekleurd naar %s = %s, als aandeel binnen elk deelgebied.",
                       pretty_var(input$r_venn_var), input$r_venn_val %||% "")))
  })

  output$venn <- renderUI({
    # No title: the heading above the figure already carries it on screen.
    HTML(venn_svg(venn_vals(), input$r_weergave,
                  names(COMBO_GROUP_LABELS[[input$populatie]]),
                  COMBO_GROUP_LABELS[[input$populatie]],
                  # Cosmetic input: fall back rather than block the figure on it.
                  palette = input$r_venn_pal %||% names(VENN_PALETTES)[1]))
  })

  output$venn_legenda <- renderUI({
    req(input$populatie)
    gl <- COMBO_GROUP_UITLEG[[input$populatie]]
    tags$div(class = "note", style = "margin-top: 8px; text-align: center;",
             HTML(paste(sprintf("<b>%s</b> %s", names(gl), gl), collapse = "&nbsp;&nbsp;&middot;&nbsp;&nbsp;")))
  })

  # De figuur in tabelvorm: dezelfde acht deelgebieden, maar met de hele
  # risicoverdeling ernaast in plaats van een gekozen waarde.
  output$venn_tabel <- renderUI({
    if (venn_zonder_score()) return(NULL)
    mm <- venn_matrix()
    tagList(
      div(class = "chart-title", style = "margin-top: 18px;",
          "Dezelfde acht groepen per waarde van de risicoscore"),
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
                            var_label = pretty_var(input$r_venn_var))))
  })

  # De risicofactor-tabel: acht deelgebieden x de losse risicofactoren.
  output$risico_tabel <- renderUI({
    req(input$populatie, input$r_venn_jaar)
    rm <- risico_matrix()
    factoren <- colnames(rm$m)

    # Niet elke risicofactor loopt tot 2024: armoede stopt na 2023 en
    # betalingsachterstand zorgverzekering na 2022 -- die bronregisters zitten
    # niet in de laatste jaren van de levering. Dat is iets anders dan een
    # onderdrukte cel, en zonder dit onderschrift zou het streepje in die
    # kolommen als "te weinig waarnemingen" gelezen worden.
    jaar <- as.integer(input$r_venn_jaar)
    in_jaar <- unique(pop_vocab()[year == jaar]$variable_name)
    ontbreekt <- setdiff(factoren, in_jaar)

    tagList(
      div(class = "chart-title", style = "margin-top: 22px;",
          "Risicofactoren per ondersteuningsgroep"),
      div(class = "note", style = "margin-bottom: 8px;",
          if (input$r_weergave == "rel")
            "Per cel: het aandeel van die ondersteuningsgroep waarbij deze risicofactor speelt."
          else
            "Per cel: het aantal binnen die ondersteuningsgroep waarbij deze risicofactor speelt.",
          " Rijen tellen hier niet op tot 100%: een huishouden/oudere kan meerdere",
          " risicofactoren tegelijk hebben. Een streepje betekent onvoldoende waarnemingen."),
      HTML(venn_matrix_html(rm$m, rm$n, input$r_weergave,
                            names(COMBO_GROUP_LABELS[[input$populatie]]),
                            COMBO_GROUP_LABELS[[input$populatie]],
                            var_label = "Risicofactor",
                            kolomlabels = risico_code(factoren),
                            kolomtitels = unname(pretty_var(factoren)),
                            n_label = "n")),
      div(class = "note", style = "margin-top: 6px;",
          HTML(paste(sprintf("<b>%s</b> %s", risico_code(factoren),
                             venn_esc(unname(pretty_var(factoren)))),
                     collapse = "&nbsp;&nbsp;&middot;&nbsp;&nbsp;"))),
      if (length(ontbreekt)) {
        div(class = "note", style = "margin-top: 6px;",
            tags$b(sprintf("Niet in %d: %s.", jaar,
                           paste(risico_code(ontbreekt), collapse = ", "))),
            " Die bronregisters lopen niet door tot dit jaar; de lege kolom",
            " betekent hier dus niet onvoldoende waarnemingen. Kies een eerder",
            " jaar om ze te zien.")
      })
  })

  # De twee knoppen onder de venn horen bij een figuur dat er altijd is.
  output$venn_downloads <- renderUI({
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

  # De kaart als plaatje. Leaflet tekent in de browser en laat zich hier niet
  # wegschrijven, dus choropleth_ggplot() tekent dezelfde laag opnieuw met
  # ggplot2 -- met dezelfde klassegrenzen (kaart_bins()), zodat de figuur en het
  # scherm dezelfde indeling en kleuren hebben.
  output$k_dl_fig <- downloadHandler(
    filename = function() sprintf("dynamo_kaart_%s_%s.png", input$k_niveau, Sys.Date()),
    contentType = "image/png",
    content = function(file) {
      laag <- kaart_geo()
      scope <- input$k_scope %||% SCOPE_ALLES
      p <- choropleth_ggplot(
        laag, kaart_bins(), input$k_weergave,
        titel = sprintf("%s = %s", pretty_var(input$k_var), input$k_val),
        ondertitel = sprintf("%s (%s) | %s | %s%s",
                             pretty_metric(input$k_metric), eenheid(input$k_weergave),
                             input$k_jaar, input$k_niveau,
                             if (identical(scope, SCOPE_ALLES)) ", heel Amsterdam"
                             else sprintf(", stadsdeel %s", scope)),
        bron = "Bron: CBS microdata via de Remote Access-omgeving.")
      # Een kaart van een stadsdeel is hoger dan breed, de hele stad juist niet;
      # het formaat volgt de verhouding van de laag zodat er geen witruimte
      # naast de kaart komt te staan.
      bb <- sf::st_bbox(laag)
      ratio <- as.numeric((bb["ymax"] - bb["ymin"]) / (bb["xmax"] - bb["xmin"]))
      breedte <- 9
      ggplot2::ggsave(file, p, width = breedte,
                      height = max(5, min(14, breedte * ratio * 0.75 + 2.2)),
                      dpi = 200, units = "in", bg = "white")
    }
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
    content  = function(file) {
      # venn_data() draagt het combinatieniveau als `niveau` -- bij "(alle)"
      # zit het in variable_value, anders in split_level -- dus dat wordt hier
      # teruggezet op de kolomnaam die de export altijd had.
      bladen <- list(figuur = export_cols(venn_data()),
                     risicofactoren = export_cols(risico_matrix_data()))
      # De risicomatrix bestaat alleen als er een score gekozen is.
      if (!venn_zonder_score()) {
        bladen$risicomatrix <- export_cols(venn_matrix_data())
      }
      write_xlsx(bladen, file)
    }
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
