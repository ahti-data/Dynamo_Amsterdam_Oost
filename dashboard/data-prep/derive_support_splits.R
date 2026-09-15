#' Afgeleide ondersteuningsuitsplitsingen voor de Dynamo-output.
#'
#' De levering bevat per huishouden/oudere alleen `O_MPG_combination`/
#' `O_OUD_combination`: welke van de drie ondersteuningsgroepen tegelijk
#' spelen, als 8 niveaus ("none", 3 losse groepen, 3 paren, alle 3). Wat het
#' dashboard daarnaast nodig heeft -- "gebruikt dit gezin uberhaupt een vorm
#' van ondersteuning" en "hoeveel vormen tegelijk" -- staat er niet als eigen
#' kolom in, maar is er wel exact uit af te leiden: de 8 combinatieniveaus
#' partitioneren de populatie (geverifieerd op de levering van 09-09-2026:
#' de som over de 8 niveaus komt op de totaalrij uit, op afronding na).
#'
#' Dit bestand is de enige plek waar die afleiding gebeurt. Zowel
#' 01_build_app_data.R (nieuwe levering, vanaf de ruwe CSV/xlsx) als
#' 02_add_derived_splits.R (bestaande parquet bijwerken) roepen
#' add_support_derivations() aan, zodat de twee routes niet uit elkaar kunnen
#' lopen.
#'
#' ## Wat er bij komt
#'
#' **Als splitsvariabele** (kruisbaar met elke risicoscore, want
#' `variable_value` blijft de risicoscore):
#'   - `ondersteuningssignaal`        -- niveaus "geen" / "wel"
#'   - `aantal_ondersteuningsvormen`  -- niveaus "0" / "1" / "2" / "3"
#'
#' **Als indicator** (`variable_name`, met de ondersteuning in
#' `variable_value`), zodat de noemer -- som over de variable_value-categorieen
#' binnen de slice, de afspraak uit PLAN.md 6 -- de hele populatie is en
#' "Aandeel (%)" dus leest als *het percentage gezinnen dat een vorm van
#' ondersteuning gebruikt*:
#'   - `O_MPG_ondersteuning` / `O_OUD_ondersteuning`   -- waarden "geen"/"wel"
#'   - `O_MPG_aantal_vormen` / `O_OUD_aantal_vormen`   -- waarden "0".."3"
#'
#' ## Onderdrukking: exact of niets
#'
#' Cellen onder de 10 zijn in de levering onderdrukt, en onderdrukt betekent
#' hier een *ontbrekende rij*, geen NA (geverifieerd: de laagste metric_value
#' in de hele levering is 10). Een som over combinatieniveaus telt zo'n
#' ontbrekende cel stilzwijgend als nul -- precies wat de CBS-uitvoerregels
#' van dit project verbieden. Daarom wordt een afgeleide cel alleen
#' weggeschreven als elke bouwsteen eronder aanwezig is; anders komt er geen
#' rij, en toont het dashboard "onvoldoende waarnemingen" zoals bij elke
#' andere onderdrukte cel. Liever een grijs vlak dan een te laag getal.
#'
#' Concreet per afgeleid niveau:
#'   - "geen" / "0"  = de `none`-rij zelf                      (exact)
#'   - "wel"         = totaalrij - `none`-rij                  (exact; beide
#'                     gepubliceerd, en het verschil vangt ook de onderdrukte
#'                     losse combinaties op -- daarom niet de som van de 7)
#'   - "1"           = som van de 3 losse groepen              (alleen compleet)
#'   - "2"           = som van de 3 paren                      (alleen compleet)
#'   - "3"           = de rij met alle 3 de groepen            (exact)
#'
#' Voor de indicatorvorm geldt bovendien alles-of-niets: de noemer is de som
#' over de variable_value-categorieen, dus een percentage over een halve
#' partitie zou te hoog uitvallen. Een indicator wordt daarom pas
#' weggeschreven als al zijn categorieen beschikbaar zijn en elk daarvan over
#' de volledige set risicowaarden is opgeteld.

SUPPORT_TOTAL_LABEL <- "(totaal)"

SUPPORT_SPLIT_SIGNAL <- "ondersteuningssignaal"
SUPPORT_SPLIT_COUNT  <- "aantal_ondersteuningsvormen"

# population -> de kolomnaam van de combinatievariabele in de levering.
SUPPORT_COMBO_VAR <- c(
  "huishoudens met kinderen" = "O_MPG_combination",
  "ouderen (65+)"            = "O_OUD_combination"
)

# population -> de cumulatieve risicoscore. Eerste keus als bron voor de
# indicatorvorm (zie derive_support_indicator_rows): elke R_-score
# partitioneert dezelfde populatie, maar deze is de canonieke.
SUPPORT_SOURCE_VAR <- c(
  "huishoudens met kinderen" = "R_MPG_totaal",
  "ouderen (65+)"            = "R_OUD_totaal"
)

# population -> naam van de twee afgeleide indicatoren.
SUPPORT_INDICATOR_SIGNAL <- c(
  "huishoudens met kinderen" = "O_MPG_ondersteuning",
  "ouderen (65+)"            = "O_OUD_ondersteuning"
)
SUPPORT_INDICATOR_COUNT <- c(
  "huishoudens met kinderen" = "O_MPG_aantal_vormen",
  "ouderen (65+)"            = "O_OUD_aantal_vormen"
)

# Aantal deelgebieden per groepsgrootte in een 3-cirkel venn: 1 keer "geen",
# 3 losse groepen, 3 paren, 1 keer alle drie. Dit is wat "compleet" betekent
# voor de sommen hierboven.
SUPPORT_N_LEVELS <- c("0" = 1L, "1" = 3L, "2" = 3L, "3" = 1L)

# De CBS-drempel, ook toegepast op een afgeleid getal: "wel" is een verschil
# van twee gepubliceerde totalen en kan zelf onder de 10 uitkomen.
SUPPORT_MIN_CELL <- 10

#' Hoeveel ondersteuningsgroepen zitten er in een combinatieniveau.
#' "none" -> 0, "O_MPG1" -> 1, "O_MPG1 + O_MPG2" -> 2, alle drie -> 3.
support_n_forms <- function(level) {
  ifelse(level == "none", 0L, lengths(regmatches(level, gregexpr("+", level, fixed = TRUE))) + 1L)
}

# De groepssleutel van een afgeleide splitsrij: alles behalve de splitsing
# zelf en de waarde. n_totaal hoort erbij en niet in de aggregatie -- hij is
# constant per populatie x regio x jaar (PLAN.md 2b), dus hij maakt de
# groepen niet fijner, en zo blijft hij zonder join op de afgeleide rijen
# staan.
SUPPORT_GROUP_COLS <- c("population", "region_level", "region_code", "region_name",
                        "stadsdeel", "year", "variable_name", "variable_value",
                        "metric_name", "n_totaal")

# Idem voor een afgeleide indicatorrij: daar valt variable_name/variable_value
# weg (die worden zelf de ondersteuningscategorie).
SUPPORT_IND_GROUP_COLS <- c("population", "region_level", "region_code", "region_name",
                            "stadsdeel", "year", "metric_name", "n_totaal")

#' De twee afgeleide splitsvariabelen, uit de combinatierijen + de totaalrijen.
#'
#' @param dt data.table in het lange schema van 01_build_app_data.R, met in
#'   elk geval de combinatierijen en de totaalrijen (`split_var ==
#'   SUPPORT_TOTAL_LABEL`) van dezelfde slices.
#' @return data.table met dezelfde kolommen als `dt` (zonder `denominator` --
#'   die wordt na het samenvoegen over alles opnieuw berekend).
derive_support_split_rows <- function(dt) {
  stopifnot(is.data.table(dt))
  cols <- c(SUPPORT_GROUP_COLS, "metric_name", "metric_value", "split_var", "split_level")
  missing <- setdiff(unique(cols), names(dt))
  if (length(missing)) stop("Ontbrekende kolommen: ", paste(missing, collapse = ", "))

  combo <- dt[split_var == SUPPORT_COMBO_VAR[population]]
  if (nrow(combo) == 0L) return(dt[0L, c(SUPPORT_GROUP_COLS, "metric_value",
                                         "split_var", "split_level"), with = FALSE])
  combo <- combo[, c(SUPPORT_GROUP_COLS, "metric_value", "split_level"), with = FALSE]
  combo[, n_vormen := support_n_forms(split_level)]

  # -- aantal_ondersteuningsvormen -------------------------------------------
  # Som per groepsgrootte, maar alleen waar elk onderliggend combinatieniveau
  # gepubliceerd is: een ontbrekend niveau zou als nul meetellen.
  aantal <- combo[, .(metric_value = sum(metric_value), n_niveaus = .N),
                  by = c(SUPPORT_GROUP_COLS, "n_vormen")]
  aantal <- aantal[n_niveaus == SUPPORT_N_LEVELS[as.character(n_vormen)]]
  aantal[, `:=`(split_var = SUPPORT_SPLIT_COUNT,
                split_level = as.character(n_vormen),
                n_niveaus = NULL, n_vormen = NULL)]

  # -- ondersteuningssignaal --------------------------------------------------
  # "geen" is de none-rij zelf. "wel" is de totaalrij min de none-rij, en
  # bewust niet de som van de 7 andere niveaus: het verschil telt de
  # onderdrukte combinaties gewoon mee, de som laat ze vallen.
  geen <- combo[n_vormen == 0L, c(SUPPORT_GROUP_COLS, "metric_value"), with = FALSE]

  totaal <- dt[split_var == SUPPORT_TOTAL_LABEL & population %in% names(SUPPORT_COMBO_VAR),
               c(SUPPORT_GROUP_COLS, "metric_value"), with = FALSE]
  setnames(totaal, "metric_value", "totaal_value")

  wel <- merge(totaal, geen, by = SUPPORT_GROUP_COLS)  # inner: beide nodig
  wel[, metric_value := totaal_value - metric_value]
  wel[, totaal_value := NULL]
  # Zowel de totaalrij als de none-rij is afgerond op tientallen, dus het
  # verschil is dat ook. Wat eronder blijft (ook een negatief verschil door
  # afronding) valt af onder dezelfde drempel als de levering zelf hanteert.
  wel <- wel[metric_value >= SUPPORT_MIN_CELL]
  wel[, `:=`(split_var = SUPPORT_SPLIT_SIGNAL, split_level = "wel")]

  geen[, `:=`(split_var = SUPPORT_SPLIT_SIGNAL, split_level = "geen")]

  out <- rbind(aantal, geen, wel, use.names = TRUE)
  setcolorder(out, c(SUPPORT_GROUP_COLS, "metric_value", "split_var", "split_level"))
  out[]
}

#' De twee afgeleide indicatoren, uit de afgeleide splitsrijen.
#'
#' Hier wordt opgeteld over de risicowaarden, en dat mag alleen als die reeks
#' compleet is. Welke risicoscore de bron is maakt inhoudelijk niet uit: elke
#' `R_`-score verdeelt dezelfde populatie over zijn eigen categorieen, dus de
#' som over die categorieen is steeds hetzelfde aantal huishoudens/ouderen --
#' op afronding op tientallen na (op de levering van 09-09-2026 verschillen
#' complete bronnen onderling 0-20, precies de afrondingsmarge). Wat wel
#' uitmaakt is *onderdrukking*: de cumulatieve score heeft vier categorieen en
#' verliest er in een kleine buurt al snel een, terwijl een binaire score er
#' maar twee heeft. Daarom wordt per slice de eerste bron gekozen die volledig
#' gepubliceerd is, met de cumulatieve score voorop en daarna de losse
#' risicofactoren op naam. Dat tilt de dekking van het
#' ondersteuningssignaal op buurtniveau van 18% naar 64% zonder ook maar een
#' onderdrukte cel als nul mee te tellen.
#'
#' @param split_rows uitvoer van derive_support_split_rows().
#' @param vocab data.table met alle voorkomende (population, variable_name,
#'   variable_value)-combinaties uit de levering -- bepaalt hoeveel
#'   risicowaarden een complete som nodig heeft, zodat dat niet hier hoeft te
#'   worden vastgelegd.
derive_support_indicator_rows <- function(split_rows, vocab) {
  stopifnot(is.data.table(split_rows), is.data.table(vocab))
  leeg <- split_rows[0L, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
                           "metric_value", "split_var", "split_level"), with = FALSE]
  if (nrow(split_rows) == 0L) return(leeg)

  # Hoeveel categorieen heeft elke bronscore? Uit de levering zelf, niet
  # vastgelegd: een volgende levering kan een andere reeks hebben.
  n_waarden <- vocab[, .(n_waarden = uniqueN(variable_value)), by = .(population, variable_name)]

  # Hoeveel categorieen de afgeleide indicator zelf moet hebben. Alles of
  # niets: de noemer is de som over die categorieen, dus een half aanwezige
  # partitie zou een te hoog percentage geven.
  n_cat <- c(2L, length(SUPPORT_N_LEVELS))  # geen/wel, en 0 t/m 3
  names(n_cat) <- c(SUPPORT_SPLIT_SIGNAL, SUPPORT_SPLIT_COUNT)

  kand <- split_rows[, .(metric_value = sum(metric_value), n_gezien = uniqueN(variable_value)),
                     by = c(SUPPORT_IND_GROUP_COLS, "variable_name", "split_var", "split_level")]
  kand <- merge(kand, n_waarden, by = c("population", "variable_name"))
  kand <- kand[n_gezien == n_waarden]                       # complete risicoreeks
  kand[, n_cat_gezien := uniqueN(split_level),
       by = c(SUPPORT_IND_GROUP_COLS, "variable_name", "split_var")]
  kand <- kand[n_cat_gezien == n_cat[split_var]]            # complete partitie
  if (nrow(kand) == 0L) return(leeg)

  # Een bron per slice, zodat de categorieen onderling optellen: de
  # cumulatieve score als die compleet is, anders de eerste losse score op
  # naam.
  kand[, voorkeur := fifelse(variable_name == SUPPORT_SOURCE_VAR[population], 0L, 1L)]
  kand[, bron := variable_name[order(voorkeur, variable_name)][1L],
       by = c(SUPPORT_IND_GROUP_COLS, "split_var")]
  ind <- kand[variable_name == bron]

  ind[, variable_name := unname(fifelse(split_var == SUPPORT_SPLIT_SIGNAL,
                                        SUPPORT_INDICATOR_SIGNAL[population],
                                        SUPPORT_INDICATOR_COUNT[population]))]
  ind[, variable_value := split_level]
  ind[, `:=`(split_var = SUPPORT_TOTAL_LABEL, split_level = SUPPORT_TOTAL_LABEL,
             n_gezien = NULL, n_waarden = NULL, n_cat_gezien = NULL,
             voorkeur = NULL, bron = NULL)]
  setcolorder(ind, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
                     "metric_value", "split_var", "split_level"))
  ind[]
}

#' Voegt beide afgeleide vormen toe aan de lange tabel.
#'
#' Draait voor de noemerberekening in 01_build_app_data.R: `denominator` wordt
#' daarna over alles ineens berekend, dus ook over de rijen die hier bij komen.
#' Idempotent -- eerder afgeleide rijen gaan er eerst uit, zodat 02_ opnieuw
#' gedraaid kan worden.
add_support_derivations <- function(dt) {
  stopifnot(is.data.table(dt))

  dt <- dt[!split_var %in% c(SUPPORT_SPLIT_SIGNAL, SUPPORT_SPLIT_COUNT)]
  dt <- dt[!variable_name %in% c(SUPPORT_INDICATOR_SIGNAL, SUPPORT_INDICATOR_COUNT)]

  vocab <- unique(dt[, .(population, variable_name, variable_value)])

  split_rows <- derive_support_split_rows(dt)
  ind_rows   <- derive_support_indicator_rows(split_rows, vocab)

  out <- rbind(dt, split_rows, ind_rows, use.names = TRUE, fill = TRUE)
  setcolorder(out, names(dt))
  out[]
}
