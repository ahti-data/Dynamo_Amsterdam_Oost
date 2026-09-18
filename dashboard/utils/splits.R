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
