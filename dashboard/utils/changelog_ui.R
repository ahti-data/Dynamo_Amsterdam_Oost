#' De "wat is er nieuw"-knop en het venster erachter.
#'
#' Leest data/metadata/changelog.R (object `CHANGELOG`). De knop staat rechts
#' in de kop en draagt de datum van de bovenste regel; een klik opent een
#' venster met de hele lijst.
#'
#' Het stipje ernaast betekent "hier heb je nog niet naar gekeken". Dat wordt in
#' de browser onthouden (localStorage), niet op de server: het dashboard heeft
#' geen accounts, dus er is geen plek om het per persoon te bewaren. Alles staat
#' in een try/catch en het stipje begint *zichtbaar* -- gaat er iets mis in de
#' browser, dan blijft het staan, en dat is onschuldig. Andersom (verborgen
#' beginnen) zou de melding stilletjes kunnen wegvallen.

CHANGELOG_SLEUTEL <- "dynamo_changelog_gezien"

#' "2026-09-17" -> "17 sep 2026". Met de maandnamen erbij in plaats van via
#' format(): dat hangt aan de locale, en Shiny Server draait vaak onder C.
changelog_datum <- function(iso) {
  maanden <- c("jan", "feb", "mrt", "apr", "mei", "jun",
               "jul", "aug", "sep", "okt", "nov", "dec")
  # Eerst de vorm controleren: as.Date() gooit een fout op iets onherkenbaars
  # in plaats van NA terug te geven, en daar zou de hele pagina op stuklopen.
  if (length(iso) != 1L || is.na(iso) || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", iso)) {
    return(as.character(iso))
  }
  delen <- as.integer(strsplit(iso, "-")[[1]])
  if (delen[2] < 1L || delen[2] > 12L) return(iso)
  sprintf("%d %s %d", delen[3], maanden[delen[2]], delen[1])
}

#' De knop, voor in de kop van de pagina.
changelog_knop <- function(id = "changelog_knop", log = CHANGELOG) {
  laatste <- if (length(log)) log[[1]]$datum else ""
  tagList(
    tags$style(HTML("
      .changelog-knop { border: 1px solid #d5dde2; background: #fff; border-radius: 16px;
        padding: 4px 12px; font-size: 12px; color: #336A88; cursor: pointer; }
      .changelog-knop:hover { background: #f4f8fa; text-decoration: none; }
      .changelog-stip { display: inline-block; width: 7px; height: 7px; border-radius: 50%;
        background: #EE3124; margin-left: 6px; vertical-align: middle; }
      .changelog-regel { border-left: 3px solid #009DDC; padding: 2px 0 2px 12px; margin-bottom: 18px; }
      .changelog-regel h4 { font-size: 14px; font-weight: 600; margin: 0 0 2px; color: #336A88; }
      .changelog-datum { font-size: 11px; color: #7a7a7a; margin-bottom: 6px; }
      .changelog-regel ul { padding-left: 18px; margin: 0; }
      .changelog-regel li { font-size: 12.5px; line-height: 1.5; margin-bottom: 3px; }
    ")),
    actionLink(id, class = "changelog-knop", `data-laatste` = laatste,
               label = tagList("✨ Wat is er nieuw",
                               span(id = paste0(id, "_stip"), class = "changelog-stip"))),
    tags$script(HTML(sprintf("
      (function() {
        var sleutel = '%s', knop = '#%s', stip = '#%s_stip';
        function gezien() { try { return window.localStorage.getItem(sleutel); } catch (e) { return null; } }
        $(document).on('shiny:connected', function() {
          var laatste = $(knop).attr('data-laatste'), g = gezien();
          if (g && laatste && g >= laatste) { $(stip).hide(); }
        });
        $(document).on('click', knop, function() {
          try { window.localStorage.setItem(sleutel, $(knop).attr('data-laatste')); } catch (e) {}
          $(stip).hide();
        });
      })();
    ", CHANGELOG_SLEUTEL, id, id)))
  )
}

#' De inhoud van het venster.
changelog_inhoud <- function(log = CHANGELOG) {
  if (!length(log)) return(div(class = "note", "Nog niets te melden."))
  tagList(lapply(log, function(regel) {
    div(class = "changelog-regel",
        h4(regel$titel),
        div(class = "changelog-datum", changelog_datum(regel$datum)),
        tags$ul(lapply(regel$punten, tags$li)))
  }))
}

#' Het venster zelf, voor showModal().
changelog_venster <- function(log = CHANGELOG) {
  modalDialog(
    title = "Wat is er nieuw in dit dashboard",
    changelog_inhoud(log),
    footer = tagList(
      div(class = "note", style = "text-align: left; margin-bottom: 8px;",
          "Deze lijst gaat over wat je hier ziet, niet over de techniek eronder.",
          " Mist er iets, of klopt een cijfer niet met wat je verwacht? Laat het weten."),
      modalButton("Sluiten")),
    easyClose = TRUE, size = "l")
}
