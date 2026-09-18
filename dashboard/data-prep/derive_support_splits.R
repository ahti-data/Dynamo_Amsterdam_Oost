#' Afgeleide ondersteuningsuitsplitsingen voor de Dynamo-output.
#'
#' De levering bevat per huishouden/oudere alleen `O_MPG_combination`/
#' `O_OUD_combination`: welke van de drie ondersteuningsgroepen tegelijk
#' spelen, als 8 niveaus ("none", 3 losse groepen, 3 paren, alle 3). Wat het
#' dashboard daarnaast nodig heeft -- "gebruikt dit gezin uberhaupt een vorm
#' van ondersteuning" en "hoeveel vormen tegelijk" -- staat er niet als eigen
#' kolom in, maar is er wel exact uit af te leiden: de 8 combinatieniveaus
#' partitioneren de populatie.
#'
#' Dit bestand is de enige plek waar die afleiding gebeurt. Zowel
#' 01_build_app_data.R (nieuwe levering, vanaf de ruwe CSV/xlsx) als
#' 02_add_derived_splits.R (bestaande parquet bijwerken) roepen
#' add_support_derivations() aan, zodat de twee routes niet uit elkaar kunnen
#' lopen. Vereist utils/splits.R en utils/metrics.R.
#'
#' ## Wat er bij komt
#'
#' **Als splitsvariabele** (kruisbaar met elke risicoscore, want
#' `variable_value` blijft de risicoscore):
#'   - `ondersteuningssignaal`        -- niveaus "geen" / "wel"
#'   - `aantal_ondersteuningsvormen`  -- niveaus "0" / "1" / "2" / "3"
#'
#' **Als indicator** (`variable_name`, met de ondersteuning in
#' `variable_value`), zodat de noemer de hele populatie is en "Aandeel (%)"
#' dus leest als *het percentage gezinnen dat een vorm van ondersteuning
#' gebruikt*:
#'   - `O_MPG_ondersteuning` / `O_OUD_ondersteuning`   -- waarden "geen"/"wel"
#'   - `O_MPG_aantal_vormen` / `O_OUD_aantal_vormen`   -- waarden "0".."3"
#'   - `O_MPG_combinatie`    / `O_OUD_combinatie`      -- het combinatieniveau zelf
#'
#' ## Wat er met levering output_1b veranderde
#'
#' De levering draagt nu `n_totaal_region_splitvar` (hier `n_split`): het aantal
#' huishoudens/ouderen in die regio x uitsplitsing. Daarmee is de *omvang* van
#' elk combinatieniveau een gepubliceerd getal in plaats van iets wat
#' teruggerekend moest worden uit de som over de risicocategorieen. Die
#' terugrekening -- een mediaan over "bruikbare bronnen", met een
#' afrondingsmarge om te bepalen welke risicoscore de regio volledig dekte --
#' is daarmee weg voor elke metric die de populatie-eenheid telt.
#'
#' Dat scheelt niet alleen code. De oude route kon een niveautotaal alleen
#' bepalen als een hele reeks risicocategorieen gepubliceerd was; de nieuwe
#' heeft aan een enkele rij van dat niveau genoeg, want `n_split` hangt niet van
#' de risicowaarde af. `n_split` is bovendien per definitie exact, waar de
#' categoriesom alles miste wat onderdrukt was.
#'
#' Ook nieuw: een rij kan naar meer dan een variabele tegelijk uitgesplitst zijn
#' (utils/splits.R). Een afleiding gebeurt daarom binnen de *rest* van de
#' sleutel: de combinatie wordt vervangen door de afgeleide variabele en de
#' andere onderdelen blijven staan, dus
#' `O_MPG_combination | geslacht` levert `aantal_ondersteuningsvormen | geslacht`.
#'
#' ## Onderdrukking
#'
#' Cellen onder de 10 zijn in de levering onderdrukt, en onderdrukt betekent
#' hier een *ontbrekende rij*, geen NA. Een som over combinatieniveaus telt zo'n
#' ontbrekende cel stilzwijgend als nul -- precies wat de CBS-uitvoerregels
#' van dit project verbieden. Voor alles wat nog wel opgeteld moet worden geldt
#' daarom onverminderd: een afgeleide cel wordt alleen weggeschreven als elke
#' bouwsteen eronder aanwezig is.
#'
#' Concreet per afgeleide *celwaarde* (`metric_value`, gekruist met de
#' risicowaarde -- daar helpt `n_split` niet, want die hangt niet van de
#' risicowaarde af):
#'   - "geen" / "0"  = de `none`-rij zelf                      (exact)
#'   - "wel"         = referentierij - `none`-rij              (exact; beide
#'                     gepubliceerd, en het verschil vangt ook de onderdrukte
#'                     losse combinaties op -- daarom niet de som van de 7)
#'   - "1"           = som van de 3 losse groepen              (alleen compleet)
#'   - "2"           = som van de 3 paren                      (alleen compleet)
#'   - "3"           = de rij met alle 3 de groepen            (exact)
#'
#' De *omvang* van elke afgeleide groep (`n_split`, en daarmee de noemer van
#' elk aandeel) komt uit de gepubliceerde groepsgroottes en is exact, behalve
#' waar een heel combinatieniveau in die regio nergens voorkomt. Wat dan niet
#' toe te wijzen is, blijft als restcategorie zichtbaar in plaats van stil de
#' noemer te verkleinen.

SUPPORT_TOTAL_LABEL <- if (exists("SPLIT_TOTAL_LABEL")) SPLIT_TOTAL_LABEL else "(totaal)"

SUPPORT_SPLIT_SIGNAL <- "ondersteuningssignaal"
SUPPORT_SPLIT_COUNT  <- "aantal_ondersteuningsvormen"

# population -> de kolomnaam van de combinatievariabele in de levering.
SUPPORT_COMBO_VAR <- c(
  "huishoudens met kinderen" = "O_MPG_combination",
  "ouderen (65+)"            = "O_OUD_combination"
)

# population -> naam van de afgeleide indicatoren.
SUPPORT_INDICATOR_SIGNAL <- c(
  "huishoudens met kinderen" = "O_MPG_ondersteuning",
  "ouderen (65+)"            = "O_OUD_ondersteuning"
)
SUPPORT_INDICATOR_COUNT <- c(
  "huishoudens met kinderen" = "O_MPG_aantal_vormen",
  "ouderen (65+)"            = "O_OUD_aantal_vormen"
)
SUPPORT_INDICATOR_COMBO <- c(
  "huishoudens met kinderen" = "O_MPG_combinatie",
  "ouderen (65+)"            = "O_OUD_combinatie"
)

# Restcategorie: het deel van de populatie dat niet aan 0, 1, 2 of 3 vormen toe
# te wijzen is. Zonder die categorie zou de noemer (de som over de categorieen)
# te klein zijn en elk percentage te hoog; met die categorie klopt de noemer
# exact en is meteen zichtbaar wat er niet toegewezen kon worden.
SUPPORT_UNKNOWN <- "onbekend"

# Aantal deelgebieden per groepsgrootte in een 3-cirkel venn: 1 keer "geen",
# 3 losse groepen, 3 paren, 1 keer alle drie. Dit is wat "compleet" betekent
# voor de sommen hierboven.
SUPPORT_N_LEVELS <- c("0" = 1L, "1" = 3L, "2" = 3L, "3" = 1L)

# De CBS-drempel, ook toegepast op een afgeleid getal: "wel" is een verschil
# van twee gepubliceerde totalen en kan zelf onder de 10 uitkomen.
SUPPORT_MIN_CELL <- 10

# Alles is afgerond op tientallen, dus twee risicoscores die dezelfde populatie
# tellen komen op een tiental van elkaar uit. Alleen nog in gebruik op de
# terugrekenroute voor de niet-populatiemetrics.
SUPPORT_ROUND_TOL <- 10

#' Afronden op tientallen, half naar boven -- de levering kent alleen
#' veelvouden van 10 en round() zou hier bankiersafronding doen.
support_round10 <- function(x) floor(x / 10 + 0.5) * 10

#' Hoeveel ondersteuningsgroepen zitten er in een combinatieniveau.
#' "none" -> 0, "O_MPG1" -> 1, "O_MPG1 + O_MPG2" -> 2, alle drie -> 3.
support_n_forms <- function(level) {
  ifelse(level == "none", 0L, lengths(regmatches(level, gregexpr("+", level, fixed = TRUE))) + 1L)
}

# De groepssleutel van een afgeleide splitsrij: alles behalve de splitsing zelf
# en de waarde. n_totaal hoort erbij en niet in de aggregatie -- hij is constant
# per populatie x regio x jaar (PLAN.md 2b), dus hij maakt de groepen niet
# fijner, en zo blijft hij zonder join op de afgeleide rijen staan.
SUPPORT_GROUP_COLS <- c("population", "region_level", "region_code", "region_name",
                        "stadsdeel", "year", "variable_name", "variable_value",
                        "metric_name", "n_totaal")

# Idem voor een afgeleide indicatorrij: daar valt variable_name/variable_value
# weg (die worden zelf de ondersteuningscategorie).
SUPPORT_IND_GROUP_COLS <- c("population", "region_level", "region_code", "region_name",
                            "stadsdeel", "year", "metric_name", "n_totaal")

# Wat er van de splitssleutel overblijft als de combinatie eruit gehaald is.
# Voor een rij die alleen naar de combinatie is uitgesplitst is dat
# "(totaal)"/"(totaal)" -- het geval dat tot output_1a het enige was.
SUPPORT_REST_COLS <- c("rest_var", "rest_level")

# De sleutel waarop groepsgroottes gelden: die hangen niet van de indicator, de
# risicowaarde of de metric af, alleen van regio x jaar x uitsplitsing. Dat is
# precies waarom `n_split` zoveel meer dekking geeft dan de oude categoriesom --
# een enkele gepubliceerde rij van dat niveau volstaat.
SUPPORT_SIZE_KEY <- c("population", "region_level", "region_code", "year",
                      "rest_var", "rest_level")

#' Ontleedt de splitssleutel in het combinatie-onderdeel en de rest.
#'
#' @param dt data.table in het lange schema.
#' @return De deelverzameling rijen waarvan de sleutel de combinatievariabele
#'   bevat, met de extra kolommen `combo_level`, `rest_var` en `rest_level`.
support_combo_rows <- function(dt) {
  sleutels <- unique(dt$split_var)
  uit <- vector("list", length(sleutels))
  for (i in seq_along(sleutels)) {
    sv <- sleutels[[i]]
    p <- split_parts(sv)
    idx <- which(p %in% SUPPORT_COMBO_VAR)
    if (length(idx) != 1L) next            # geen combinatie in deze sleutel
    rows <- dt[split_var == sv]
    if (nrow(rows) == 0L) next
    lv <- if (length(p) == 1L) list(rows$split_level) else
      tstrsplit(rows$split_level, SPLIT_SEP, fixed = TRUE)
    rest <- p[-idx]
    rows[, `:=`(
      combo_level = lv[[idx]],
      rest_var    = if (length(rest)) paste(rest, collapse = SPLIT_SEP) else SUPPORT_TOTAL_LABEL,
      rest_level  = if (length(rest)) do.call(paste, c(lv[-idx], list(sep = SPLIT_SEP)))
                    else SUPPORT_TOTAL_LABEL)]
    uit[[i]] <- rows
  }
  uit <- uit[!vapply(uit, is.null, logical(1))]
  if (length(uit) == 0L) {
    leeg <- copy(dt[0L])
    leeg[, `:=`(combo_level = character(), rest_var = character(), rest_level = character())]
    return(leeg)
  }
  rbindlist(uit, use.names = TRUE)
}

#' De referentierijen bij een restsleutel: dezelfde slice, maar zonder de
#' combinatie erin. Voor een lege rest zijn dat de totaalrijen.
support_ref_rows <- function(dt, rest_keys) {
  ref <- dt[split_var %in% rest_keys]
  if (nrow(ref) == 0L) return(ref)
  ref <- copy(ref)
  ref[, `:=`(rest_var = split_var, rest_level = split_level)]
  ref[]
}

#' Gepubliceerde groepsgroottes per combinatieniveau.
#'
#' `n_split` hangt alleen van regio x jaar x uitsplitsing af, dus deze tabel
#' gaat dwars door alle indicatoren, risicowaarden en metrics heen. Dat is wat
#' de dekking zo veel groter maakt dan onder output_1a: een niveau telt mee
#' zodra er ergens een rij van bestaat.
support_group_sizes <- function(combo) {
  if (nrow(combo) == 0L || !"n_split" %in% names(combo)) {
    return(data.table(population = character(), region_level = character(),
                      region_code = character(), year = integer(),
                      rest_var = character(), rest_level = character(),
                      combo_level = character(), n = numeric()))
  }
  gs <- combo[!is.na(n_split), .(n = n_split[1], spreiding = diff(range(n_split))),
              by = c(SUPPORT_SIZE_KEY, "combo_level")]
  # n_split hoort binnen deze sleutel constant te zijn -- op afronding na. Elk
  # aantal in de levering is los op tientallen afgerond, dus dezelfde groep kan
  # er op de ene rij als 49.950 en op de andere als 49.960 in staan; in
  # output_1b gebeurt dat in 2 van de 7.744 groepen, steeds precies een tiental.
  # Loopt het verder uiteen, dan telt de kolom iets anders dan de afleiding
  # aanneemt, en dat hoort hardop gezegd te worden -- alles hieronder rekent erop.
  if (any(gs$spreiding > SUPPORT_ROUND_TOL)) {
    warning(sprintf(paste("n_split varieert binnen regio x jaar x uitsplitsing x",
                          "combinatieniveau met meer dan een afrondingsstap (%d",
                          "groepen). De afleiding neemt de eerste waarde;",
                          "controleer de levering."),
                    sum(gs$spreiding > SUPPORT_ROUND_TOL)))
  }
  gs[, spreiding := NULL]
  gs[]
}

#' Idem voor de referentierij: de omvang van de hele populatie binnen de rest
#' van de uitsplitsing (en dus van de regio als de rest leeg is).
support_ref_sizes <- function(ref) {
  if (nrow(ref) == 0L || !"n_split" %in% names(ref)) {
    return(data.table(population = character(), region_level = character(),
                      region_code = character(), year = integer(),
                      rest_var = character(), rest_level = character(),
                      n_ref = numeric()))
  }
  ref[!is.na(n_split), .(n_ref = n_split[1]), by = SUPPORT_SIZE_KEY]
}

#' De exacte omvang van elke afgeleide ondersteuningscategorie.
#'
#' Eén tabel voor beide afgeleide vormen: de splitsrijen gebruiken hem als
#' noemer (`n_split`), en voor elke metric die de populatie-eenheid telt is hij
#' meteen ook de *waarde* van de indicatorvorm -- "hoeveel gezinnen zitten in
#' deze groep" is per definitie de groepsgrootte.
#'
#' @return data.table met SUPPORT_SIZE_KEY, `categorie` ("0".."3", "geen",
#'   "wel", "onbekend", of een combinatieniveau) en `n`.
support_categorie_n <- function(combo, ref) {
  gs  <- support_group_sizes(combo)
  rs  <- support_ref_sizes(ref)
  if (nrow(gs) == 0L) {
    return(data.table(population = character(), region_level = character(),
                      region_code = character(), year = integer(),
                      rest_var = character(), rest_level = character(),
                      categorie = character(), n = numeric()))
  }

  gs[, n_vormen := support_n_forms(combo_level)]
  per <- gs[, .(n = sum(n), n_niveaus = .N), by = c(SUPPORT_SIZE_KEY, "n_vormen")]
  per <- per[n_niveaus == SUPPORT_N_LEVELS[as.character(n_vormen)]][, n_niveaus := NULL]

  w <- dcast(per, paste(paste(SUPPORT_SIZE_KEY, collapse = " + "), "~ n_vormen"),
             value.var = "n")
  for (kol in c("0", "1", "2", "3")) if (!kol %in% names(w)) w[, (kol) := NA_real_]
  setnames(w, c("0", "1", "2", "3"), c("k0", "k1", "k2", "k3"))
  if (nrow(rs) > 0L) {
    w <- merge(w, rs, by = SUPPORT_SIZE_KEY, all.x = TRUE)
  } else {
    w[, n_ref := NA_real_]   # geen referentierij: "wel" en de rest onbekend
  }

  # "wel" uit de referentierij min de none-groep: exact, en het vangt ook de
  # combinatieniveaus op die zelf te klein zijn om gepubliceerd te worden.
  w[, wel := n_ref - k0]
  # Complement: k1 + k2 + k3 = wel. Beide complementen worden berekend voordat
  # er iets wordt ingevuld, dus ze kunnen niet op elkaar terugslaan.
  w[, `:=`(k1_complement = wel - k2 - k3, k2_complement = wel - k1 - k3)]
  w[is.na(k1), k1 := k1_complement]
  w[is.na(k2), k2 := k2_complement]
  w[, c("k1_complement", "k2_complement") := NULL]
  # Wat overblijft is niet toe te wijzen; als eigen categorie wegschrijven zodat
  # de noemer de hele populatie blijft.
  w[, (SUPPORT_UNKNOWN) := n_ref - rowSums(.SD, na.rm = TRUE),
    .SDcols = c("k0", "k1", "k2", "k3")]

  vormen <- melt(w, id.vars = SUPPORT_SIZE_KEY,
                 measure.vars = c("k0", "k1", "k2", "k3", "wel", SUPPORT_UNKNOWN),
                 variable.name = "categorie", value.name = "n",
                 variable.factor = FALSE, na.rm = TRUE)
  vormen[categorie == "k0", categorie := "geen_en_0"]
  # "geen" (van het signaal) en "0" (van het aantal vormen) zijn hetzelfde
  # niveau met twee namen; allebei wegschrijven, zodat de rest van dit bestand
  # ze los kan opzoeken.
  vormen <- rbind(
    vormen[categorie != "geen_en_0"],
    vormen[categorie == "geen_en_0"][, categorie := "geen"],
    vormen[categorie == "geen_en_0"][, categorie := "0"])
  vormen[categorie %in% c("k1", "k2", "k3"), categorie := sub("^k", "", categorie)]

  # De combinatieniveaus zelf horen er ook bij: dat is de derde indicator.
  niveaus <- gs[, c(SUPPORT_SIZE_KEY, "combo_level", "n"), with = FALSE]
  setnames(niveaus, "combo_level", "categorie")

  uit <- rbind(vormen, niveaus, use.names = TRUE)
  # Een groep onder de CBS-drempel is geen publiceerbare groep, ook niet als
  # hij uit een verschil komt.
  uit <- uit[!is.na(n) & n >= SUPPORT_MIN_CELL]
  uit[]
}

#' De twee afgeleide splitsvariabelen, uit de combinatierijen + de referentierijen.
#'
#' Werkt per (regio, jaar, risicoscore, risicowaarde, metric, rest van de
#' uitsplitsing): hier wordt niet over de risicowaarden heen opgeteld, dus elke
#' afgeleide celwaarde is een som van cellen die allemaal gepubliceerd moeten
#' zijn. Waar dat niet lukt biedt het complement soms alsnog uitkomst -- "1
#' vorm" en "2 vormen" tellen samen met "3 vormen" op tot "wel".
#'
#' De *noemer* van die cellen komt sinds output_1b uit de gepubliceerde
#' groepsgroottes (`n_split`) en is dus exact, ook waar de celwaarden zelf
#' gedeeltelijk onderdrukt zijn.
#'
#' @param dt data.table in het lange schema van 01_build_app_data.R.
#' @return data.table met dezelfde kolommen als `dt` (zonder `denominator` --
#'   die wordt na het samenvoegen over alles opnieuw berekend).
derive_support_split_rows <- function(dt) {
  stopifnot(is.data.table(dt))
  cols <- c(SUPPORT_GROUP_COLS, "metric_value", "split_var", "split_level")
  missing <- setdiff(unique(cols), names(dt))
  if (length(missing)) stop("Ontbrekende kolommen: ", paste(missing, collapse = ", "))

  leeg <- dt[0L, c(SUPPORT_GROUP_COLS, "metric_value", "n_split",
                   "split_var", "split_level"), with = FALSE]

  combo <- support_combo_rows(dt)
  if (nrow(combo) == 0L) return(leeg)
  # De referentierij mag ontbreken: zonder hem is "wel" niet af te leiden (dat
  # is een verschil met de totaalrij), maar "geen" en de groepsgroottes staan
  # los van hem en blijven gewoon bestaan.
  ref <- support_ref_rows(dt, unique(combo$rest_var))

  GK <- c(SUPPORT_GROUP_COLS, SUPPORT_REST_COLS)
  combo[, n_vormen := support_n_forms(combo_level)]

  # Som per groepsgrootte, maar alleen waar elk onderliggend combinatieniveau
  # gepubliceerd is: een ontbrekend niveau zou als nul meetellen.
  aantal <- combo[, .(waarde = sum(metric_value), n_niveaus = uniqueN(combo_level)),
                  by = c(GK, "n_vormen")]
  aantal <- aantal[n_niveaus == SUPPORT_N_LEVELS[as.character(n_vormen)]]
  aantal[, n_niveaus := NULL]
  if (nrow(aantal) == 0L) return(leeg)

  w <- dcast(aantal, paste(paste(GK, collapse = " + "), "~ n_vormen"), value.var = "waarde")
  for (kol in c("0", "1", "2", "3")) if (!kol %in% names(w)) w[, (kol) := NA_real_]
  setnames(w, c("0", "1", "2", "3"), c("k0", "k1", "k2", "k3"))
  if (nrow(ref) > 0L) {
    totaal <- ref[, c(GK, "metric_value"), with = FALSE]
    setnames(totaal, "metric_value", "totaal_waarde")
    w <- merge(w, totaal, by = GK, all.x = TRUE)
  } else {
    w[, totaal_waarde := NA_real_]
  }

  # "wel" komt uit de referentierij min de none-rij, bewust niet uit de som van
  # de zeven andere niveaus: het verschil telt de onderdrukte combinaties mee,
  # de som laat ze vallen.
  w[, wel := totaal_waarde - k0]
  w[, `:=`(k1_complement = wel - k2 - k3, k2_complement = wel - k1 - k3)]
  w[is.na(k1), k1 := k1_complement]
  w[is.na(k2), k2 := k2_complement]
  w[, c("k1_complement", "k2_complement") := NULL]

  lang <- melt(w, id.vars = GK, measure.vars = c("k0", "k1", "k2", "k3", "wel"),
               variable.name = "categorie", value.name = "metric_value",
               variable.factor = FALSE, na.rm = TRUE)
  # Een afgeleid getal kan onder de CBS-drempel uitkomen (of door afronding
  # zelfs negatief); dan vervalt de cel, net als in de levering.
  lang <- lang[metric_value >= SUPPORT_MIN_CELL]
  if (nrow(lang) == 0L) return(leeg)

  aantal_rijen <- lang[categorie != "wel"]
  aantal_rijen[, `:=`(afgeleide_var = SUPPORT_SPLIT_COUNT,
                      niveau = sub("^k", "", categorie), categorie = NULL)]

  signaal <- rbind(
    lang[categorie == "wel"][, `:=`(niveau = "wel", categorie = NULL)],
    lang[categorie == "k0"][, `:=`(niveau = "geen", categorie = NULL)])
  signaal[, afgeleide_var := SUPPORT_SPLIT_SIGNAL]

  out <- rbind(aantal_rijen, signaal, use.names = TRUE)

  # De exacte groepsomvang eraan: dat wordt straks de noemer van elk aandeel.
  cat_n <- support_categorie_n(combo, ref)
  out <- merge(out, cat_n, by.x = c(SUPPORT_SIZE_KEY, "niveau"),
               by.y = c(SUPPORT_SIZE_KEY, "categorie"), all.x = TRUE)
  setnames(out, "n", "n_split")

  # De sleutel weer samenstellen: de combinatie is vervangen door de afgeleide
  # variabele, de rest van de uitsplitsing blijft staan. De namen gaan
  # alfabetisch (split_key()), dus de waarden moeten in diezelfde volgorde --
  # anders wijst de sleutel naar het verkeerde niveau. Per unieke combinatie van
  # (afgeleide variabele, rest) is die volgorde hetzelfde, en dat zijn er een
  # handvol, dus dat scheelt een berekening per rij.
  out[, `:=`(split_var = NA_character_, split_level = NA_character_)]
  paren <- unique(out[, .(afgeleide_var, rest_var)])
  for (r in seq_len(nrow(paren))) {
    av <- paren$afgeleide_var[r]
    rv <- paren$rest_var[r]
    rest_namen <- split_parts(rv)
    namen <- c(av, rest_namen)
    volgorde <- order(namen, method = "radix")   # zelfde volgorde als split_key()
    i <- out[, which(afgeleide_var == av & rest_var == rv)]
    set(out, i = i, j = "split_var", value = paste(namen[volgorde], collapse = SPLIT_SEP))
    if (length(rest_namen) == 0L) {
      set(out, i = i, j = "split_level", value = out$niveau[i])
    } else {
      delen <- c(list(out$niveau[i]),
                 tstrsplit(out$rest_level[i], SPLIT_SEP, fixed = TRUE))
      set(out, i = i, j = "split_level",
          value = do.call(paste, c(delen[volgorde], list(sep = SPLIT_SEP))))
    }
  }

  out <- out[, c(SUPPORT_GROUP_COLS, "metric_value", "n_split",
                 "split_var", "split_level"), with = FALSE]
  out[]
}

#' De afgeleide indicatoren: de ondersteuning als `variable_name`.
#'
#' Twee routes, en welke er geldt hangt aan wat de metric telt:
#'
#' **Exact (metrics die de populatie-eenheid tellen).** "Hoeveel gezinnen zitten
#' in deze ondersteuningsgroep" *is* de groepsgrootte, en die publiceert de
#' levering sinds output_1b als `n_split`. Geen som over risicowaarden, geen
#' completeness-toets, geen mediaan over bronnen -- alleen de gepubliceerde
#' getallen. Dit is de route die het dashboard standaard laat zien.
#'
#' Let op het verschil tussen de twee afgeleide vormen. Bij de *splits*vorm is de
#' categorie de groep zelf, dus daar is de groepsomvang ook de noemer. Bij de
#' *indicator*vorm staat de categorie in `variable_value` en is de noemer juist
#' de hele populatie binnen de rest van de uitsplitsing -- anders leest elk
#' aandeel als 100%. Vandaar dat `n_split` hier de referentie-omvang krijgt en
#' niet de categorie-omvang.
#'
#' **Terugrekenen (de overige metrics).** De `n_kinderen_*`-metrics tellen
#' kinderen, niet huishoudens, dus `n_split` is er de verkeerde eenheid voor en
#' het niveautotaal moet nog steeds uit de som over de risicocategorieen komen.
#' Dat mag alleen als die reeks compleet is, en "compleet" wordt getoetst aan de
#' totaalrijen van de bron zelf: tellen die op tot het regiototaal, dan dekken
#' zijn categorieen de hele populatie. (Een score kan in een regio minder
#' categorieen hebben dan landelijk zonder dat er iets onderdrukt is -- in
#' Geuzenveld 2024 heeft `R_MPG1_armoede_hh` alleen waarde `0`, en die ene rij
#' telt de hele wijk. Toetsen op het landelijke aantal gooit juist die weg.)
#' Deze route draait alleen op de niet-samengestelde uitsplitsing; met een
#' kruising erbij is de reeks vrijwel altijd te onvolledig om iets te kunnen
#' zeggen.
derive_support_indicator_rows <- function(dt) {
  stopifnot(is.data.table(dt))
  leeg <- dt[0L, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
                   "metric_value", "n_split", "split_var", "split_level"), with = FALSE]

  combo <- support_combo_rows(dt)
  if (nrow(combo) == 0L) return(leeg)
  ref <- support_ref_rows(dt, unique(combo$rest_var))
  if (nrow(ref) == 0L) return(leeg)

  exact  <- support_indicator_exact(dt, combo, ref)
  oud    <- support_indicator_reconstructed(dt, combo, ref)

  ind <- rbind(exact, oud, use.names = TRUE, fill = TRUE)
  if (nrow(ind) == 0L) return(leeg)
  ind <- ind[metric_value >= SUPPORT_MIN_CELL]
  if (nrow(ind) == 0L) return(leeg)
  setcolorder(ind, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
                     "metric_value", "n_split", "split_var", "split_level"))
  ind[]
}

#' De exacte route: de indicatorwaarde *is* de groepsgrootte.
support_indicator_exact <- function(dt, combo, ref) {
  leeg <- dt[0L, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
                   "metric_value", "n_split", "split_var", "split_level"), with = FALSE]

  cat_n <- support_categorie_n(combo, ref)
  if (nrow(cat_n) == 0L) return(leeg)

  # Voor welke metrics geldt dit: die de populatie-eenheid tellen en in deze
  # levering ook echt voorkomen.
  mets <- unique(dt[metric_telt_populatie(metric_name), .(population, metric_name)])
  if (nrow(mets) == 0L) return(leeg)

  # De regio-informatie die een indicatorrij nodig heeft en die niet in de
  # groepsgroottetabel zit.
  regio <- unique(dt[, .(population, region_level, region_code, region_name,
                         stadsdeel, year, n_totaal)])
  # n_totaal is constant per populatie x regio x jaar (PLAN.md 2b); de eerste
  # niet-lege waarde is dus de waarde. Geen max(na.rm = TRUE): dat geeft -Inf
  # met een waarschuwing als een regio er toevallig geen heeft.
  regio <- regio[, .(region_name = region_name[1], stadsdeel = stadsdeel[1],
                     n_totaal = {
                       v <- n_totaal[!is.na(n_totaal)]
                       if (length(v)) v[1] else NA_real_
                     }),
                 by = .(population, region_level, region_code, year)]

  ind <- merge(cat_n, mets, by = "population", allow.cartesian = TRUE)
  ind <- merge(ind, regio, by = c("population", "region_level", "region_code", "year"))

  # De omvang van de *slice* waar deze rij in staat -- niet die van de categorie.
  # Een indicatorrij draagt de ondersteuning in variable_value, dus de groep
  # waarbinnen hij gelezen wordt is de hele populatie binnen de rest van de
  # uitsplitsing: dat is precies wat `n_ref` telt. Zetten we hier de
  # categorie-omvang neer (die is gelijk aan metric_value), dan wordt dat verderop
  # de noemer en leest elk aandeel als 100%.
  ind <- merge(ind, support_ref_sizes(ref), by = SUPPORT_SIZE_KEY, all.x = TRUE)

  # Welke van de drie afgeleide indicatoren hoort bij welke categorie.
  ind[, variable_name := fifelse(
    categorie %in% c("geen", "wel"), unname(SUPPORT_INDICATOR_SIGNAL[population]),
    fifelse(categorie %in% c("0", "1", "2", "3", SUPPORT_UNKNOWN),
            unname(SUPPORT_INDICATOR_COUNT[population]),
            unname(SUPPORT_INDICATOR_COMBO[population])))]
  # De restcategorie hoort bij twee indicatoren tegelijk: bij "aantal vormen"
  # (wat niet aan 0-3 toe te wijzen was) en bij de combinatie zelf (wat aan geen
  # enkel deelgebied toe te wijzen was). Beide keren is het hetzelfde getal.
  rest <- ind[categorie == SUPPORT_UNKNOWN]
  if (nrow(rest) > 0L) {
    rest <- copy(rest)[, variable_name := unname(SUPPORT_INDICATOR_COMBO[population])]
    ind <- rbind(ind, rest, use.names = TRUE)
  }

  ind[, `:=`(variable_value = categorie,
             metric_value   = n,
             n_split        = n_ref,
             split_var      = rest_var,
             split_level    = rest_level)]
  ind[, c(SUPPORT_IND_GROUP_COLS, "variable_name", "variable_value",
          "metric_value", "n_split", "split_var", "split_level"), with = FALSE]
}

#' De terugrekenroute, alleen voor metrics die iets anders tellen dan de
#' populatie-eenheid. Ongewijzigd ten opzichte van output_1a, op de restsleutel
#' na: hij draait alleen op de niet-samengestelde uitsplitsing.
support_indicator_reconstructed <- function(dt, combo, ref) {
  SL <- SUPPORT_IND_GROUP_COLS
  leeg <- dt[0L, c(SL, "variable_name", "variable_value", "metric_value", "n_split",
                   "split_var", "split_level"), with = FALSE]

  combo <- combo[rest_var == SUPPORT_TOTAL_LABEL & !metric_telt_populatie(metric_name)]
  totaal <- dt[split_var == SUPPORT_TOTAL_LABEL & population %in% names(SUPPORT_COMBO_VAR) &
               !metric_telt_populatie(metric_name)]
  if (nrow(combo) == 0L || nrow(totaal) == 0L) return(leeg)

  # -- bruikbare bronnen ------------------------------------------------------
  bron <- totaal[, .(bron_totaal = sum(metric_value), n_cat = uniqueN(variable_value)),
                 by = c(SL, "variable_name")]
  # Elke bron telt dezelfde populatie, dus de hoogste is de beste schatting van
  # het regiototaal: onderdrukking haalt er alleen af. Exact gelijk zijn ze
  # nooit -- afronding op tientallen zet ze een stap uit elkaar.
  bron[, regio_totaal := max(bron_totaal), by = SL]
  bron <- bron[regio_totaal - bron_totaal <= SUPPORT_ROUND_TOL]
  if (nrow(bron) == 0L) return(leeg)

  # -- niveautotalen ----------------------------------------------------------
  niv <- combo[, .(som = sum(metric_value), n_cel = uniqueN(variable_value)),
               by = c(SL, "variable_name", "combo_level")]
  niv <- merge(niv, bron[, c(SL, "variable_name", "n_cat", "regio_totaal"), with = FALSE],
               by = c(SL, "variable_name"))
  niv <- niv[n_cel == n_cat]                      # geen onderdrukte cel in deze rij
  if (nrow(niv) == 0L) return(leeg)

  lev <- niv[, .(niveau = support_round10(median(som))),
             by = c(SL, "regio_totaal", "combo_level")]
  lev[, n_vormen := support_n_forms(combo_level)]

  IK <- c(SL, "regio_totaal")

  # -- signaal: alleen de none-rij nodig --------------------------------------
  signaal <- lev[combo_level == "none", .(geen = niveau), by = IK]
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
    w[, wel := regio_totaal - k0]
    w[, `:=`(k1_complement = wel - k2 - k3, k2_complement = wel - k1 - k3)]
    w[is.na(k1), k1 := k1_complement]
    w[is.na(k2), k2 := k2_complement]
    w[, (SUPPORT_UNKNOWN) := regio_totaal -
        rowSums(.SD, na.rm = TRUE), .SDcols = c("k0", "k1", "k2", "k3")]
    w <- w[!is.na(k0) | !is.na(k1) | !is.na(k2) | !is.na(k3)]
    if (nrow(w) > 0L) {
      aantal <- melt(w, id.vars = IK,
                     measure.vars = c("k0", "k1", "k2", "k3", SUPPORT_UNKNOWN),
                     variable.name = "variable_value", value.name = "metric_value",
                     variable.factor = FALSE, na.rm = TRUE)
      aantal[, variable_value := sub("^k", "", variable_value)]
      aantal[, variable_name := unname(SUPPORT_INDICATOR_COUNT[population])]
    }
  }

  # -- de combinatie zelf als indicator ---------------------------------------
  combinatie <- lev[, .(variable_value = combo_level, metric_value = niveau), by = IK]
  rest <- combinatie[, .(metric_value = regio_totaal[1] - sum(metric_value)), by = IK]
  rest[, variable_value := SUPPORT_UNKNOWN]
  combinatie <- rbind(combinatie, rest, use.names = TRUE)
  combinatie[, variable_name := unname(SUPPORT_INDICATOR_COMBO[population])]

  ind <- rbind(signaal, aantal, combinatie, use.names = TRUE, fill = TRUE)
  if (nrow(ind) == 0L) return(leeg)
  # Deze route kent de groepsgrootte niet in de eenheid van deze metric; de
  # noemer komt dan uit de categoriesom, zoals voor elke andere kindermetric.
  ind[, `:=`(split_var = SUPPORT_TOTAL_LABEL, split_level = SUPPORT_TOTAL_LABEL,
             n_split = NA_real_, regio_totaal = NULL)]
  ind[, c(SL, "variable_name", "variable_value", "metric_value", "n_split",
          "split_var", "split_level"), with = FALSE]
}

#' Leidt per (populatie, regioniveau) af in plaats van over de hele tabel ineens.
#'
#' Elke groepssleutel in dit bestand draagt `population` en `region_level`
#' (SUPPORT_GROUP_COLS, SUPPORT_SIZE_KEY, SUPPORT_IND_GROUP_COLS), en een
#' afgeleide rij put alleen uit rijen van diezelfde regio. Per stuk afleiden
#' geeft dus exact hetzelfde resultaat -- maar de piek in geheugen is die van
#' het grootste regioniveau in plaats van die van de hele levering.
#'
#' Dat is geen optimalisatie achteraf: `output_1b` is met ruim 11 miljoen rijen
#' een veelvoud van `output_1a`, en ongesplitst liep de groepering van
#' data.table hier vast op een hashtabel die niet meer paste (16 GB werkgeheugen,
#' regioniveau `gebied` van OT_HHKIND alleen al 4,1 miljoen rijen).
#'
#' @param dt data.table in het lange schema.
#' @param fn De afleiding, een functie van een data.table naar een data.table.
support_per_regioniveau <- function(dt, fn) {
  stukken <- unique(dt[, .(population, region_level)])
  if (nrow(stukken) == 0L) return(fn(dt))
  uit <- vector("list", nrow(stukken))
  for (i in seq_len(nrow(stukken))) {
    deel <- dt[population == stukken$population[i] & region_level == stukken$region_level[i]]
    # Per stuk melden wat eraan komt en wat het opleverde. Deze stap duurt op de
    # hele levering tientallen minuten; zonder deze regels is er geen enkel
    # verschil te zien tussen "nog bezig" en "vastgelopen".
    t0 <- Sys.time()
    message(sprintf("  [%d/%d] %s, %s: %s rijen ...", i, nrow(stukken),
                    stukken$population[i], stukken$region_level[i],
                    format(nrow(deel), big.mark = ".", decimal.mark = ",")))
    uit[[i]] <- fn(deel)
    message(sprintf("        -> %s afgeleide rijen in %.0f s",
                    format(nrow(uit[[i]]), big.mark = ".", decimal.mark = ","),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    rm(deel)
    invisible(gc(verbose = FALSE))
  }
  rbindlist(uit, use.names = TRUE)
}

#' Voegt beide afgeleide vormen toe aan de lange tabel.
#'
#' Draait voor de noemerberekening in 01_build_app_data.R: `denominator` wordt
#' daarna over alles ineens berekend, dus ook over de rijen die hier bij komen.
#' Idempotent -- eerder afgeleide rijen gaan er eerst uit, zodat 02_ opnieuw
#' gedraaid kan worden.
#'
#' Publiceert de levering een van deze uitsplitsingen zelf, dan blijft die van
#' de levering staan en wordt er niets afgeleid: het echte cijfer gaat voor een
#' afgeleid cijfer.
add_support_derivations <- function(dt) {
  stopifnot(is.data.table(dt))
  if (!"n_split" %in% names(dt)) {
    stop("Kolom n_split ontbreekt. Die komt uit n_totaal_region_splitvar in levering ",
         "output_1b; bouw de parquet opnieuw met data-prep/01_build_app_data.R.")
  }

  afgeleide_splits <- c(SUPPORT_SPLIT_SIGNAL, SUPPORT_SPLIT_COUNT)

  # `afgeleid` scheidt wat dit bestand heeft gemaakt van wat de levering zelf
  # publiceert. Zonder die markering zijn ze niet uit elkaar te houden: een
  # tweede run zou de rijen van de levering opruimen, of ze juist aanzien voor
  # een reden om niets af te leiden. De kolom rijdt mee de parquet in.
  if (!"afgeleid" %in% names(dt)) dt[, afgeleid := FALSE]
  dt[is.na(afgeleid), afgeleid := FALSE]

  # Eerder afgeleide rijen eruit, zodat 02_ opnieuw gedraaid kan worden.
  dt <- dt[!(afgeleid)]

  # Levert de levering zelf al zo'n uitsplitsing, dan niets afleiden: een echt
  # cijfer gaat voor een afgeleid cijfer, en allebei zou dubbeltellen.
  aanwezig <- intersect(afgeleide_splits, split_vars_available(dt$split_var))
  if (length(aanwezig)) {
    message("Levering bevat zelf al: ", paste(aanwezig, collapse = ", "),
            " -- geen afleiding voor deze uitsplitsing(en).")
    return(dt[])
  }

  split_rows <- support_per_regioniveau(dt, derive_support_split_rows)
  ind_rows   <- support_per_regioniveau(dt, derive_support_indicator_rows)

  out <- rbind(dt, split_rows, ind_rows, use.names = TRUE, fill = TRUE)
  out[is.na(afgeleid), afgeleid := TRUE]
  setcolorder(out, names(dt))
  out[]
}
