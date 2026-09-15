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

# Alles is afgerond op tientallen, dus twee risicoscores die dezelfde populatie
# tellen komen op een tiental van elkaar uit: in Geuzenveld 2024 zeggen zeven
# bronnen 2.480 en drie 2.490. Dat is afronding, geen ontbrekende categorie --
# vandaar de mediaan als referentie en een marge van een afrondingsstap. Op de
# levering van 09-09-2026 is de spreiding binnen een slice in 84% van de
# gevallen precies 10 en in 99,6% hoogstens 20.
SUPPORT_ROUND_TOL <- 10

#' Afronden op tientallen, half naar boven -- de mediaan van twee
#' gepubliceerde waarden kan op een vijftal uitkomen, en de levering kent
#' alleen veelvouden van 10. round() zou hier bankiersafronding doen.
support_round10 <- function(x) floor(x / 10 + 0.5) * 10

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
#' Werkt per (regio, jaar, risicoscore, risicowaarde, metric): hier wordt niet
#' over de risicowaarden heen opgeteld, dus elke afgeleide cel is een som van
#' cellen die allemaal gepubliceerd moeten zijn. Waar dat niet lukt biedt het
#' complement soms alsnog uitkomst -- "1 vorm" en "2 vormen" tellen samen met
#' "3 vormen" op tot "wel", dus wie er twee kent, kent de derde exact.
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

  leeg <- dt[0L, c(SUPPORT_GROUP_COLS, "metric_value", "split_var", "split_level"), with = FALSE]

  combo <- dt[split_var == SUPPORT_COMBO_VAR[population]]
  if (nrow(combo) == 0L) return(leeg)
  combo <- combo[, c(SUPPORT_GROUP_COLS, "metric_value", "split_level"), with = FALSE]
  combo[, n_vormen := support_n_forms(split_level)]

  # Som per groepsgrootte, maar alleen waar elk onderliggend combinatieniveau
  # gepubliceerd is: een ontbrekend niveau zou als nul meetellen.
  aantal <- combo[, .(waarde = sum(metric_value), n_niveaus = .N),
                  by = c(SUPPORT_GROUP_COLS, "n_vormen")]
  aantal <- aantal[n_niveaus == SUPPORT_N_LEVELS[as.character(n_vormen)]]
  aantal[, n_niveaus := NULL]

  totaal <- dt[split_var == SUPPORT_TOTAL_LABEL & population %in% names(SUPPORT_COMBO_VAR),
               c(SUPPORT_GROUP_COLS, "metric_value"), with = FALSE]
  setnames(totaal, "metric_value", "totaal_waarde")

  # Breed zetten: per groep een kolom voor 0, 1, 2 en 3 vormen, plus het
  # totaal. Dat is wat het complement hieronder nodig heeft.
  w <- dcast(aantal, paste(paste(SUPPORT_GROUP_COLS, collapse = " + "), "~ n_vormen"),
             value.var = "waarde")
  for (kol in c("0", "1", "2", "3")) if (!kol %in% names(w)) w[, (kol) := NA_real_]
  setnames(w, c("0", "1", "2", "3"), c("k0", "k1", "k2", "k3"))
  w <- merge(w, totaal, by = SUPPORT_GROUP_COLS, all.x = TRUE)

  # "wel" komt uit de totaalrij min de none-rij, bewust niet uit de som van de
  # zeven andere niveaus: het verschil telt de onderdrukte combinaties gewoon
  # mee, de som laat ze vallen.
  w[, wel := totaal_waarde - k0]

  # Complement: k1 + k2 + k3 = wel. Kent een groep er twee van, dan is de derde
  # exact af te leiden -- ook als zijn eigen combinatieniveaus deels onderdrukt
  # zijn. Beide complementen worden berekend voordat er iets wordt ingevuld,
  # dus ze kunnen niet op elkaar terugslaan.
  w[, `:=`(k1_complement = wel - k2 - k3,
           k2_complement = wel - k1 - k3)]
  w[is.na(k1), k1 := k1_complement]
  w[is.na(k2), k2 := k2_complement]
  w[, c("k1_complement", "k2_complement") := NULL]

  lang <- melt(w, id.vars = SUPPORT_GROUP_COLS,
               measure.vars = c("k0", "k1", "k2", "k3", "wel"),
               variable.name = "categorie", value.name = "metric_value",
               variable.factor = FALSE, na.rm = TRUE)
  # Een afgeleid getal kan onder de CBS-drempel uitkomen (of door afronding
  # zelfs negatief); dan vervalt de cel, net als in de levering.
  lang <- lang[metric_value >= SUPPORT_MIN_CELL]

  aantal_rijen <- lang[categorie != "wel"]
  aantal_rijen[, `:=`(split_var = SUPPORT_SPLIT_COUNT,
                      split_level = sub("^k", "", categorie), categorie = NULL)]

  signaal <- rbind(
    lang[categorie == "wel"][, `:=`(split_level = "wel", categorie = NULL)],
    lang[categorie == "k0"][, `:=`(split_level = "geen", categorie = NULL)])
  signaal[, split_var := SUPPORT_SPLIT_SIGNAL]

  out <- rbind(aantal_rijen, signaal, use.names = TRUE)
  setcolorder(out, c(SUPPORT_GROUP_COLS, "metric_value", "split_var", "split_level"))
  out[]
}

#' De twee afgeleide indicatoren, rechtstreeks uit de combinatie- en
#' totaalrijen.
#'
#' Hier wordt wel over de risicowaarden heen opgeteld, en dat mag alleen als
#' die reeks compleet is. Welke risicoscore de bron is maakt inhoudelijk niet
#' uit: elke `R_`-score verdeelt dezelfde populatie over zijn eigen
#' categorieen, dus de som over die categorieen is steeds hetzelfde aantal
#' huishoudens/ouderen -- op afronding op tientallen na.
#'
#' **Wat "compleet" betekent, en waarom dat niet het landelijke aantal
#' categorieen is.** Een score kan in een regio minder categorieen hebben dan
#' landelijk, zonder dat er iets onderdrukt is: in Geuzenveld 2024 heeft
#' `R_MPG1_armoede_hh` alleen waarde `0`, en die ene rij telt 2.480 = de hele
#' wijk. Zo'n bron is juist de *beste* die er is -- geen kruising, dus geen
#' onderdrukking in de niveaurijen -- maar een toets op "landelijk twee
#' categorieen, hier een" gooit hem weg. De toets loopt daarom via de
#' totaalrijen van de bron zelf: tellen die op tot het regiototaal, dan dekken
#' zijn categorieen de hele populatie en ontbreekt er niets. Een niveaurij van
#' zo'n bron is exact zodra hij evenveel cellen heeft als de bron categorieen
#' heeft.
#'
#' Meerdere bruikbare bronnen geven hetzelfde niveautotaal, op afronding na
#' (gemeten spreiding 0-20); de mediaan vangt de afrondingsuitschieters.
derive_support_indicator_rows <- function(dt) {
  stopifnot(is.data.table(dt))
  leeg <- dt[0L, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
                   "metric_value", "split_var", "split_level"), with = FALSE]

  combo <- dt[split_var == SUPPORT_COMBO_VAR[population]]
  totaal <- dt[split_var == SUPPORT_TOTAL_LABEL & population %in% names(SUPPORT_COMBO_VAR)]
  if (nrow(combo) == 0L || nrow(totaal) == 0L) return(leeg)

  SL <- SUPPORT_IND_GROUP_COLS

  # -- bruikbare bronnen ------------------------------------------------------
  bron <- totaal[, .(bron_totaal = sum(metric_value), n_cat = uniqueN(variable_value)),
                 by = c(SL, "variable_name")]
  # Elke bron telt dezelfde populatie, dus de hoogste is de beste schatting van
  # het regiototaal: onderdrukking haalt er alleen af. Maar exact gelijk zijn ze
  # nooit -- afronding op tientallen zet ze een stap uit elkaar. Zonder die
  # marge zouden juist de beste bronnen afvallen: die met een of twee
  # categorieen in deze regio, en dus nauwelijks onderdrukking in hun
  # niveaurijen. Zie SUPPORT_ROUND_TOL.
  bron[, regio_totaal := max(bron_totaal), by = SL]
  # Wat een bron binnen die marge mist, zou een hele categorie onder de 10
  # zijn; daarboven mist zij er echt een en zou elk niveautotaal te laag worden.
  bron <- bron[regio_totaal - bron_totaal <= SUPPORT_ROUND_TOL]
  if (nrow(bron) == 0L) return(leeg)

  # -- niveautotalen ----------------------------------------------------------
  niv <- combo[, .(som = sum(metric_value), n_cel = uniqueN(variable_value)),
               by = c(SL, "variable_name", "split_level")]
  niv <- merge(niv, bron[, c(SL, "variable_name", "n_cat", "regio_totaal"), with = FALSE],
               by = c(SL, "variable_name"))
  niv <- niv[n_cel == n_cat]                      # geen onderdrukte cel in deze rij
  if (nrow(niv) == 0L) return(leeg)

  lev <- niv[, .(niveau = support_round10(median(som))),
             by = c(SL, "regio_totaal", "split_level")]
  lev[, n_vormen := support_n_forms(split_level)]

  IK <- c(SL, "regio_totaal")

  # -- signaal: alleen de none-rij nodig --------------------------------------
  signaal <- lev[split_level == "none", .(geen = niveau), by = IK]
  signaal[, wel := regio_totaal - geen]
  signaal <- melt(signaal, id.vars = IK, measure.vars = c("geen", "wel"),
                  variable.name = "variable_value", value.name = "metric_value",
                  variable.factor = FALSE)
  signaal[, variable_name := unname(SUPPORT_INDICATOR_SIGNAL[population])]

  # -- aantal vormen: alle vier de categorieen nodig --------------------------
  grp <- lev[, .(som = sum(niveau), n_niveaus = .N), by = c(IK, "n_vormen")]
  grp <- grp[n_niveaus == SUPPORT_N_LEVELS[as.character(n_vormen)]]
  aantal <- leeg[0L]
  if (nrow(grp) > 0L) {
    w <- dcast(grp, paste(paste(IK, collapse = " + "), "~ n_vormen"), value.var = "som")
    for (kol in c("0", "1", "2", "3")) if (!kol %in% names(w)) w[, (kol) := NA_real_]
    setnames(w, c("0", "1", "2", "3"), c("k0", "k1", "k2", "k3"))
    # Zelfde complement als bij de splitsvorm: k1 + k2 + k3 = wel.
    w[, wel := regio_totaal - k0]
    w[, `:=`(k1_complement = wel - k2 - k3, k2_complement = wel - k1 - k3)]
    w[is.na(k1), k1 := k1_complement]
    w[is.na(k2), k2 := k2_complement]
    # Alles-of-niets: de noemer van deze indicator is de som over zijn eigen
    # categorieen, dus een half aanwezige partitie zou het percentage te hoog
    # maken.
    w <- w[!is.na(k0) & !is.na(k1) & !is.na(k2) & !is.na(k3)]
    if (nrow(w) > 0L) {
      aantal <- melt(w, id.vars = IK, measure.vars = c("k0", "k1", "k2", "k3"),
                     variable.name = "variable_value", value.name = "metric_value",
                     variable.factor = FALSE)
      aantal[, variable_value := sub("^k", "", variable_value)]
      aantal[, variable_name := unname(SUPPORT_INDICATOR_COUNT[population])]
    }
  }

  ind <- rbind(signaal, aantal, use.names = TRUE, fill = TRUE)
  ind <- ind[metric_value >= SUPPORT_MIN_CELL]
  if (nrow(ind) == 0L) return(leeg)
  ind[, `:=`(split_var = SUPPORT_TOTAL_LABEL, split_level = SUPPORT_TOTAL_LABEL,
             regio_totaal = NULL)]
  setcolorder(ind, c(SL, "variable_name", "variable_value", "metric_value",
                     "split_var", "split_level"))
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

  split_rows <- derive_support_split_rows(dt)
  ind_rows   <- derive_support_indicator_rows(dt)

  out <- rbind(dt, split_rows, ind_rows, use.names = TRUE, fill = TRUE)
  setcolorder(out, names(dt))
  out[]
}
