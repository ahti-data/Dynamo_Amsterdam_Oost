#' Samengestelde uitsplitsingen: een rij kan naar meer dan een variabele
#' tegelijk uitgesplitst zijn.
#'
#' Levering `output_1a` kruiste nooit twee splitsvariabelen; elke rij was of een
#' totaalrij of een marginaal van een enkele variabele. Vanaf `output_1b` mag
#' dat wel, en daarmee is `split_var` geen enkele naam meer maar een *verzameling*
#' namen -- en `split_level` de bijbehorende verzameling waarden.
#'
#' Die verzameling wordt als tekst opgeslagen: de namen alfabetisch gesorteerd
#' en aan elkaar geplakt met `SPLIT_SEP`, en de waarden in precies diezelfde
#' volgorde. Zo blijft het lange schema uit PLAN.md 2 intact -- een rij houdt
#' een `split_var` en een `split_level` -- en blijft elke bestaande filter
#' (`split_var == "O_MPG_combination"`) doen wat hij deed: die selecteert nog
#' steeds alleen de rijen die *alleen* naar de combinatie zijn uitgesplitst.
#' Een enkelvoudige splitsing is gewoon een samenstelling van lengte een, dus
#' data van voor `output_1b` leest ongewijzigd mee.
#'
#' De sortering is wat de sleutel eenduidig maakt: "geslacht + herkomst7" en
#' "herkomst7 + geslacht" zijn dezelfde uitsplitsing en moeten dezelfde rijen
#' opleveren, hoe de gebruiker ze ook aanklikt.

# Het scheidingsteken. Met spaties eromheen, zodat het in een keuzelijst leest
# als een opsomming en niet als een woord. Geen "+": de combinatieniveaus van
# de ondersteuning dragen die zelf al ("O_MPG1 + O_MPG2").
SPLIT_SEP <- " | "

# Label van een rij die helemaal niet uitgesplitst is. Zelfde waarde als
# TOTAL_LABEL in app.R en SUPPORT_TOTAL_LABEL in de prep-stap; hier apart
# gedefinieerd omdat dit bestand los van allebei gesourced wordt.
SPLIT_TOTAL_LABEL <- "(totaal)"

#' De onderdelen van een samengestelde sleutel.
#'
#' @param key Een `split_var`- of `split_level`-waarde (lengte 1).
#' @return Character vector met de losse onderdelen. `(totaal)` en `NA` geven
#'   een lege vector -- een totaalrij is naar niets uitgesplitst.
split_parts <- function(key) {
  if (length(key) == 0L || is.na(key) || identical(key, SPLIT_TOTAL_LABEL)) return(character(0))
  strsplit(key, SPLIT_SEP, fixed = TRUE)[[1]]
}

#' Idem, maar gevectoriseerd: een lijst met per element zijn onderdelen.
split_parts_list <- function(keys) lapply(keys, split_parts)

#' Bouwt de sleutel van een verzameling splitsvariabelen.
#'
#' Sorteert zelf, zodat de aanroeper zich niet om de volgorde hoeft te
#' bekommeren -- een keuzelijst levert ze aan in aanklikvolgorde.
#'
#' `method = "radix"` is hier niet optioneel. De gewone `sort()` volgt de
#' collatie van de locale, en die is op de Shiny-server niet dezelfde als op de
#' machine waar de prep-stap draait: onder `C` komt `O_MPG_combination` voor
#' `geslacht`, onder `nl_NL.UTF-8` juist andersom. De sleutel die de app bouwt
#' zou dan niet meer die in de parquet zijn, en de selectie zou zonder enige
#' melding leeg blijven. Radix sorteert altijd op bytes, waar de app ook draait.
#'
#' @param vars Character vector met variabelenamen (mag leeg zijn).
#' @return De sleutel, of `(totaal)` als er niets uit te splitsen valt.
split_key <- function(vars) {
  vars <- vars[!is.na(vars) & nzchar(vars) & vars != SPLIT_TOTAL_LABEL]
  if (length(vars) == 0L) return(SPLIT_TOTAL_LABEL)
  paste(sort(unique(vars), method = "radix"), collapse = SPLIT_SEP)
}

#' Alle losse splitsvariabelen die in een reeks sleutels voorkomen.
#'
#' Wat de keuzelijst "splits uit naar" aanbiedt: de variabelen zelf, niet de
#' samenstellingen. Welke *combinaties* daarvan bestaan blijft een vraag aan de
#' data -- zie split_key_bestaat().
split_vars_available <- function(keys) {
  sort(unique(unlist(split_parts_list(unique(keys)))), method = "radix")
}

#' Bestaat deze samenstelling in de data?
#'
#' De levering publiceert niet elke denkbare kruising, en een selectie die geen
#' rijen heeft moet als zodanig herkenbaar zijn -- niet als een lege grafiek die
#' op een bug lijkt.
split_key_bestaat <- function(key, keys) !is.na(key) && key %in% keys

#' Onderdeelsgewijze opmaak van een samengestelde sleutel.
#'
#' Elk onderdeel gaat door `labeller` heen (voor `split_var` de naam van de
#' variabele, voor `split_level` de waarde) en de onderdelen worden weer aan
#' elkaar geplakt. Bij `split_level` hoort de gebruikte labeller per onderdeel
#' te verschillen -- "vrouw" en "O_MPG1 + O_MPG2" staan naast elkaar in dezelfde
#' sleutel -- vandaar dat `labeller` de index van het onderdeel meekrijgt.
#'
#' @param keys Character vector met sleutels.
#' @param labeller function(waarden, i) -> labels, met `i` de positie van het
#'   onderdeel binnen de sleutel.
#' @param sep Scheidingsteken in de *uitvoer*. Een middenpunt leest als een
#'   opsomming en botst niet met de " | " van de opslag.
#' @return Character vector van dezelfde lengte als `keys`.
split_pretty <- function(keys, labeller, sep = " \u00b7 ") {
  vapply(keys, function(k) {
    p <- split_parts(k)
    if (length(p) == 0L) return(SPLIT_TOTAL_LABEL)
    paste(vapply(seq_along(p), function(i) as.character(labeller(p[[i]], i))[1],
                 character(1)), collapse = sep)
  }, character(1), USE.NAMES = FALSE)
}

#' Controleert dat geen naam of waarde het scheidingsteken bevat.
#'
#' De hele codering staat of valt hiermee: een waarde met een " | " erin zou bij
#' het uitpakken in twee onderdelen uiteenvallen en stil de verkeerde rijen
#' selecteren. Liever hier hard stoppen in de prep-stap dan dat later in het
#' dashboard terugzien.
split_check_sep <- function(x, wat = "waarde") {
  fout <- unique(x[!is.na(x) & grepl(SPLIT_SEP, x, fixed = TRUE)])
  if (length(fout)) {
    stop(sprintf("%s bevat het scheidingsteken \"%s\": %s. Kies een ander SPLIT_SEP.",
                 wat, SPLIT_SEP, paste(utils::head(fout, 5), collapse = ", ")))
  }
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Een keuzelijst per splitsvariabele
# ---------------------------------------------------------------------------
#
# De app bood eerst een enkele meervoudige keuzelijst "splits uit naar" met de
# variabelen erin, en daarnaast een tweede lijst met de niveaus van de gekozen
# verzameling. Daarmee was "naar deze variabele niet uitsplitsen" alleen te
# bereiken door de variabele uit de eerste lijst weg te klikken -- terwijl de
# levering daar gewoon een waarde voor heeft. Sinds deze versie krijgt elke
# variabele een eigen lijst met haar eigen niveaus, en staat dat "alle"
# gewoon als keuze bovenaan.
#
# Drie schildwachtwaarden staan naast de echte niveaus: twee keuzes die geen
# niveau zijn, en een lege selectie. Ze mogen nooit samenvallen met een echte
# waarde uit de levering; split_check_keuzes() hieronder bewaakt dat bij het
# opstarten.
SPLIT_ALLE <- "__alle__"   # niet naar deze variabele uitsplitsen
SPLIT_ELK  <- "__elk__"    # wel uitsplitsen, en elk niveau apart tonen

# Staat in een filter waar de selectie leeg is: een niveau dat gegarandeerd
# niet bestaat, zodat "niets gekozen" ook echt nul rijen oplevert.
SPLIT_GEEN <- "__geen__"

#' Welke niveaus een enkele splitsvariabele heeft.
#'
#' Kijkt door de samengestelde sleutels heen: staat `var` op positie i van een
#' sleutel, dan hoort daar het i-de onderdeel van het bijbehorende niveau bij.
#' Zo levert ook een variabele die alleen gekruist gepubliceerd is haar eigen
#' niveaus op.
#'
#' @param var Naam van de splitsvariabele.
#' @param keys,levels Even lange vectors met `split_var`/`split_level`-paren.
#' @return De niveaus, radix-gesorteerd (zie split_key() voor het waarom).
split_levels_available <- function(var, keys, levels) {
  uit <- character(0)
  for (i in seq_along(keys)) {
    p <- split_parts(keys[[i]])
    j <- match(var, p)
    if (is.na(j)) next
    d <- split_parts(levels[[i]])
    if (length(d) >= j) uit <- c(uit, d[[j]])
  }
  sort(unique(uit), method = "radix")
}

#' De gepubliceerde niveaus van een sleutel die binnen de keuze per variabele
#' vallen.
#'
#' Bewust niet het product van de losse keuzes: de levering publiceert lang niet
#' elke kruising, en een niet-bestaande combinatie in de filter zou een lege
#' grafiek geven waar "deze kruising bestaat niet" bedoeld is. Daarom worden de
#' *gepubliceerde* niveaus van deze sleutel gefilterd.
#'
#' @param key De sleutel (uit split_key()).
#' @param levels De gepubliceerde `split_level`-waarden bij die sleutel.
#' @param keuze Named list: per variabelenaam de gekozen niveaus, of `NULL`
#'   voor "elk niveau" (een variabele die niet in de lijst staat telt ook als
#'   elk niveau).
#' @return De passende niveaus, radix-gesorteerd. Bij een lege sleutel de
#'   totaalwaarde zelf.
split_levels_matching <- function(key, levels, keuze = list()) {
  vars <- split_parts(key)
  if (length(vars) == 0L) return(SPLIT_TOTAL_LABEL)
  lv <- unique(levels[!is.na(levels)])
  if (length(lv) == 0L) return(character(0))
  houd <- vapply(lv, function(l) {
    d <- split_parts(l)
    if (length(d) != length(vars)) return(FALSE)
    all(vapply(seq_along(vars), function(i) {
      sel <- keuze[[vars[[i]]]]
      is.null(sel) || d[[i]] %in% sel
    }, logical(1)))
  }, logical(1), USE.NAMES = FALSE)
  sort(lv[houd], method = "radix")
}

#' Knipt sleutel en niveaus terug tot alleen de opgegeven variabelen.
#'
#' Waar een variabele op een vaste waarde staat, hoeft die waarde niet in elk
#' reekslabel terug te komen -- hij geldt voor de hele figuur en staat in de
#' titel. De onderdelen blijven in hun oorspronkelijke (gesorteerde) volgorde
#' staan, dus het resultaat is weer een geldige sleutel met geldige niveaus en
#' kan zo door de bestaande opmaakfuncties heen.
#'
#' @param key De volledige sleutel.
#' @param levels De volledige niveaus.
#' @param vars De variabelen die overblijven.
#' @return list(key=, levels=). Blijft er niets over, dan de totaalwaarde --
#'   dan is er immers een reeks, niet een reeks per niveau.
split_subset <- function(key, levels, vars) {
  delen <- split_parts(key)
  idx <- which(delen %in% vars)
  if (length(idx) == 0L) {
    return(list(key = SPLIT_TOTAL_LABEL,
                levels = rep(SPLIT_TOTAL_LABEL, length(levels))))
  }
  list(
    key = paste(delen[idx], collapse = SPLIT_SEP),
    levels = vapply(levels, function(l) {
      d <- split_parts(l)
      if (length(d) < max(idx)) return(NA_character_)
      paste(d[idx], collapse = SPLIT_SEP)
    }, character(1), USE.NAMES = FALSE))
}

#' Controleert dat de schildwachtwaarden geen echte niveaus zijn.
#'
#' Zou een levering ooit een `split_level` met de waarde `__alle__` dragen, dan
#' zou "alle" als gewone waarde gelezen worden en zou het dashboard stil de
#' verkeerde rijen tonen. Liever bij het opstarten hard stoppen.
split_check_keuzes <- function(levels) {
  fout <- intersect(unique(levels), c(SPLIT_ALLE, SPLIT_ELK, SPLIT_GEEN))
  if (length(fout)) {
    stop(sprintf("split_level bevat een schildwachtwaarde (%s). Kies een andere SPLIT_ALLE/SPLIT_ELK.",
                 paste(fout, collapse = ", ")))
  }
  invisible(TRUE)
}
