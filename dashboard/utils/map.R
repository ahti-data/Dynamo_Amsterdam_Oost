#' Alles wat de kaart deelt tussen het scherm en de download: welke rijen er
#' opgeteld worden, over welk bereik de kleurschaal loopt, en hoe dezelfde laag
#' als statische figuur getekend wordt.
#'
#' Dynamo-specifiek, net als venn_diagram.R -- niet gedeeld met de andere
#' dashboards uit shiny_dashboard_template.

# Zelfde grijs als de leaflet-kaart en de venn voor een onderdrukte regio.
MAP_NA_FILL <- "#e0e0e0"

#' Vat een kaartselectie samen tot een rij per regio.
#'
#' De kaart kan meerdere combinatieniveaus en/of meerdere indicatorwaarden
#' tegelijk tonen -- "hoeveel gezinnen zitten in O1, O2 of O1+O2 samen" -- en
#' telt die op. De teller is simpel: de som. De noemer niet, en daar zit de
#' valkuil:
#'
#' - Over `variable_value` heen is de noemer voor elke rij **dezelfde**: hij is
#'   per definitie de som over alle categorieen binnen die slice. Optellen zou
#'   hem dubbel tellen en het percentage halveren.
#' - Over `split_level` heen heeft elk niveau juist zijn **eigen** noemer, en
#'   die moeten wel bij elkaar.
#'
#' Vandaar: de noemer is de som over de *unieke* splitsniveaus. In beide
#' gevallen komt daar hetzelfde uit als je met de hand zou rekenen.
#'
#' Onderdrukking: ontbreekt een van de gevraagde cellen voor een regio, dan
#' telt de som alleen op wat er wél is. Dat getal is dan een **ondergrens**, en
#' de regio wordt als zodanig gemarkeerd (`compleet = FALSE`) zodat de kaart,
#' de tooltip en de export het kunnen zeggen. Dat is een bewuste afwijking van
#' de regel elders in dit dashboard, waar een onvolledige optelling helemaal
#' vervalt: bij een handmatig samengestelde groep is een ondergrens mét
#' waarschuwing bruikbaarder dan een grijs vlak, zolang de lezer weet dat het er
#' een is. Wie hem weer wil dichtzetten, filtert op `compleet`.
#'
#' Let op het verschil met de afgeleide indicatoren in
#' `data-prep/derive_support_splits.R`: daar blijft alles-of-niets gelden, want
#' daar bepaalt de optelling de *noemer* van een percentage, en een halve
#' partitie zou dat percentage te hoog maken. Hier is de noemer meegeteld met de
#' teller, dus een ontbrekende cel maakt beide te laag en verschuift de
#' verhouding veel minder.
#'
#' @param d data.table met de opgehaalde slice (een rij per regio x
#'   splitsniveau x indicatorwaarde).
#' @param n_cellen Hoeveel rijen een regio moet hebben om compleet te zijn:
#'   het aantal gekozen splitsniveaus maal het aantal gekozen waarden.
#' @return data.table met een rij per regio, plus `compleet` (waren alle
#'   gevraagde cellen gepubliceerd) en `n_gevonden`. `variable_value`/
#'   `split_level` dragen de gekozen verzameling als tekst, zodat de export zelf
#'   vertelt wat er opgeteld is.
map_aggregate <- function(d, n_cellen) {
  stopifnot(is.data.table(d))
  if (nrow(d) == 0L) return(d)

  # Komma's, geen plussen: de combinatieniveaus dragen zelf al een " + "
  # ("O_MPG1 + O_MPG2"), dus daarmee samenvoegen levert onleesbare tekst op.
  samen <- function(x) paste(sort(unique(x)), collapse = ", ")

  uit <- d[, .(variable_name  = variable_name[1],
               variable_value = samen(variable_value),
               split_var      = split_var[1],
               split_level    = samen(split_level),
               metric_value   = sum(metric_value),
               n_totaal       = n_totaal[1],
               denominator    = sum(denominator[!duplicated(split_level)]),
               n_gevonden     = .N),
           by = .(population, region_level, region_code, region_name, stadsdeel,
                  year, metric_name)]
  uit[, compleet := n_gevonden == n_cellen]
  uit[]
}

#' Welke noemer hoort bij een gekozen weergave.
#'
#' Een aandeel kan tegen twee dingen afgezet worden, en dat verschil is precies
#' waar een kaart verkeerd gelezen wordt:
#'
#' - **binnen de groep** (`"rel_groep"`, en `"rel"` als oude naam): de som over
#'   de categorieen van de indicator binnen dezelfde selectie. Leest als "van de
#'   gezinnen met dit ondersteuningsbeeld heeft x% deze risicoscore". Dit is de
#'   afspraak uit PLAN.md 6 en de enige noemer die het dashboard eerst kende.
#' - **van het regiototaal** (`"rel_regio"`): de hele buurt/wijk/gebied of het
#'   hele stadsdeel. Leest als "x% van alle gezinnen in deze wijk". Dat is
#'   bewust *niet* `n_totaal`: die telt huishoudens, terwijl de teller bij de
#'   `n_kinderen_*`-metrics kinderen telt, en dan is de uitkomst geen
#'   percentage. Het regiototaal komt daarom uit de noemer van de totaalrijen,
#'   die per metric klopt.
#'
#' Alles wat geen aandeel is (`"abs"`) krijgt NULL: dan is er geen noemer.
#'
#' @param weergave "abs", "rel_groep"/"rel", of "rel_regio".
#' @param binnen_groep,regio_totaal Numerieke vectoren van gelijke lengte.
#' @return De te gebruiken noemer, of NULL bij een absolute weergave.
map_noemer <- function(weergave, binnen_groep, regio_totaal = NULL) {
  switch(weergave,
         rel_groep = binnen_groep,
         rel       = binnen_groep,
         rel_regio = regio_totaal,
         NULL)
}

#' Is deze weergave een aandeel? Bepaalt de opmaak (procentteken) op elke plek
#' waar een getal getoond wordt.
map_is_aandeel <- function(weergave) !identical(weergave, "abs")

#' Het bereik waarover de kleurschaal loopt.
#'
#' Standaard de uiterste waarden van de selectie zelf. Een handmatig bereik
#' gaat voor -- dat is wat twee kaarten naast elkaar vergelijkbaar maakt -- maar
#' alleen als het een geldig bereik is; een half ingevuld of omgedraaid veld valt
#' terug op de data in plaats van de kaart leeg te laten.
#'
#' @param waarde Numerieke vector (NA's mogen).
#' @param handmatig Lengte-2 vector, of NULL.
#' @return Lengte-2 vector, of NULL als er niets te schalen valt.
map_domein <- function(waarde, handmatig = NULL) {
  ok <- waarde[is.finite(waarde)]
  if (length(ok) == 0L) return(NULL)

  if (!is.null(handmatig) && length(handmatig) == 2L &&
      all(is.finite(handmatig)) && handmatig[1] < handmatig[2]) {
    return(as.numeric(handmatig))
  }

  d <- range(ok)
  # Een selectie waarin elke regio dezelfde waarde heeft levert een bereik van
  # nul breed op; dan is er geen schaal te tekenen. Een marge eromheen houdt de
  # kaart leesbaar in plaats van leeg.
  if (d[1] == d[2]) d <- d + c(-0.5, 0.5)
  d
}

#' Waarden binnen het bereik duwen, zodat een regio boven het gekozen maximum
#' de topkleur krijgt in plaats van uit de schaal te vallen (colorNumeric()
#' geeft daar anders de NA-kleur, wat als "onvoldoende waarnemingen" leest).
map_klem <- function(waarde, domein) {
  if (is.null(domein)) return(waarde)
  pmin(pmax(waarde, domein[1]), domein[2])
}

#' De choropleth als statische figuur, voor de download.
#'
#' Leaflet tekent in de browser en laat zich niet zomaar als plaatje
#' wegschrijven (daar is een headless browser voor nodig, die op de server niet
#' staat). Deze functie tekent dezelfde laag opnieuw met ggplot2 + geom_sf --
#' allebei al dependencies van de app -- zodat er een echt bestand uitkomt dat
#' in een rapport of slide past.
#'
#' Het kleurbereik komt van de aanroeper en is hetzelfde als dat van de kaart op
#' het scherm (`kaart_domein()` in app.R). Anders zou de figuur zijn eigen
#' schaal kiezen en niet meer op het scherm lijken.
#'
#' Onderdrukte regio's krijgen hetzelfde neutrale grijs als op de kaart en
#' staan met zoveel woorden in het onderschrift -- "onvoldoende waarnemingen",
#' nooit een nul aan de onderkant van de schaal.
#'
#' Regio's waar een van de gevraagde groepen onderdrukt was (`compleet =
#' FALSE`) krijgen een gestippelde donkere rand: hun getal is een ondergrens, en
#' zonder dat merkteken zou de figuur dat verschil niet dragen -- de tooltip van
#' de kaart bestaat hier immers niet.
#'
#' @param laag sf-object met ten minste `waarde` en `region_name`.
#' @param domein Lengte-2 kleurbereik, of NULL als er niets te schalen valt.
#' @param weergave "rel" of "abs" -- bepaalt de opmaak van de legendalabels.
#' @param titel,ondertitel,bron Tekst boven en onder de figuur.
#' @return Een ggplot-object.
choropleth_ggplot <- function(laag, domein, weergave = "rel",
                              titel = NULL, ondertitel = NULL, bron = NULL) {
  stopifnot(inherits(laag, "sf"), "waarde" %in% names(laag))

  fmt <- function(v) {
    if (weergave == "rel") sprintf("%g%%", v)
    else format(round(v), big.mark = ".", decimal.mark = ",", trim = TRUE, scientific = FALSE)
  }

  # Dezelfde ramp als leaflet, uit leaflet's eigen colorNumeric(): zo is het
  # aantoonbaar dezelfde YlOrRd als op het scherm, zonder een tweede
  # palettepakket erbij te halen.
  ramp <- colorNumeric("YlOrRd", domain = c(0, 1))
  kleuren <- ramp(seq(0, 1, length.out = 9))

  schaal <- if (is.null(domein)) {
    ggplot2::scale_fill_gradientn(colours = kleuren, na.value = MAP_NA_FILL,
                                  guide = "none")
  } else {
    ggplot2::scale_fill_gradientn(
      colours = kleuren, limits = domein, na.value = MAP_NA_FILL,
      # squish: een regio buiten het gekozen bereik krijgt de rand van de
      # schaal, niet de NA-kleur -- anders leest een te hoge waarde als
      # "onvoldoende waarnemingen".
      oob = scales::squish,
      labels = function(x) vapply(x, fmt, character(1)),
      name = if (weergave == "rel") "Aandeel (%)" else "Aantal",
      guide = ggplot2::guide_colourbar(barheight = grid::unit(38, "mm"),
                                       barwidth = grid::unit(4, "mm"),
                                       frame.colour = "#b9b9b9",
                                       ticks.colour = "#b9b9b9"))
  }

  # `compleet` ontbreekt bij een enkelvoudige keuze -- daar is elke regio per
  # definitie compleet -- en is NA voor een regio zonder cijfer, die toch al
  # grijs is. Allebei een gewone rand.
  if (is.null(laag$compleet)) laag$compleet <- TRUE
  laag$compleet[is.na(laag$compleet)] <- TRUE
  onvolledig <- sum(!laag$compleet)

  onderschrift <- c(
    bron,
    "Grijs = onvoldoende waarnemingen (CBS-onderdrukking), niet nul.",
    if (onvolledig > 0) sprintf(
      paste("Gestippelde rand (%d regio's): een van de opgetelde groepen is daar onderdrukt,",
            "dus het getal is een ondergrens."), onvolledig))

  ggplot2::ggplot(laag) +
    ggplot2::geom_sf(ggplot2::aes(fill = waarde, colour = compleet, linetype = compleet),
                     linewidth = 0.25) +
    ggplot2::scale_colour_manual(values = c(`TRUE` = "#ffffff", `FALSE` = "#3b3b3b"),
                                 guide = "none") +
    ggplot2::scale_linetype_manual(values = c(`TRUE` = "solid", `FALSE` = "dotted"),
                                   guide = "none") +
    schaal +
    ggplot2::labs(title = titel, subtitle = ondertitel,
                  caption = paste(onderschrift, collapse = "\n")) +
    ggplot2::coord_sf(datum = NA) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(
      plot.title    = ggplot2::element_text(face = "bold", size = 12, hjust = 0),
      plot.subtitle = ggplot2::element_text(size = 9.5, colour = "#524F50", hjust = 0),
      plot.caption  = ggplot2::element_text(size = 7.5, colour = "#7a7a7a", hjust = 0),
      legend.title  = ggplot2::element_text(size = 9),
      legend.text   = ggplot2::element_text(size = 8),
      plot.margin   = ggplot2::margin(10, 10, 8, 10))
}
