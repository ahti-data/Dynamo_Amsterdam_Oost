# Dynamo Amsterdam Oost -- internal dashboard, iteratie 1.
#
# Reads data/app_data/, built by data-prep/01_build_app_data.R from the CBS RA
# delivery. Run that script first after a new delivery; the app does no
# aggregation of its own beyond filtering and the share calculation.

source("data/metadata/brand_colors.R")
source("data/metadata/variable_labels.R")
source("data/metadata/changelog.R")

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

# `%||%` zit pas sinds R 4.4 in base. De app gebruikt hem op tientallen plekken
# (en utils/slide_download.R rekent op een app-niveau versie), dus hem hier
# neerzetten waar hij ontbreekt scheelt een stille afhankelijkheid van de
# R-versie op de server.
if (!exists("%||%")) `%||%` <- function(x, y) if (is.null(x)) y else x

source("utils/splits.R")
source("utils/metrics.R")
source("utils/venn_diagram.R")
source("utils/map.R")
source("utils/changelog_ui.R")

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

# Levering output_1b draagt de exacte groepsomvang mee (`n_split`, uit
# n_totaal_region_splitvar). Daarop staat de noemer van elk aandeel en de n-kolom
# onder de venn. Een parquet van voor die levering heeft de kolom niet; dan valt
# de app terug op de oude, uit de categorieen teruggerekende noemer en zegt hij
# dat met zoveel woorden -- liever een dashboard dat blijft werken met een
# zichtbare kanttekening dan een dashboard dat niet opstart omdat de prep-stap
# nog moet draaien.
HEEFT_N_SPLIT <- "n_split" %in% names(ds)

# Westpoort is haven- en bedrijventerrein: twee wijken, nauwelijks huishoudens.
# Op de kaart kleurt het mee als een gewone wijk en trekt het door zijn kleine
# aantallen de schaal scheef, terwijl er inhoudelijk niets te zien is. Het
# stadsdeel blijft daarom overal buiten beeld -- kaart, regiokeuze, tabel en
# downloads. De data zelf blijft ongemoeid: dit is een weergavekeuze, geen
# correctie op de levering.
UITGESLOTEN_STADSDEEL <- "Westpoort"

GEMEENTE_CODE <- "Amsterdam"
GEMEENTE_NAAM <- "Heel Amsterdam"

geo <- lapply(geo, function(g) g[!(!is.na(g$stadsdeel) & g$stadsdeel == UITGESLOTEN_STADSDEEL), ])

# Het gemeentevlak: de stadsdelen aan elkaar. Hier afgeleid en niet in de
# prep-stap, omdat het geen nieuwe geometrie is maar de buitenrand van wat er al
# staat -- en omdat het pas klopt nadat Westpoort eruit is (dat is een
# weergavekeuze van deze app, niet van de levering). Een choropleth van een
# enkel vlak zegt niets over de spreiding, maar laat wel het cijfer voor de hele
# stad zien, en daar is het hier om te doen.
geo$gemeente <- {
  g <- sf::st_sf(region_code = GEMEENTE_CODE, region_name = GEMEENTE_NAAM,
                 stadsdeel = NA_character_,
                 geometry = sf::st_union(sf::st_geometry(geo$stadsdeel)))
  sf::st_make_valid(g)
}

# Provenance stamped into every export (tc_build_datasheet_log() in
# utils/slide_download.R): which RA delivery a chart's numbers came from, and
# when this app's own prepped copy of that delivery was last rebuilt. De ruwe
# levering blijft op de machine van de analist en wordt nooit gedeployd, dus de
# parquet-uitvoer van data-prep/01_build_app_data.R -- wat de app echt leest en
# wat meegaat -- is het bestand waarvan de datum de cijfers op het scherm
# beschrijft.
#
# Welke levering dat is, staat naast die parquet (source_info.rds) en niet als
# constante hier: zo hoeft bij een volgende levering alleen de prep-stap bij en
# kan de app nooit een andere levering noemen dan hij inleest.
RA_SOURCE_INFO <- local({
  f <- file.path(DATA_DIR, "source_info.rds")
  if (file.exists(f)) readRDS(f) else list()
})
RA_OUTPUT_ID   <- RA_SOURCE_INFO$output_id %||% "output_1b"
RA_SOURCE_FILE <- RA_SOURCE_INFO$files     %||% character(0)
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

# De keuzelijsten zetten "alle"/"elk niveau apart" als schildwacht naast de
# echte niveaus. Draagt een levering diezelfde tekst ooit als waarde, dan zou
# het dashboard stil de verkeerde rijen tonen; dan liever hier niet opstarten.
split_check_keuzes(vocab$split_level)

POPULATIONS  <- sort(unique(vocab$population))
YEARS        <- sort(unique(vocab$year))

# Welke stadsdelen de levering op elk regioniveau dekt. Niet elke levering gaat
# even diep over de hele stad: `output_1b` levert buurt en wijk alleen voor
# Oost (63 buurten, 15 wijken) en pas vanaf gebiedsniveau de hele stad. Op de
# kaart is dat niet te onderscheiden van onderdrukking -- allebei een grijs
# vlak -- en dat is precies het verschil dat dit project niet mag vervagen. Uit
# de data halen en niet vastzetten: een volgende levering kan weer breder zijn.
DEKKING <- ds |>
  select(region_level, region_code) |>
  distinct() |>
  collect() |>
  as.data.table()
DEKKING <- merge(DEKKING,
                 unique(rbindlist(lapply(names(geo), function(lvl) {
                   d <- sf::st_drop_geometry(geo[[lvl]])
                   data.table(region_level = lvl, region_code = d$region_code,
                              stadsdeel = d$stadsdeel)
                 }))),
                 by = c("region_level", "region_code"))
# Per niveau: welke stadsdelen erin zitten, en hoeveel er in de geometrie zijn.
DEKKING_STADSDELEN <- DEKKING[, .(stadsdelen = list(sort(unique(stadsdeel)))), by = region_level]

# Gemeente staat onderaan, na de fijnere niveaus: als choropleth is een enkel
# vlak nutteloos -- er valt niets te vergelijken -- maar het is de snelste manier
# om het cijfer voor de hele stad te zien zonder van tabblad te wisselen, en dat
# is waarvoor het erin zit.
MAP_LEVELS   <- c("buurt", "wijk", "gebied", "stadsdeel", "gemeente")
REGIO_LEVELS <- MAP_LEVELS

# Stadsdeel om op in te zoomen, of de hele stad. Zo is een kaart van alleen
# Oost te maken, zonder de andere stadsdelen eromheen.
SCOPE_ALLES <- "Heel Amsterdam"
STADSDELEN  <- sort(unique(geo$stadsdeel$region_code))

# Opening view: the city itself, not a default that includes Haarlem and Almere.
AMS_BBOX <- st_bbox(geo$stadsdeel)

# Region code -> name, per level, from the geometry (the delivery carries codes
# only). Gemeente zit er sinds het gemeentevlak hierboven gewoon bij.
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
# benoemen.
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
  "huishoudens met kinderen" = setdiff(names(RISICO_LABELS_HHKIND), RISICO_TOTAAL_HHKIND),
  "ouderen (65+)"            = setdiff(names(RISICO_LABELS_OUD),    RISICO_TOTAAL_OUD)
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

METRIC_LABELS <- c(average_score = "gemiddelde score")

pretty_metric <- function(x) {
  known <- METRIC_LABELS[x]
  out <- gsub("_", " ", sub("^n_", "aantal ", x))
  out <- sub("aantal ouderen with var value", "aantal ouderen", out)
  unname(ifelse(is.na(known), out, known))
}

# Een enkele splitsvariabele. pretty_split() hieronder zet er samengestelde
# uitsplitsingen omheen.
SPLIT_VAR_LABELS <- c(ONDERSTEUNING_SPLIT_LABELS,
                      O_MPG_combination = "ondersteuningscombinatie",
                      O_OUD_combination = "ondersteuningscombinatie")

pretty_split_1 <- function(x) {
  known <- SPLIT_VAR_LABELS[x]
  fallback <- ifelse(x == TOTAL_LABEL, TOTAL_LABEL, gsub("_", " ", sub("_hh$", "", x)))
  unname(ifelse(is.na(known), fallback, known))
}

# Een rij kan naar meer dan een variabele tegelijk uitgesplitst zijn
# (utils/splits.R); dan draagt split_var ze allemaal en krijgt elk onderdeel
# zijn eigen label.
pretty_split <- function(x) split_pretty(x, function(deel, i) pretty_split_1(deel))

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
  namen <- if (!is.null(split_var) && length(split_var) == 1L) split_parts(split_var) else character(0)
  if (length(namen) <= 1L || length(x) == 0L) return(pretty_level_1(x, split_var, population))
  # Samengesteld: elk onderdeel langs zijn eigen variabele. Per onderdeel de
  # hele kolom ineens, niet waarde voor waarde -- pretty_level_1() kijkt naar de
  # verzameling ("alleen 0 en 1" leest als nee/ja), en die context zou per
  # losse waarde wegvallen.
  delen <- strsplit(as.character(x), SPLIT_SEP, fixed = TRUE)
  m <- do.call(rbind, lapply(delen, function(d) { length(d) <- length(namen); d }))
  kol <- lapply(seq_along(namen), function(i) pretty_level_1(m[, i], namen[[i]], population))
  do.call(paste, c(kol, list(sep = " \u00b7 ")))
}

pretty_level_1 <- function(x, split_var = NULL, population = NULL) {
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

named <- function(values, labeller) setNames(values, labeller(values))

# Keeps the user's current pick when it is still a valid choice, so changing an
# unrelated selector does not silently reset the rest of the form.
update_preserving <- function(session, id, choices, current) {
  # `current` kan meerdere waarden hebben (de kaartselectors staan op
  # multiple = TRUE): alles wat nog bestaat blijft staan, en als er niets van
  # overblijft valt hij terug op de eerste keuze in plaats van op leeg.
  blijft <- current[!is.na(current) & current %in% choices]
  sel <- if (length(blijft)) blijft
         else if (length(choices) == 0L) character(0)
         else choices[1]
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
    .kaart-let-op { background: #FDF3E7; border-left: 4px solid #E8871A; border-radius: 3px;
        padding: 8px 12px; margin-bottom: 10px; font-size: 12px; color: #6b4415;
        line-height: 1.45; }
    .kaart-let-op code { background: #f6e6d2; color: #6b4415; font-size: 11px; }
  ", ahti_branding$colors$grijs_blauw,
     ahti_branding$colors$helder_blauw,
     ahti_branding$colors$midden_grijs,
     ahti_branding$colors$licht_grijs,
     VENN_NONE_FILL)))),

  fluidRow(
    column(9,
      h2("Dynamo Amsterdam", class = "app-title"),
      div("Risicostapeling bij huishoudens met kinderen en ouderen, 2018-2024. ",
          "Bron: CBS microdata via de Remote Access-omgeving.", class = "app-sub")),
    column(3, div(style = "text-align: right; padding-top: 22px;", changelog_knop()))
  ),

  tabsetPanel(
    id = "hoofdtab",
    tabPanel(
      "Iteratie 1",
      br(),

      uiOutput("data_waarschuwing"),

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
                selectInput("k_val", "Waarde van de indicator", choices = NULL,
                            multiple = TRUE),
                selectInput("k_metric", "Metric", choices = NULL)
              ),
              control_card(
                tags$label(class = "control-label", "Splits uit naar"),
                div(class = "note", style = "margin: 2px 0 10px;",
                    "Elke uitsplitsing staat op \u201calle\u201d: dan telt hij niet mee",
                    " in de selectie. Kies een niveau om er wel op te filteren.",
                    " Meerdere niveaus van dezelfde uitsplitsing worden bij elkaar",
                    " opgeteld; twee uitsplitsingen tegelijk geeft de gekruiste",
                    " groep, zolang de levering die kruising publiceert."),
                uiOutput("k_split_ui"),
                uiOutput("k_split_note")
              ),
              control_card(
                radioButtons("k_weergave", "Weergave",
                             c("Absoluut" = "abs",
                               "Aandeel van regiototaal (%)" = "rel_regio",
                               "Aandeel binnen groep (%)" = "rel_groep",
                               "Aandeel binnen indicatorwaarde (%)" = "rel_indicator"),
                             selected = "rel_regio"),
                uiOutput("k_gem_note"),
                div(class = "note", style = "margin: -6px 0 10px;",
                    tags$b("Van regiototaal:"),
                    " ten opzichte van alle huishoudens/ouderen in die buurt, wijk,",
                    " dat gebied of dat stadsdeel \u2014 \"x% van alle gezinnen hier\". ",
                    tags$b("Binnen groep:"),
                    " ten opzichte van de gekozen groep zelf \u2014 \"van de gezinnen met",
                    " dit ondersteuningsbeeld heeft x% deze risicoscore\". ",
                    tags$b("Binnen indicatorwaarde:"),
                    " precies andersom \u2014 ten opzichte van iedereen met de gekozen",
                    " waarde van de indicator, zonder uitsplitsing: \"van de gezinnen",
                    " met 3+ risicofactoren hier gebruikt x% alle drie de",
                    " ondersteuningsvormen\"."),
                checkboxInput("k_schaal_auto", "Kleurschaal volgt de data", TRUE),
                conditionalPanel(
                  "!input.k_schaal_auto",
                  fluidRow(
                    column(6, numericInput("k_min", "Van", value = NA, width = "100%")),
                    column(6, numericInput("k_max", "Tot", value = NA, width = "100%"))),
                  div(class = "note", style = "margin-top: -4px;",
                      "Een vast bereik maakt twee kaarten naast elkaar vergelijkbaar.",
                      " Regio's erbuiten krijgen de rand van de schaal, niet grijs.")
                )
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
              uiOutput("k_dekking_note"),
              uiOutput("k_som_waarschuwing"),
              uiOutput("k_waarschuwing"),
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
                selectizeInput("r_regio", "Regio", choices = NULL),
                uiOutput("r_dekking_note")
              ),
              control_card(
                selectInput("r_var", "Indicator", choices = NULL),
                uiOutput("r_var_note"),
                selectInput("r_val", "Waarde van de indicator", choices = NULL),
                selectInput("r_metric", "Metric", choices = NULL)
              ),
              control_card(
                tags$label(class = "control-label", "Splits de lijn uit naar"),
                div(class = "note", style = "margin: 2px 0 10px;",
                    "\u201cAlle\u201d laat de uitsplitsing weg. \u201cElk niveau apart\u201d",
                    " geeft een lijn per niveau; kies je in plaats daarvan \u00e9\u00e9n",
                    " niveau, dan gaat de hele figuur over die groep. Twee",
                    " uitsplitsingen op \u201celk niveau apart\u201d geeft een lijn per",
                    " kruising."),
                uiOutput("r_split_ui"),
                uiOutput("r_split_note")
              ),
              control_card(
                radioButtons("r_weergave", "Weergave",
                             c("Absoluut" = "abs", "Aandeel (%)" = "rel"),
                             selected = "rel"),
                uiOutput("r_gem_note")
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

  # Alleen de indicatorlijst hangt aan de populatie alleen. "Waarde van de
  # indicator" (k_val/r_val), "Metric" (k_metric/r_metric) en "Splits uit naar"
  # (k_split/r_split) hangen aan de gekozen *indicator* en worden hieronder
  # bijgewerkt: een lijst voor de hele populatie zou combinaties aanbieden die
  # nergens rijen hebben. De losse risicofactoren zijn binair (0/1) maar de
  # stapeling heeft klassen, de afgeleide ondersteuningsindicatoren dragen
  # alleen de splitsingen die de afleiding kon maken, en -- sinds levering
  # output_1b -- heeft niet elke indicator elke metric: `average_score` bestaat
  # alleen bij R_MPG_totaal/R_OUD_totaal, en die dragen juist alleen dat
  # gemiddelde. Zolang de metriclijst hier stond, opende het dashboard op de
  # alfabetisch eerste indicator met de alfabetisch eerste metric -- en dat is
  # sinds output_1b een lege kaart.
  observeEvent(input$populatie, {
    v <- pop_vocab()

    vars <- sort(unique(v$variable_name))

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
    # population's indicator. k_val/r_val, k_metric/r_metric and k_split/r_split
    # are frozen too even though they are not updated here: they depend on
    # k_var/r_var (see update_indicator_keuzes() below), which is itself
    # mid-change, so any stale read of them this same flush must also be halted
    # rather than paired with the wrong population's indicator. De
    # splitsselectors staan er niet bij: die bestaan per variabele en worden
    # door renderUI opnieuw opgebouwd, en split_selectie() negeert een waarde
    # die bij deze populatie niet bestaat (zie daar).
    for (i in c(ids, "k_val", "r_val")) freezeReactiveValue(input, i)

    for (p in c("k", "r")) {
      update_preserving(session, paste0(p, "_var"), named(vars, pretty_var),
                        current[[paste0(p, "_var")]])
    }
  }, ignoreInit = FALSE)

  #' Werkt "Waarde van de indicator" en "Metric" bij voor een van de twee
  #' tabbladen. Allebei hangen ze aan de gekozen indicator, dus ze horen in
  #' dezelfde flush bijgewerkt te worden -- anders staat er een moment lang een
  #' waarde van de ene indicator naast een metric van de andere.
  update_indicator_keuzes <- function(p) {
    var_id <- paste0(p, "_var"); val_id <- paste0(p, "_val"); met_id <- paste0(p, "_metric")
    var_name <- input[[var_id]]
    req(var_name)
    # De ene flush waarin de indicator nog van de vorige populatie kan zijn:
    # overslaan in plaats van keuzes bouwen tegen de verkeerde populatie.
    req(var_name %in% pop_vocab()$variable_name)
    rijen <- pop_vocab()[variable_name == var_name]
    vals <- sort(unique(rijen$variable_value))
    mets <- sort(unique(rijen$metric_name))
    # Lezen voor het bevriezen: een bevroren input geeft bij het lezen een
    # stille fout, en dan stopt deze observer voor hij iets verstuurd heeft.
    cur_val <- isolate(input[[val_id]])
    cur_met <- isolate(input[[met_id]])
    freezeReactiveValue(input, val_id)
    freezeReactiveValue(input, met_id)
    update_preserving(session, val_id,
                      setNames(vals, pretty_value(vals, var_name, input$populatie)), cur_val)
    update_preserving(session, met_id, named(mets, pretty_metric), cur_met)
  }

  observeEvent(list(input$populatie, input$k_var), update_indicator_keuzes("k"))
  observeEvent(list(input$populatie, input$r_var), update_indicator_keuzes("r"))

  # "Splits uit naar": welke splitsvariabelen rijen hebben bij de op dit moment
  # gekozen indicator, en per variabele welke niveaus. De risicoscores dragen ze
  # allemaal; de afgeleide ondersteuningsindicatoren dragen alleen wat de
  # afleiding kon maken, want de ondersteuning zit daar al in hun
  # variable_value. Een keuzelijst voor de hele populatie zou combinaties
  # aanbieden die nergens rijen hebben, en dat leest als een bug in plaats van
  # als een onmogelijke combinatie.
  #
  # Elke variabele krijgt haar eigen keuzelijst, met "alle" bovenaan. Dat is
  # wat de levering ook doet -- een rij die niet naar deze variabele is
  # uitgesplitst is gewoon een rij -- terwijl het in de oude gezamenlijke
  # meerkeuzelijst alleen te bereiken was door de variabele weg te klikken.
  splits_keuzes <- function(var_name) {
    v <- pop_vocab()[variable_name == var_name]
    paren <- unique(v[, .(split_var, split_level)])
    vars <- split_vars_available(paren$split_var)
    setNames(lapply(vars, function(x)
      split_levels_available(x, paren$split_var, paren$split_level)), vars)
  }

  # De naam van de variabele zit in de input-id, zodat de keuze bewaard blijft
  # als renderUI de lijsten opnieuw opbouwt. Niet-alfanumerieke tekens eruit:
  # een input-id moet een geldige naam zijn. De variabelenamen van de levering
  # zijn dat al, dit is de vangnetregel voor een volgende levering.
  split_input_id <- function(p, var) paste0(p, "_split_", gsub("[^A-Za-z0-9_]", "_", var))

  # Dynamische inputs krijgen hun observer maar een keer. renderUI bouwt de
  # lijst opnieuw op bij elke indicatorwissel, en een observeEvent() per render
  # zou stapelen -- dan draait dezelfde correctie net zo vaak als er ooit
  # gerenderd is.
  split_geregistreerd <- new.env(parent = emptyenv())
  registreer_alle_observer <- function(id) {
    if (exists(id, envir = split_geregistreerd, inherits = FALSE)) return(invisible(FALSE))
    assign(id, TRUE, envir = split_geregistreerd)
    observeEvent(input[[id]], {
      sel <- input[[id]]
      if (length(sel) <= 1L || !SPLIT_ALLE %in% sel) return()
      # "Alle" en een los niveau sluiten elkaar uit. Wat er het laatst bij
      # kwam wint: klik je een niveau aan, dan valt "alle" weg; klik je "alle"
      # aan, dan vallen de niveaus weg. selectize levert de waarden in
      # aanklikvolgorde, dus het laatste element is de nieuwste keuze.
      nieuw <- if (identical(sel[[length(sel)]], SPLIT_ALLE)) SPLIT_ALLE
               else setdiff(sel, SPLIT_ALLE)
      updateSelectInput(session, id, selected = nieuw)
    }, ignoreInit = TRUE)
    invisible(TRUE)
  }

  #' Een keuzelijst per splitsvariabele voor een van de twee tabbladen.
  #'
  #' @param p "k" of "r".
  #' @param elk Biedt "elk niveau apart" aan (Per regio: dat tekent een lijn per
  #'   niveau). Op de kaart bestaat die keuze niet -- een choropleth toont een
  #'   getal per regio, dus daar worden meerdere niveaus opgeteld.
  split_ui <- function(p, elk) {
    var_name <- input[[paste0(p, "_var")]]
    req(var_name)
    req(var_name %in% pop_vocab()$variable_name)
    keuzes <- splits_keuzes(var_name)
    if (length(keuzes) == 0L) {
      return(div(class = "note", "Deze indicator heeft geen uitsplitsingen."))
    }
    lapply(names(keuzes), function(v) {
      id <- split_input_id(p, v)
      lv <- keuzes[[v]]
      ch <- c(setNames(SPLIT_ALLE, "(alle)"),
              if (elk) setNames(SPLIT_ELK, "(elk niveau apart)"),
              setNames(lv, pretty_level(lv, v, input$populatie)))
      # De staande keuze overleeft een herbouw, zolang hij hier nog bestaat --
      # een andere indicator of populatie kan dezelfde variabele met andere
      # niveaus dragen.
      cur <- isolate(input[[id]])
      sel <- cur[!is.na(cur) & cur %in% ch]
      if (!length(sel)) sel <- SPLIT_ALLE
      # Alleen de meerkeuzelijst kan "alle" naast een niveau krijgen.
      if (!elk) registreer_alle_observer(id)
      selectInput(id, pretty_split_1(v), choices = ch, selected = sel,
                  multiple = !elk)
    })
  }
  output$k_split_ui <- renderUI(split_ui("k", elk = FALSE))
  output$r_split_ui <- renderUI(split_ui("r", elk = TRUE))

  #' Wat er op dit moment gekozen staat, uitgesplitst naar wat het betekent:
  #'
  #'   vars       de variabelen die meedoen (samen de sleutel)
  #'   keuze      per variabele de gekozen niveaus -- alleen voor de variabelen
  #'              die op een vast niveau staan; een variabele die hier ontbreekt
  #'              telt in split_levels_matching() als "elk niveau"
  #'   reeks_vars de variabelen op "elk niveau apart": die bepalen de reeksen
  #'   key        de sleutel zoals de levering hem wegschrijft
  #'
  #' Een waarde die bij deze populatie/indicator niet bestaat wordt genegeerd en
  #' leest dus als "alle". Dat is de ene flush waarin de keuzelijsten nog van de
  #' vorige indicator zijn: liever de uitsplitsing even weglaten dan de
  #' verkeerde rijen selecteren.
  split_selectie <- function(p) {
    var_name <- input[[paste0(p, "_var")]]
    req(var_name)
    req(var_name %in% pop_vocab()$variable_name)
    keuzes <- splits_keuzes(var_name)
    vars <- character(0)
    keuze <- list()
    for (v in names(keuzes)) {
      sel <- input[[split_input_id(p, v)]]
      sel <- sel[!is.na(sel) & sel %in% c(SPLIT_ALLE, SPLIT_ELK, keuzes[[v]])]
      if (!length(sel) || SPLIT_ALLE %in% sel) next
      vars <- c(vars, v)
      if (!SPLIT_ELK %in% sel) keuze[[v]] <- sel
    }
    list(vars = vars, keuze = keuze, reeks_vars = setdiff(vars, names(keuze)),
         key = split_key(vars))
  }

  k_split_sel <- reactive(split_selectie("k"))
  r_split_sel <- reactive(split_selectie("r"))

  # De sleutel van de gekozen verzameling: "(totaal)" als alles op "alle" staat,
  # en anders de namen alfabetisch aan elkaar -- precies zoals de prep-stap ze
  # in split_var heeft weggeschreven.
  k_split_key <- reactive(k_split_sel()$key)
  r_split_key <- reactive(r_split_sel()$key)

  # Bestaat deze kruising in de levering? Niet elke combinatie wordt
  # gepubliceerd, en een lege grafiek moet als "niet geleverd" leesbaar zijn.
  k_split_bestaat <- reactive(split_key_bestaat(k_split_key(), pop_vocab()$split_var))
  r_split_bestaat <- reactive(split_key_bestaat(r_split_key(), pop_vocab()$split_var))

  # Welke gepubliceerde split_level-waarden bij de keuze horen. Bewust de
  # geleverde niveaus filteren en niet het product van de losse keuzes: de
  # levering publiceert lang niet elke kruising (zie split_levels_matching()).
  # Een lege selectie mag geen lege vector de filter in: `%in% character(0)`
  # is bij arrow niet gegarandeerd dezelfde "niets" als bij een data.frame.
  # Een waarde die in geen enkele levering voorkomt is dat wel.
  niets_als_leeg <- function(x) if (length(x)) x else SPLIT_GEEN

  split_niveaus <- function(sel) {
    if (identical(sel$key, TOTAL_LABEL)) return(TOTAL_LABEL)
    split_levels_matching(sel$key, pop_vocab()[split_var == sel$key]$split_level,
                          sel$keuze)
  }
  k_split_levels <- reactive(split_niveaus(k_split_sel()))
  r_split_levels <- reactive(split_niveaus(r_split_sel()))

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
                 "Afgeleid uit de ondersteuningscombinaties. Voor het aantal",
                 " huishoudens/ouderen komt dat sinds levering output_1b uit de",
                 " gepubliceerde groepsgroottes en is het dus exact. Telt de metric",
                 " iets anders (de kindermetrics tellen kinderen), dan moet het nog",
                 " uit de risicocategorie\u00ebn worden opgeteld en lukt dat lang niet",
                 " overal; wat dan overblijft staat als",
                 " \u201cNiet toe te wijzen\u201d in de waardelijst, zodat de noemer",
                 " de hele populatie blijft.")
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

  # Toelichting onder "Splits uit naar", op beide tabbladen: de O_MPG1/2/3-legenda bij de
  # combinatiesplitsing, wat de noemer betekent bij de afgeleide splitsingen, en
  # -- sinds er meerdere tegelijk kunnen -- de melding dat een kruising niet
  # geleverd is.
  split_note <- function(gekozen, bestaat) {
    delen <- gekozen %||% character(0)
    if (length(delen) == 0L) return(NULL)
    tagList(
      if (!isTRUE(bestaat))
        tags$div(class = "kaart-let-op",
                 tags$b("Deze kruising zit niet in de levering."),
                 " De CBS-output publiceert lang niet elke combinatie van",
                 " uitsplitsingen. Kies er een weg, of een andere combinatie."),
      if (any(delen %in% COMBO_SPLIT_VAR)) {
        gl <- COMBO_GROUP_UITLEG[[input$populatie]]
        tags$div(class = "note", style = "margin-top: -4px;",
                 HTML(paste(sprintf("<b>%s</b> %s", names(gl), gl), collapse = "<br/>")))
      },
      if (any(delen %in% ONDERSTEUNING_SPLITS))
        tags$div(class = "note", style = "margin-top: -4px;",
                 "Afgeleid uit de ondersteuningscombinaties. Bij",
                 " \u201cAandeel (%)\u201d is de noemer de gekozen groep zelf,",
                 " dus dat leest als: van de groep met dit ondersteuningsbeeld",
                 " heeft x% deze risicoscore. Kies de indicator",
                 " \u201cOndersteuningssignaal (wel/geen)\u201d voor het",
                 " omgekeerde: het aandeel van de hele populatie.")
    )
  }
  output$k_split_note <- renderUI({
    req(input$populatie)
    split_note(k_split_sel()$vars, k_split_bestaat())
  })
  output$r_split_note <- renderUI({
    req(input$populatie)
    split_note(r_split_sel()$vars, r_split_bestaat())
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
  # De weergave zoals hij echt gebruikt wordt. `average_score` is een
  # gemiddelde: daar bestaat geen aandeel van, want er is geen noemer om tegen
  # af te zetten (utils/metrics.R). De keuzeknop blijft staan -- hij geldt weer
  # zodra er een tellende metric gekozen wordt -- maar de app rekent en schrijft
  # dan "gemiddelde", en zegt dat onder de knop.
  k_weergave <- reactive({
    if (isTRUE(metric_is_gemiddelde(input$k_metric))) "gem" else input$k_weergave
  })
  r_weergave <- reactive({
    if (isTRUE(metric_is_gemiddelde(input$r_metric))) "gem" else input$r_weergave
  })

  gemiddelde_note <- function(metric) {
    if (!isTRUE(metric_is_gemiddelde(metric))) return(NULL)
    tags$div(class = "note", style = "margin: -6px 0 10px;",
             tags$b("Dit is een gemiddelde."),
             " Een aandeel van een gemiddelde bestaat niet, dus de keuze",
             " hierboven geldt hier niet: er staat het gemiddelde zelf. Om",
             " dezelfde reden kan een gemiddelde niet over meerdere waarden of",
             " niveaus opgeteld worden \u2014 kies er \u00e9\u00e9n van elk.")
  }
  output$k_gem_note <- renderUI(gemiddelde_note(input$k_metric))
  output$r_gem_note <- renderUI(gemiddelde_note(input$r_metric))

  add_display <- function(d, weergave) {
    if (nrow(d) == 0) {
      d[, `:=`(waarde = numeric(), noemer = numeric())]
      return(d[])
    }
    # Welke noemer bij welke weergave hoort staat in map_noemer() -- daar staat
    # ook waarom het regiototaal niet n_totaal is. `regio_totaal` zit alleen op
    # de kaartselectie; de andere tabbladen kennen alleen "binnen de groep".
    nmr <- map_noemer(weergave, d$denominator,
                      if ("regio_totaal" %in% names(d)) d$regio_totaal else NULL,
                      if ("indicator_totaal" %in% names(d)) d$indicator_totaal else NULL)
    # De noemer waar het getoonde getal echt door gedeeld is, als kolom naast
    # de waarde. De tooltip van de kaart zei "n = x van y" met y = n_totaal --
    # het aantal huishoudens/ouderen in de hele regio -- ook bij "aandeel
    # binnen groep", waar er door de groepsomvang gedeeld wordt. Die twee
    # spraken elkaar dan tegen: 40 van 2.020 naast 5,3% op de kaart. Nu draagt
    # elke rij de noemer die er werkelijk gebruikt is, en lezen tooltip, export
    # en kaart hetzelfde getal.
    d[, noemer := if (is.null(nmr)) NA_real_ else as.numeric(nmr)]
    d[, waarde := if (!map_is_aandeel(weergave)) {
        as.numeric(metric_value)
      } else if (is.null(nmr)) {
        # Een aandeel zonder noemer is geen aandeel. Liever leeg -- dat leest
        # als "onvoldoende waarnemingen" -- dan aantallen die met een
        # procentteken worden afgedrukt.
        NA_real_
      } else {
        # Afgekapt op 100%. Sinds output_1b komen teller en noemer uit twee
        # afzonderlijk op tientallen afgeronde getallen -- de celwaarde uit de
        # levering (of uit referentierij - none), de noemer uit de gepubliceerde
        # groepsomvang. Vlak boven de onderdrukkingsgrens kan de teller daardoor
        # een tiental boven de noemer uitkomen: 20 van een groep van 10 leest dan
        # als 200%, terwijl de echte waarden bijvoorbeeld 15 van 14 zijn. Het
        # gaat om 0,08% van de afgeleide rijen, altijd bij zulke kleine
        # aantallen. Een deel van een groep kan nooit meer dan de hele groep
        # zijn, dus 100% is hier het eerlijkste getal; het absolute aantal blijft
        # ongewijzigd zichtbaar onder "Aantal".
        fifelse(!is.na(nmr) & nmr > 0,
                pmin(metric_value / nmr * 100, 100), NA_real_)
      }]
    # Een gemiddelde staat los van de gekozen weergave: het getal zelf is de
    # waarde. Dit vangt ook de slice waarin meerdere metrics door elkaar staan.
    gem <- metric_is_gemiddelde(d$metric_name)
    if (any(gem)) d[gem, `:=`(waarde = as.numeric(metric_value), noemer = NA_real_)]
    d[]
  }

  # Wat er achter een getal staat, en tegelijk het onderschrift van de legenda:
  # bij een aandeel maakt het verschil of het tegen de groep of tegen de hele
  # regio is afgezet, en dat hoort zichtbaar te zijn.
  eenheid <- function(weergave) {
    switch(weergave,
           rel_regio     = "% van regiototaal",
           rel_groep     = "% binnen groep",
           rel_indicator = "% binnen indicatorwaarde",
           rel       = "%",
           gem       = "gemiddelde",
           "aantal")
  }

  # ---------------------------------------------------------------- Kaart -----

  # De ruwe rijen achter de kaart: een per regio x gekozen splitsniveau x
  # gekozen indicatorwaarde. Beide keuzelijsten staan op multiple, zodat er
  # bijvoorbeeld "O1, O2 en O1+O2 samen" te bekijken is.
  kaart_rijen <- reactive({
    req(input$populatie, input$k_jaar, input$k_niveau,
        input$k_var, input$k_val, input$k_metric)

    sleutel <- k_split_key()
    # Levert deze kruising geen enkel passend niveau op, dan blijft de selectie
    # leeg en tekent de kaart "geen data" -- met de reden eronder in
    # k_split_note(). Niet req(): dan zou de kaart de vorige selectie blijven
    # tonen alsof er niets aan de hand is.
    lvl <- niets_als_leeg(k_split_levels())

    ds |>
      filter(population   == !!input$populatie,
             region_level == !!input$k_niveau,
             year          == !!as.integer(input$k_jaar),
             variable_name == !!input$k_var,
             variable_value %in% !!input$k_val,
             metric_name   == !!input$k_metric,
             split_var     == !!sleutel,
             split_level %in% !!lvl) |>
      collect() |>
      as.data.table()
  })

  # Hoeveel rijen een regio moet hebben om compleet te zijn. Komt een cel niet
  # voor, dan zou de optelling stilzwijgend te laag uitvallen, en valt de regio
  # af -- zie map_aggregate().
  kaart_n_cellen <- reactive({
    length(k_split_levels()) * length(input$k_val %||% character(0))
  })

  # Het totaal van de regio voor deze metric: de noemer van de totaalrijen, dus
  # de som over alle categorieen van de indicator. Bewust niet n_totaal -- die
  # telt huishoudens, terwijl de teller bij de n_kinderen_*-metrics kinderen
  # telt, en dan is de uitkomst geen percentage (PLAN.md 6). Per regio een
  # waarde; de noemer is binnen een slice constant over de categorieen.
  kaart_regio_totaal <- reactive({
    req(input$populatie, input$k_jaar, input$k_niveau, input$k_var, input$k_metric)
    ds |>
      filter(population   == !!input$populatie,
             region_level == !!input$k_niveau,
             year          == !!as.integer(input$k_jaar),
             variable_name == !!input$k_var,
             metric_name   == !!input$k_metric,
             split_var     == !!TOTAL_LABEL) |>
      select(region_code, denominator) |>
      distinct() |>
      collect() |>
      as.data.table()
  })

  # Dezelfde indicatorwaarde(n), maar zonder uitsplitsing: de totaalrij. Dat is
  # de noemer van "Aandeel binnen indicatorwaarde" -- van de gezinnen met 3+
  # risicofactoren in deze wijk gebruikt x% alle drie de ondersteuningsvormen.
  #
  # Anders dan bij het regiototaal is dit `metric_value` en niet `denominator`:
  # we willen niet de hele populatie maar juist alleen de gekozen
  # indicatorwaarden, en daarover wordt opgeteld net als in de teller.
  #
  # `gevonden` telt hoeveel van de gevraagde waarden er op de totaalrij stonden.
  # Zijn dat er minder, dan is de noemer te klein en zou elk percentage te hoog
  # uitvallen; die regio krijgt hieronder NA in plaats van een verkeerd getal.
  kaart_indicator_totaal <- reactive({
    req(input$populatie, input$k_jaar, input$k_niveau, input$k_var,
        input$k_metric, input$k_val)
    ds |>
      filter(population    == !!input$populatie,
             region_level  == !!input$k_niveau,
             year          == !!as.integer(input$k_jaar),
             variable_name == !!input$k_var,
             metric_name   == !!input$k_metric,
             variable_value %in% !!input$k_val,
             split_var     == !!TOTAL_LABEL) |>
      select(region_code, variable_value, metric_value) |>
      distinct() |>
      collect() |>
      as.data.table() |>
      (\(d) d[, .(indicator_totaal = sum(metric_value), gevonden = .N), by = region_code])()
  })

  # Het regiototaal aanhaken. Ook de ruwe rijen krijgen hem, zodat het tweede
  # tabblad van de export hetzelfde aandeel toont als de kaart en niet stilletjes
  # op aantallen terugvalt.
  met_regio_totaal <- function(d) {
    if (nrow(d) == 0) {
      d[, `:=`(regio_totaal = numeric(), indicator_totaal = numeric())]
      return(d[])
    }
    d <- merge(d, kaart_regio_totaal()[, .(region_code, regio_totaal = denominator)],
               by = "region_code", all.x = TRUE)
    it <- kaart_indicator_totaal()
    gevraagd <- length(input$k_val %||% character(0))
    # Onvolledige noemer = geen noemer. Een aandeel tegen een te kleine noemer
    # is erger dan geen aandeel: het valt te hoog uit en niets verraadt dat.
    it <- it[, .(region_code,
                 indicator_totaal = fifelse(gevonden >= gevraagd, indicator_totaal, NA_real_))]
    merge(d, it, by = "region_code", all.x = TRUE)
  }

  kaart_data <- reactive(add_display(
    met_regio_totaal(map_aggregate(kaart_rijen(), kaart_n_cellen(),
                                   optelbaar = !isTRUE(metric_is_gemiddelde(input$k_metric)))),
    k_weergave()))

  # Het bereik van de kleurschaal: standaard de uiterste waarden van de
  # selectie, of een handmatig bereik als de gebruiker dat aanzet.
  kaart_domein <- reactive({
    handmatig <- if (isTRUE(input$k_schaal_auto)) NULL else c(input$k_min, input$k_max)
    map_domein(kaart_data()$waarde, handmatig)
  })

  # Zodra de gebruiker de schaal overneemt, staan de velden vast op wat er op
  # dat moment te zien was -- dan hoeft niemand twee getallen te verzinnen.
  observeEvent(input$k_schaal_auto, {
    if (isTRUE(input$k_schaal_auto)) return()
    d <- map_domein(kaart_data()$waarde)
    req(d)
    updateNumericInput(session, "k_min", value = signif(d[1], 3))
    updateNumericInput(session, "k_max", value = signif(d[2], 3))
  }, ignoreInit = TRUE)

  # Een selectie van meerdere waarden of niveaus wordt opgeteld; de titel zegt
  # welke, tot een stuk of drie. Daarboven wordt het een opsomming die de titel
  # onleesbaar maakt, en volstaat het aantal.
  som_label <- function(x) {
    if (length(x) == 0) return("")
    if (length(x) <= 3) paste(x, collapse = ", ") else sprintf("%d samengevoegd", length(x))
  }

  kaart_titel <- reactive({
    req(input$k_var, input$k_metric, input$k_jaar, input$k_val)
    sleutel <- k_split_key()
    sp <- if (identical(sleutel, TOTAL_LABEL)) "" else
      sprintf(" | %s: %s", pretty_split(sleutel),
              som_label(pretty_level(k_split_levels(), sleutel, input$populatie)))
    sprintf("%s = %s | %s (%s) | %s %s%s",
            pretty_var(input$k_var),
            som_label(pretty_value(input$k_val, input$k_var, input$populatie)),
            pretty_metric(input$k_metric), eenheid(k_weergave()),
            input$k_jaar, input$k_niveau, sp)
  })

  output$k_titel <- renderText(kaart_titel())

  # Bij een opgetelde selectie telt een regio waar een van de gekozen groepen
  # onderdrukt is alleen op wat gepubliceerd is. Dat cijfer is dan een
  # ondergrens, en dat hoort er hardop bij te staan -- niet alleen in de
  # tooltip, want je ziet de kaart eerder dan dat je erover hovert.
  # De dataset is nog van voor levering output_1b: de exacte groepsomvang
  # ontbreekt, dus de noemers komen nog uit de oude terugrekening. Het dashboard
  # werkt, maar wie een aandeel afleest hoort te weten dat het de oude berekening
  # is -- die telde onderdrukte categorieen niet mee en viel dus te hoog uit.
  output$data_waarschuwing <- renderUI({
    if (HEEFT_N_SPLIT) return(NULL)
    div(class = "kaart-let-op",
        tags$b("Deze dataset is nog van voor levering output_1b."),
        " De exacte groepsomvang (", tags$code("n_totaal_region_splitvar"),
        ") zit er nog niet in, dus elke noemer is teruggerekend uit de",
        " gepubliceerde categorie\u00ebn en kan te klein zijn waar een categorie",
        " onderdrukt is. Draai ", tags$code("data-prep/01_build_app_data.R"),
        " op de nieuwe levering en commit de parquet.")
  })

  # Dekt dit regioniveau maar een deel van de stad, dan hoort dat boven de kaart
  # te staan. Een niet-geleverde regio en een onderdrukte regio zien er allebei
  # uit als een grijs vlak, en dat verschil is hier groot: "hier wonen te weinig
  # mensen om te publiceren" tegen "dit gebied zit niet in deze levering".
  dekking_note <- function(niveau) {
    if (is.null(niveau) || !nzchar(niveau)) return(NULL)
    rij <- DEKKING_STADSDELEN[region_level == niveau]
    if (nrow(rij) == 0L) return(NULL)
    heeft <- setdiff(rij$stadsdelen[[1]], NA_character_)
    # Gemeente is de hele stad in een vlak en valt niet in stadsdelen uiteen;
    # daar valt over dekking niets te melden. Zonder deze regel zou "heeft" leeg
    # zijn en de melding beweren dat er niets geleverd is.
    if (length(heeft) == 0L) return(NULL)
    mist  <- setdiff(STADSDELEN, heeft)
    if (length(mist) == 0L) return(NULL)
    div(class = "kaart-let-op",
        tags$b(sprintf("Deze levering bevat op %sniveau alleen %s.",
                       niveau, paste(heeft, collapse = ", "))),
        sprintf(" De overige stadsdelen (%s) zijn hier niet geleverd en blijven leeg.",
                paste(mist, collapse = ", ")),
        " Dat is iets anders dan onvoldoende waarnemingen — er is daar niets",
        " onderdrukt, er is niets aangeleverd. Kies gebied, stadsdeel of Heel",
        " Amsterdam voor een beeld van de hele stad.")
  }
  # Meerdere niveaus van dezelfde uitsplitsing mogen (dat is hoe "O1, O2 en
  # O1+O2 samen" te bekijken is), maar dan staat er een optelsom op de kaart en
  # niet een groep. Met een keuzelijst per variabele is dat makkelijker per
  # ongeluk te doen dan met de oude gezamenlijke niveaulijst, dus het hoort er
  # hardop bij -- boven de kaart, want de titel leest niemand als controle.
  output$k_som_waarschuwing <- renderUI({
    req(input$populatie, input$k_var)
    lvl <- k_split_levels()
    if (identical(k_split_key(), TOTAL_LABEL) || length(lvl) <= 1L) return(NULL)
    div(class = "kaart-let-op",
        tags$b(sprintf("Let op: %d groepen worden bij elkaar opgeteld.", length(lvl))),
        sprintf(" De kaart toont de som van %s, niet elke groep apart.",
                som_label(pretty_level(lvl, k_split_key(), input$populatie))),
        " Kies \u00e9\u00e9n niveau per uitsplitsing voor een enkele groep.")
  })

  output$k_dekking_note <- renderUI(dekking_note(input$k_niveau))
  output$r_dekking_note <- renderUI(dekking_note(input$r_niveau))

  output$k_waarschuwing <- renderUI({
    d <- kaart_data()
    if (nrow(d) == 0) return(NULL)
    # Een gemiddelde laat zich niet optellen; dan is er bij meer dan een cel per
    # regio geen getal te tonen en hoort dat er hardop bij te staan.
    if (isTRUE(metric_is_gemiddelde(input$k_metric)) && any(d$n_gevonden > 1)) {
      return(div(class = "kaart-let-op",
                 tags$b("Een gemiddelde kan niet opgeteld worden."),
                 " Er zijn meerdere waarden of niveaus geselecteerd, en het",
                 " gemiddelde daarvan is niet uit deze cijfers te bepalen: daar",
                 " zouden de aantallen per cel voor nodig zijn, en die staan niet",
                 " in dezelfde slice. Kies \u00e9\u00e9n waarde en \u00e9\u00e9n",
                 " niveau."))
    }
    if (!"compleet" %in% names(d)) return(NULL)
    n <- sum(!d$compleet)
    if (n == 0) return(NULL)
    # Bij een aantal is een onvolledige optelling een ondergrens: er mist alleen
    # teller. Bij een aandeel klopt dat woord niet -- daar valt met de
    # onderdrukte cel ook de hele noemer van die groep weg, en die is veel
    # groter dan de onderdrukte cel zelf. Het percentage valt dan juist te hoog
    # uit (20 van 180 in plaats van 20 van 460), en "ondergrens" zou de lezer
    # precies de verkeerde kant op sturen.
    aandeel <- map_is_aandeel(k_weergave())
    div(class = "kaart-let-op",
        tags$b(sprintf("Let op: in %d van de %d regio's is een gekozen groep onderdrukt.",
                       n, nrow(d))),
        if (aandeel)
          paste(" Daar telt niet alleen de teller maar ook de noemer alleen op wat",
                " gepubliceerd is (minder dan tien blijft weg), en omdat er met een",
                " onderdrukte cel een hele groep uit de noemer valt, kan het",
                " percentage daar te hoog uitvallen.")
        else
          paste(" Daar telt het cijfer alleen op wat wel gepubliceerd is (minder dan",
                " tien blijft weg), dus het is een ondergrens."),
        " Die regio's hebben een gestippelde rand; hover erover voor de bevestiging,",
        " daar staat ook hoeveel van de gekozen onderdelen er gepubliceerd zijn.",
        " In de xlsx staat het als kolom ", tags$code("alle_groepen_aanwezig"), ".")
  })

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
    # "Toon" snijdt op stadsdeel; het gemeentevlak ligt in geen enkel stadsdeel,
    # dus daar zou dat filter de kaart leegmaken in plaats van hem in te perken.
    if (!identical(scope, SCOPE_ALLES) && !identical(input$k_niveau, "gemeente")) {
      g <- g[!is.na(g$stadsdeel) & g$stadsdeel == scope, ]
    }
    d <- kaart_data()
    kolommen <- c("region_code", "waarde", "metric_value", "n_totaal",
                  intersect(c("noemer", "compleet", "n_gevonden"), names(d)))
    merge(g, d[, ..kolommen], by = "region_code", all.x = TRUE)
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

    # Continue schaal in plaats van klassen: de nuances tussen twee regio's in
    # hetzelfde "vakje" gingen daar verloren. Het bereik komt uit
    # kaart_domein(), zodat een handmatig ingesteld bereik ook hier geldt en
    # twee kaarten naast elkaar te leggen zijn. Waarden erbuiten worden naar de
    # rand geklemd -- colorNumeric() zou ze anders de NA-kleur geven, wat als
    # "onvoldoende waarnemingen" leest.
    domein <- kaart_domein()
    pal <- colorNumeric("YlOrRd", domain = domein, na.color = MAP_NA_FILL)
    m$kleurwaarde <- map_klem(m$waarde, domein)

    fmt <- function(x) {
      if (is.na(x)) return("onvoldoende waarnemingen")
      if (map_is_aandeel(k_weergave())) sprintf("%.1f%%", x)
      else if (map_is_gemiddelde(k_weergave())) sprintf("%.2f", x)
      else format(round(x), big.mark = ".", decimal.mark = ",")
    }

    # Regio's waar een van de opgetelde groepen onderdrukt is: het cijfer telt
    # alleen op wat gepubliceerd is en is dus een ondergrens. Die krijgen een
    # gestippelde donkere rand, zodat het aan de kaart zelf te zien is en niet
    # alleen aan de melding erboven.
    onvolledig <- !is.na(m$compleet) & !m$compleet

    # Hoeveel van de gevraagde onderdelen hier gepubliceerd zijn. "1 van de 3"
    # zegt veel meer dan "ondergrens": bij 1 van de 3 kan het cijfer er ver
    # naast zitten, bij 5 van de 6 nauwelijks.
    gevraagd <- kaart_n_cellen()
    gevonden <- if (is.null(m$n_gevonden)) rep(gevraagd, nrow(m)) else m$n_gevonden

    # De regel onder de waarde: de teller en, bij een aandeel, de noemer waar
    # het percentage echt door gedeeld is. Dat was n_totaal -- het aantal
    # huishoudens/ouderen in de hele regio -- ook bij "aandeel binnen groep",
    # zodat de breuk in de tooltip iets anders zei dan het percentage erboven.
    # Bij een absolute weergave staat er geen noemer meer: daar wordt nergens
    # door gedeeld, en n_totaal erbij zetten nodigt uit tot een deling die voor
    # de n_kinderen_*-metrics niet eens dezelfde eenheid heeft (die tellen
    # kinderen tegen een huishoudnoemer). Een gemiddelde heeft al helemaal geen
    # teller om te tonen.
    noemer_woorden <- switch(k_weergave(),
                             rel_regio = "in deze regio",
                             rel_groep = "in deze groep",
                             rel       = "in deze groep",
                             "")
    n_regel <- function(w, mv, nmr) {
      if (is.na(w) || map_is_gemiddelde(k_weergave())) return("")
      getal <- format(round(mv), big.mark = ".", decimal.mark = ",", scientific = FALSE)
      if (!map_is_aandeel(k_weergave())) {
        return(sprintf("<br/><span style='color:#666'>n = %s</span>", getal))
      }
      if (is.na(nmr)) return(sprintf("<br/><span style='color:#666'>n = %s</span>", getal))
      sprintf("<br/><span style='color:#666'>n = %s van %s %s</span>",
              getal, format(round(nmr), big.mark = ".", decimal.mark = ",", scientific = FALSE),
              noemer_woorden)
    }

    labels <- mapply(function(nm, w, mv, nmr, half, k) {
      HTML(sprintf(
        "<b>%s</b><br/>%s: %s%s%s",
        nm, pretty_metric(input$k_metric), fmt(w),
        n_regel(w, mv, nmr),
        # Niet "ondergrens": bij een aandeel valt met de onderdrukte cel ook
        # een stuk noemer weg, en dan is het percentage geen ondergrens maar
        # eerder te hoog. Het feit zelf -- hoeveel er gepubliceerd is -- zegt
        # genoeg, en de melding boven de kaart legt het per weergave uit.
        if (isTRUE(half)) sprintf(
          "<br/><span style='color:#b3541e'>%d van de %d gekozen onderdelen gepubliceerd</span>",
          k, gevraagd) else ""
      ))
    # USE.NAMES = FALSE matters: mapply() would otherwise key the result by
    # region_name, and leaflet serialises a *named* list as one JS object that
    # every polygon then shares -- which renders as an empty tooltip.
    }, m$region_name, m$waarde, m$metric_value,
       if (is.null(m$noemer)) rep(NA_real_, nrow(m)) else m$noemer,
       onvolledig, gevonden,
       SIMPLIFY = FALSE, USE.NAMES = FALSE)

    proxy |>
      addPolygons(
        data = m,
        fillColor = ~pal(kleurwaarde), fillOpacity = 0.8,
        color = ifelse(onvolledig, "#3b3b3b", "#ffffff"),
        weight = ifelse(onvolledig, 1.6, 1),
        dashArray = ifelse(onvolledig, "3,4", ""),
        label = labels,
        labelOptions = labelOptions(direction = "auto", textsize = "13px"),
        highlightOptions = highlightOptions(weight = 3, color = "#272727",
                                            fillOpacity = 0.9, bringToFront = TRUE)
      ) |>
      addLegend(position = "bottomright", pal = pal, values = domein,
                title = eenheid(k_weergave()), opacity = 0.9,
                labFormat = labelFormat(suffix = if (map_is_aandeel(k_weergave())) "%" else ""),
                na.label = "onvoldoende")
  })

  # ------------------------------------------------------------ Per regio -----

  regio_data <- reactive({
    req(input$populatie, input$r_niveau, input$r_regio,
        input$r_var, input$r_val, input$r_metric)

    d <- ds |>
      filter(population    == !!input$populatie,
             region_level  == !!input$r_niveau,
             region_code   == !!input$r_regio,
             variable_name == !!input$r_var,
             variable_value== !!input$r_val,
             metric_name   == !!input$r_metric,
             split_var     == !!r_split_key(),
             # Staat een uitsplitsing op een vast niveau, dan gaat de hele
             # figuur over die groep; op "elk niveau apart" zijn dit gewoon
             # alle geleverde niveaus.
             split_level %in% !!niets_als_leeg(r_split_levels())) |>
      collect() |>
      as.data.table()

    d <- add_display(d, r_weergave())
    if (nrow(d) == 0) return(d)
    setorder(d, split_level, year)
    d[]
  })

  regio_titel <- reactive({
    req(input$r_var, input$r_metric, input$r_regio)
    nm <- names(region_choices[[input$r_niveau]])[
      match(input$r_regio, region_choices[[input$r_niveau]])]
    # De reeksvariabelen ("elk niveau apart") en de vastgezette variabelen
    # lezen verschillend: het eerste zegt waar de lijnen vandaan komen, het
    # tweede waar de hele figuur over gaat.
    sel <- r_split_sel()
    sp <- paste(c(
      if (length(sel$reeks_vars))
        sprintf("uitgesplitst naar %s", pretty_split(split_key(sel$reeks_vars))),
      vapply(names(sel$keuze), function(v)
        sprintf("%s: %s", pretty_split_1(v),
                paste(pretty_level(sel$keuze[[v]], v, input$populatie),
                      collapse = ", ")),
        character(1))), collapse = " | ")
    sp <- if (nzchar(sp)) paste0(" | ", sp) else ""
    sprintf("%s = %s | %s (%s) | %s%s",
            pretty_var(input$r_var),
            # Hetzelfde label als in de keuzelijst en op de Kaart-tab: daar
            # stond "Geen ondersteuning" waar deze titel nog "0" zei.
            pretty_value(input$r_val, input$r_var, input$populatie),
            pretty_metric(input$r_metric), eenheid(r_weergave()),
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
    # Alleen de variabelen op "elk niveau apart" horen in het legendalabel: een
    # variabele die op een vast niveau staat geldt voor de hele figuur en staat
    # al in de titel, dus die waarde in elke reeksnaam herhalen zegt niets.
    deel <- split_subset(r_split_key(), lv, r_split_sel()$reeks_vars)
    lab <- unname(pretty_level(deel$levels, deel$key, input$populatie))
    d[, reeks := factor(lab[match(split_level, lv)], levels = unique(lab))]
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
          if (r_weergave() == "rel") "%{y:.1f}%"
          else if (r_weergave() == "gem") "%{y:.2f}" else "%{y:,.0f}",
          "<extra></extra>")
      )
    }

    p |>
      layout(
        title = list(text = ""),
        xaxis = list(title = "", dtick = 1, tickmode = "linear"),
        yaxis = list(title = eenheid(r_weergave()),
                     rangemode = "tozero",
                     ticksuffix = if (r_weergave() == "rel") "%" else ""),
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
    add_display(d, r_weergave())
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

    add_display(d, r_weergave())
  })

  # De omvang van een deelgebied: sinds levering output_1b staat die als
  # gepubliceerd getal in de data (`n_split`, uit n_totaal_region_splitvar), dus
  # hoeft hij niet meer uit de noemer van een cel te komen. Dat verschil is
  # zichtbaar: de noemer telde alleen de gepubliceerde categorieen mee, terwijl
  # n_split de hele groep telt -- ook de huishoudens zonder enkele risicofactor
  # en de cellen die onderdrukt zijn. Een parquet van voor die levering heeft de
  # kolom niet; dan blijft het de oude noemer.
  groeps_n <- function(rows) {
    if (HEEFT_N_SPLIT && !all(is.na(rows$n_split))) return(rows$n_split[which(!is.na(rows$n_split))[1]])
    rows$denominator[1]
  }

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
      n[[k]] <- groeps_n(rows)
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

    add_display(d, r_weergave())
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
      n[[k]] <- groeps_n(rows)
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
            kleuring, pretty_metric(input$r_metric), eenheid(r_weergave()),
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
    HTML(venn_svg(venn_vals(), r_weergave(),
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
          if (r_weergave() == "rel")
            paste("Per rij verdeeld over de waarden van de risicoscore; elke rij telt op tot",
                  "100%.")
          else
            "Aantallen per groep en risicowaarde.",
          " n is de gepubliceerde omvang van die groep (het aantal huishoudens/",
          "ouderen erin), niet de som van de rij: een onderdrukte cel zit wel in n",
          " maar niet in de rij.",
          " Een streepje betekent onvoldoende waarnemingen, geen nul."),
      HTML(venn_matrix_html(mm$m, mm$n, r_weergave(),
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
          if (r_weergave() == "rel")
            "Per cel: het aandeel van die ondersteuningsgroep waarbij deze risicofactor speelt."
          else
            "Per cel: het aantal binnen die ondersteuningsgroep waarbij deze risicofactor speelt.",
          " Rijen tellen hier niet op tot n, om twee redenen: een huishouden/oudere",
          " kan meerdere risicofactoren tegelijk hebben (en telt dan in meer dan",
          " \u00e9\u00e9n kolom mee), en n is de hele groep \u2014 inclusief wie",
          " geen enkele risicofactor heeft. Een streepje betekent onvoldoende",
          " waarnemingen."),
      HTML(venn_matrix_html(rm$m, rm$n, r_weergave(),
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
    uit <- d[, .(populatie = population, regioniveau = region_level,
                 regiocode = region_code, regionaam = region_name, stadsdeel,
                 jaar = year, indicator = variable_name, waarde_indicator = variable_value,
                 metric = metric_name, aantal = metric_value,
                 n_totaal, noemer_binnen_groep = denominator,
                 weergegeven_waarde = waarde,
                 splitsvariabele = split_var, splitsniveau = split_level)]
    # Alleen een opgetelde kaartselectie draagt deze markering; hij hoort mee de
    # export in, anders is aan een cijfer niet te zien dat het een ondergrens is.
    if ("compleet" %in% names(d)) {
      uit[, `:=`(alle_groepen_aanwezig = d$compleet, onderdelen_gevonden = d$n_gevonden)]
    }
    # De twee noemers naast elkaar, zodat in de export na te rekenen is welk
    # aandeel er getoond werd en wat het andere geweest zou zijn -- plus, apart,
    # degene die bij deze weergave echt gebruikt is. Dat is dezelfde kolom als
    # de tooltip van de kaart toont, zodat het cijfer in het spreadsheet exact
    # na te rekenen is.
    if ("regio_totaal" %in% names(d)) uit[, noemer_regiototaal := d$regio_totaal]
    if ("indicator_totaal" %in% names(d)) uit[, noemer_indicatorwaarde := d$indicator_totaal]
    if ("noemer" %in% names(d)) uit[, gebruikte_noemer := d$noemer]
    # De gepubliceerde omvang van de regio x uitsplitsing waar deze rij bij
    # hoort: sinds output_1b een kolom in de levering, en de noemer van elk
    # aandeel waar de metric huishoudens/ouderen telt.
    if ("n_split" %in% names(d)) uit[, n_groep := d$n_split]
    uit[]
  }

  output$k_dl <- downloadHandler(
    filename = function() sprintf("dynamo_kaart_%s.xlsx", Sys.Date()),
    # Twee tabbladen sinds de kaart meerdere niveaus/waarden kan optellen: wat
    # er getekend is, en de cellen waar die optelling uit komt.
    content  = function(file) write_xlsx(
      list(kaart = export_cols(kaart_data()),
           onderliggend = export_cols(add_display(met_regio_totaal(copy(kaart_rijen())),
                                                  k_weergave()))), file)
  )

  # De kaart als plaatje. Leaflet tekent in de browser en laat zich hier niet
  # wegschrijven, dus choropleth_ggplot() tekent dezelfde laag opnieuw met
  # ggplot2 -- met hetzelfde kleurbereik (kaart_domein()), zodat de figuur en
  # het scherm dezelfde schaal hebben.
  output$k_dl_fig <- downloadHandler(
    filename = function() sprintf("dynamo_kaart_%s_%s.png", input$k_niveau, Sys.Date()),
    contentType = "image/png",
    content = function(file) {
      laag <- kaart_geo()
      # Dezelfde uitzondering als in kaart_geo(): op gemeenteniveau doet "Toon"
      # niets, dus het onderschrift moet er ook niet over opscheppen.
      scope <- if (identical(input$k_niveau, "gemeente")) SCOPE_ALLES
               else input$k_scope %||% SCOPE_ALLES
      p <- choropleth_ggplot(
        laag, kaart_domein(), k_weergave(),
        titel = sprintf("%s = %s", pretty_var(input$k_var), input$k_val),
        ondertitel = sprintf("%s (%s) | %s | %s%s",
                             pretty_metric(input$k_metric), eenheid(k_weergave()),
                             input$k_jaar, input$k_niveau,
                             if (identical(scope, SCOPE_ALLES)) ", heel Amsterdam"
                             else sprintf(", stadsdeel %s", scope)),
        bron = "Bron: CBS microdata via de Remote Access-omgeving.")
      # Een kaart van een stadsdeel is hoger dan breed, de hele stad juist niet;
      # het formaat volgt de verhouding van de laag zodat er geen witruimte
      # naast de kaart komt te staan. Een ontaarde bbox (een enkele regio, of
      # een lege selectie) zou NaN geven -- dan de standaardverhouding.
      bb <- sf::st_bbox(laag)
      breed <- as.numeric(bb[["xmax"]] - bb[["xmin"]])
      hoog  <- as.numeric(bb[["ymax"]] - bb[["ymin"]])
      ratio <- if (is.finite(breed) && is.finite(hoog) && breed > 0) hoog / breed else 0.9
      breedte <- 9
      # device expliciet: downloadHandler geeft een tijdelijk bestand zonder
      # extensie, en ggsave() leidt het device normaal juist daaruit af.
      ggplot2::ggsave(file, p, device = "png", width = breedte,
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
      "r_downloads" = "^(populatie|r_niveau|r_regio|r_var|r_val|r_metric|r_split_[A-Za-z0-9_]+|r_weergave)$"
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
      svg <- venn_svg(venn_vals(), r_weergave(),
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

  # "Wat is er nieuw": de lijst uit data/metadata/changelog.R. Het stipje op de
  # knop wordt in de browser bijgehouden (zie utils/changelog_ui.R); de server
  # hoeft alleen het venster te openen.
  observeEvent(input$changelog_knop, showModal(changelog_venster()))

  # The three shared tabs. They read the same state/ files any chart writes to,
  # so nothing here needs to know which charts are wired up.
  favorites_panel_server("favorieten")
  export_history_panel_server("exporthistorie")
  template_admin_server("templates")
}

shinyApp(ui, server)
