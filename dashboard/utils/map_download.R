#' De choropleth als statische figuur, voor de download.
#'
#' Leaflet tekent in de browser en laat zich niet zomaar als plaatje
#' wegschrijven (daar is een headless browser voor nodig, die op de server niet
#' staat). Deze functie tekent dezelfde laag opnieuw met ggplot2 + geom_sf --
#' allebei al dependencies van de app -- zodat er een echt bestand uitkomt dat
#' in een rapport of slide past.
#'
#' De klassegrenzen komen van de aanroeper en zijn dezelfde als die van de
#' kaart op het scherm (`kaart_bins()` in app.R). Dat is de hele reden dat ze
#' daar apart berekend worden en niet aan colorBin() worden overgelaten: anders
#' zou de gedownloade figuur zijn eigen indeling kiezen en niet meer op het
#' scherm lijken.
#'
#' Onderdrukte regio's krijgen hetzelfde neutrale grijs als op de kaart en
#' staan met zoveel woorden in de legenda -- "onvoldoende waarnemingen", nooit
#' een nul aan de onderkant van de schaal.

# Zelfde grijs als de leaflet-kaart en de venn voor een onderdrukte regio.
MAP_NA_FILL <- "#e0e0e0"

#' Het vakje in de legenda: alleen de vulling, plus een dun kadertje.
#'
#' geom_sf tekent zijn legendavakjes standaard met draw_key_polygon(), en die
#' leidt de afmeting van het vakje af uit `linewidth`/`size` van de rij. Voor
#' een klasse waar geen enkele regio in valt is die rij er niet, en dan komt er
#' helemaal geen vakje uit -- de legenda liet precies de lege klassen blanco.
#' Deze glyph leest alleen `fill`, die de schaal voor elke klasse levert, dus
#' elk vakje wordt getekend of er nu een regio in valt of niet. Het kadertje
#' houdt de lichtste klasse zichtbaar op wit papier.
draw_key_vlak <- function(data, params, size) {
  vulling <- if (is.null(data$fill)) "grey20" else data$fill
  grid::rectGrob(gp = grid::gpar(col = "#b9b9b9", fill = vulling, lwd = 0.7))
}

#' De klasse-indeling achter de figuur: waarde -> klasse-label, plus de kleur
#' per klasse. Apart van de tekenstap, omdat dit het stuk is dat fout kan gaan
#' (een verkeerde grens, een waarde die buiten de schaal valt, een kleur te
#' weinig) en het zonder sf of een tekendevice te testen is.
#'
#' @param waarde Numerieke vector; NA = onderdrukt.
#' @param bins Oplopende klassegrenzen, of minder dan twee als er niets te
#'   schalen valt.
#' @param weergave "rel" of "abs".
#' @return list(klasse = factor met alle klassen als levels, kleuren = evenveel
#'   kleuren, benoemd naar diezelfde klassen). Die namen doen het werk:
#'   scale_fill_manual() koppelt dan op naam in plaats van op volgorde, en dat
#'   blijft kloppen ook als niet elke klasse in de data voorkomt.
choropleth_klassen <- function(waarde, bins, weergave = "rel") {
  fmt <- function(v) {
    if (weergave == "rel") sprintf("%g%%", v)
    else format(round(v), big.mark = ".", decimal.mark = ",", trim = TRUE, scientific = FALSE)
  }

  labels <- if (length(bins) >= 2) {
    # Een gewoon streepje, geen en-dash: deze labels gaan ook het
    # PNG-tekendevice in, en Shiny Server kan onder een C-locale draaien waar
    # een niet-ASCII teken in de broncode geen een teken meer is (zie de
    # opmerking bij VENN_SUPPRESSED_MARK).
    sprintf("%s - %s", vapply(bins[-length(bins)], fmt, character(1)),
            vapply(bins[-1], fmt, character(1)))
  } else {
    character(0)
  }

  klasse <- if (length(labels)) {
    factor(labels[findInterval(waarde, bins, rightmost.closed = TRUE, all.inside = TRUE)],
           levels = labels)
  } else {
    factor(rep(NA_character_, length(waarde)), levels = character(0))
  }

  # De kleuren komen uit leaflet's eigen colorNumeric(), niet uit een tweede
  # palettepakket: dan is het aantoonbaar dezelfde YlOrRd-ramp als de kaart op
  # het scherm gebruikt. Bij een enkele klasse een kleur uit het midden, anders
  # zou de hele figuur bijna wit zijn -- net als in venn_svg().
  n <- length(labels)
  kleuren <- if (n == 0L) character(0) else {
    ramp <- colorNumeric("YlOrRd", domain = c(0, 1))
    setNames(ramp(if (n == 1L) 0.6 else seq(0, 1, length.out = n)), labels)
  }

  list(klasse = klasse, kleuren = kleuren)
}

#' @param laag sf-object met ten minste `waarde` en `region_name`.
#' @param bins Numerieke klassegrenzen (oplopend), of lengte 0 als er niets te
#'   schalen valt.
#' @param weergave "rel" of "abs" -- bepaalt de opmaak van de legendalabels.
#' @param titel,ondertitel,bron Tekst boven en onder de figuur.
#' @return Een ggplot-object.
choropleth_ggplot <- function(laag, bins, weergave = "rel",
                              titel = NULL, ondertitel = NULL, bron = NULL) {
  stopifnot(inherits(laag, "sf"), "waarde" %in% names(laag))

  ks <- choropleth_klassen(laag$waarde, bins, weergave)
  laag$klasse <- ks$klasse

  ggplot2::ggplot(laag) +
    ggplot2::geom_sf(ggplot2::aes(fill = klasse), colour = "#ffffff", linewidth = 0.15,
                     key_glyph = draw_key_vlak) +
    ggplot2::scale_fill_manual(
      values = ks$kleuren, drop = FALSE, na.value = MAP_NA_FILL,
      name = if (weergave == "rel") "Aandeel (%)" else "Aantal",
      labels = function(x) x,
      guide = ggplot2::guide_legend(reverse = TRUE)) +
    ggplot2::labs(title = titel, subtitle = ondertitel,
                  caption = paste(c(bron, "Grijs = onvoldoende waarnemingen (CBS-onderdrukking), niet nul."),
                                  collapse = "\n")) +
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
