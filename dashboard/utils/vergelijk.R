#' Alles wat het tabblad "Regio's vergelijken" deelt tussen het scherm en de
#' download: welke regio's er te kiezen zijn, welke er bij het openen
#' aangevinkt staan, in welke volgorde de lijnen in de legenda komen en welke
#' kleuren ze krijgen.
#'
#' Dynamo-specifiek, net als map.R en venn_diagram.R -- niet gedeeld met de
#' andere dashboards uit shiny_dashboard_template.
#'
#' De optelling van meerdere splitsniveaus doet dit tabblad *niet* zelf: dat is
#' precies wat map_aggregate() in utils/map.R al doet (en waar de noemerregel
#' in staat die hier net zo goed geldt -- optellen over de unieke splitsniveaus,
#' niet over de indicatorwaarden). Een tweede implementatie zou daar vroeg of
#' laat van afdrijven.

# Hoeveel regio's er bij het wisselen van regioniveau of stadsdeel vanzelf
# aangevinkt worden. Vijftien is de vraag waar dit tabblad voor gemaakt is --
# alle wijken van Oost in een keer -- en tegelijk ongeveer waar een lijnfiguur
# ophoudt leesbaar te zijn. Daarboven staat de rest klaar in de keuzelijst en
# onder de knop "Alle regio's"; het is een startpunt, geen grens.
VERGELIJK_MAX_AUTO <- 15L

#' De regio's van een niveau, eventueel ingeperkt tot een stadsdeel.
#'
#' Zelfde inperking als "Toon" op de Kaart, met dezelfde uitzondering: een
#' niveau dat in geen enkel stadsdeel ligt (gemeente is een vlak over de hele
#' stad) wordt niet gefilterd, want dan zou de keuzelijst leeg blijven in plaats
#' van korter worden.
#'
#' @param meta data.frame/data.table met `region_code`, `region_name` en
#'   `stadsdeel`, al op naam gesorteerd.
#' @param scope Een stadsdeelcode, of `alles`.
#' @param alles De waarde die "niet inperken" betekent.
#' @return Named character vector: namen als label, codes als waarde -- de vorm
#'   die selectInput/selectizeInput verwacht.
vergelijk_regio_keuzes <- function(meta, scope, alles = "Heel Amsterdam") {
  if (is.null(meta) || nrow(meta) == 0L) return(character(0))
  houd <- rep(TRUE, nrow(meta))
  if (!is.null(scope) && !identical(scope, alles) && any(!is.na(meta$stadsdeel))) {
    houd <- !is.na(meta$stadsdeel) & meta$stadsdeel == scope
  }
  stats::setNames(as.character(meta$region_code[houd]),
                  as.character(meta$region_name[houd]))
}

#' Wat er aangevinkt staat zodra het niveau of het stadsdeel wisselt.
#'
#' Bewust de hele selectie opnieuw zetten in plaats van de oude keuzes te
#' bewaren: "regioniveau wijk, stadsdeel Oost" leest als "geef me de wijken van
#' Oost", en een half overgebleven selectie van het vorige niveau zou dat in de
#' weg zitten.
#'
#' @param keuzes De keuzelijst uit vergelijk_regio_keuzes().
#' @param max_auto Hoeveel er hoogstens vanzelf aangevinkt worden.
#' @return De aan te vinken codes.
vergelijk_start_selectie <- function(keuzes, max_auto = VERGELIJK_MAX_AUTO) {
  if (length(keuzes) == 0L) return(character(0))
  unname(utils::head(keuzes, max_auto))
}

#' De volgorde van de lijnen in de legenda.
#'
#' Alfabetisch zegt niets; de lezer kijkt naar de rechterkant van de figuur en
#' leest van boven naar beneden. Daarom: de waarde in het laatste jaar waarin
#' uberhaupt iets gepubliceerd is, van hoog naar laag. Regio's die daar niets
#' hebben (onderdrukt, of niet geleverd) staan achteraan op naam, want ze hebben
#' geen plek op die as.
#'
#' Die volgorde is tegelijk de factorvolgorde van de reeks, en dus wat
#' format_tc_data() in de export aanhoudt -- zo staat een spreadsheet in
#' dezelfde volgorde als de figuur (zie de thinkcell-export skill).
#'
#' @param naam,jaar,waarde Even lange vectors, een element per regio x jaar.
#' @return De regionamen, in tekenvolgorde.
vergelijk_reeks_volgorde <- function(naam, jaar, waarde) {
  naam <- as.character(naam)
  if (length(naam) == 0L) return(character(0))
  namen <- sort(unique(naam))
  bruikbaar <- is.finite(waarde)
  if (!any(bruikbaar)) return(namen)

  laatste <- max(jaar[bruikbaar])
  # match() pakt de eerste rij per regio in dat jaar; er is er per regio x jaar
  # ook maar een, want map_aggregate() heeft ze al samengevat.
  idx <- match(namen, naam[jaar == laatste])
  v <- as.numeric(waarde[jaar == laatste][idx])
  namen[order(is.na(v), -v, namen)]
}

#' De kleuren van de lijnen.
#'
#' Tot en met vijf reeksen de huisstijlkleuren van ahti. Daarboven houdt die
#' schaal op -- hij heeft er vijf -- en zou herhalen betekenen dat twee wijken
#' dezelfde kleur krijgen, wat op een figuur met vijftien lijnen precies de
#' vergissing is die je niet wilt. Dan valt hij terug op een kwalitatieve schaal
#' uit base R (grDevices::hcl.colors), die voor elk aantal reeksen kleuren van
#' gelijke helderheid geeft.
#'
#' @param n Aantal reeksen.
#' @param merk De huisstijlschaal (ahti_branding$scale_discrete).
#' @return Character vector met n kleuren.
vergelijk_palet <- function(n, merk = character(0)) {
  n <- as.integer(n)
  if (is.na(n) || n <= 0L) return(character(0))
  if (n <= length(merk)) return(as.character(merk[seq_len(n)]))
  grDevices::hcl.colors(n, "Dark 3")
}
