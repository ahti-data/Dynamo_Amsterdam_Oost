# De think-cell-tabeldownload werd niet gelogd: hij kreeg wel een herkomstregel
# in de hoekcel mee, maar zonder download-id en zonder regel in Export history.
# Daarmee was dat de enige export die je niet kon terugzoeken vanaf het bestand
# in iemands inbox. Deze tests houden dat dicht.

skip_if_not_installed("dplyr")     # format_tc_data() pakt %>% uit de app
skip_if_not_installed("tidyr")
skip_if_not_installed("writexl")

library(shiny)
suppressPackageStartupMessages(library(dplyr))

VOORBEELD <- data.frame(jaar = c(2023, 2024, 2023, 2024),
                        reeks = c("A", "A", "B", "B"),
                        waarde = c(1, 2, 3, 4))

#' De content()-functie achter een downloadknop van de module.
#'
#' Shiny biedt geen nette weg om een downloadHandler in testServer aan te
#' roepen, dus dit graaft in MockShinySession. Verandert die interne opbouw bij
#' een shiny-upgrade, dan geeft dit NULL en slaan de tests hieronder over met
#' een zichtbare reden -- liever dat dan een rode test die niets met deze code
#' te maken heeft.
download_content <- function(session, naam) {
  tryCatch({
    outs <- .subset2(session, "parent")$.__enclos_env__$private$outs
    environment(environment(outs[[naam]]$func)$renderFunc)$content
  }, error = function(e) NULL)
}

met_historie <- function(code) {
  dir <- tempfile("hist_")
  oud <- Sys.getenv("SHINY_EXPORT_HISTORY_DIR", unset = NA)
  Sys.setenv(SHINY_EXPORT_HISTORY_DIR = dir)
  on.exit({
    if (is.na(oud)) Sys.unsetenv("SHINY_EXPORT_HISTORY_DIR") else Sys.setenv(SHINY_EXPORT_HISTORY_DIR = oud)
    unlink(dir, recursive = TRUE)
  }, add = TRUE)
  code(dir)
}

download_thinkcell <- function(dir, data = VOORBEELD, ...) {
  uit <- list()
  testServer(chart_data_downloads_server, args = c(list(
    id = "dl", data = reactive(data), chart_type = "line",
    category_col = "jaar", series_col = "reeks", value_col = "waarde",
    agg_fun = NULL, filename_prefix = "test",
    source_output = "output_1a", source_sheet = "OT.csv"), list(...)), {
    content <- download_content(session, "dl-thinkcell")
    uit$overslaan <<- is.null(content)
    if (!is.null(content)) {
      uit$bestand <<- tempfile(fileext = ".xlsx")
      content(uit$bestand)
    }
  })
  uit
}

test_that("een think-cell-download levert een regel in Export history op", {
  met_historie(function(dir) {
    r <- download_thinkcell(dir)
    skip_if(isTRUE(r$overslaan), "MockShinySession-interne opbouw veranderd; pas download_content() aan")

    expect_true(file.exists(r$bestand))
    entries <- export_history_list()
    expect_equal(length(entries), 1)

    e <- entries[[1]]
    expect_match(e$id, "^exp_")
    expect_equal(e$chart_type, "line")
    expect_equal(e$source_output, "output_1a")
    expect_equal(e$module_id, "dl")
    # De momentopname moet er ook in zitten, anders valt er later niets mee te
    # herhalen -- dat is het verschil tussen een logregel en een exporthistorie.
    expect_false(is.null(e$tc_data_table))
    expect_false(is.null(e$slide_matrix_table))
  })
})

test_that("het download-id staat in de werkmap en wijst naar diezelfde regel", {
  # Dit is wat een bestand in iemands inbox terugvindbaar maakt.
  met_historie(function(dir) {
    r <- download_thinkcell(dir)
    skip_if(isTRUE(r$overslaan), "MockShinySession-interne opbouw veranderd")

    id <- export_history_list()[[1]]$id
    uitgepakt <- tempfile("xlsx_")
    utils::unzip(r$bestand, exdir = uitgepakt)
    tekst <- unlist(lapply(list.files(uitgepakt, recursive = TRUE, full.names = TRUE),
                           function(f) tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))))
    expect_true(any(grepl(paste0("download_id=", id), tekst, fixed = TRUE)))
  })
})

test_that("elke download is een eigen regel, geen overschreven regel", {
  met_historie(function(dir) {
    r1 <- download_thinkcell(dir)
    skip_if(isTRUE(r1$overslaan), "MockShinySession-interne opbouw veranderd")
    download_thinkcell(dir)
    expect_equal(length(export_history_list()), 2)
    ids <- vapply(export_history_list(), function(e) e$id, character(1))
    expect_equal(length(unique(ids)), 2)
  })
})

test_that("de ruwe xlsx blijft ongelogd", {
  # Die draagt geen think-cell-opmaak en geen herkomstregel; hem meenemen zou
  # de historie vullen met regels die nergens naar verwijzen.
  met_historie(function(dir) {
    overslaan <- TRUE
    testServer(chart_data_downloads_server, args = list(
      id = "dl", data = reactive(VOORBEELD), chart_type = "line",
      category_col = "jaar", series_col = "reeks", value_col = "waarde",
      agg_fun = NULL, filename_prefix = "test"), {
      content <- download_content(session, "dl-raw")
      overslaan <<- is.null(content)
      if (!is.null(content)) content(tempfile(fileext = ".xlsx"))
    })
    skip_if(overslaan, "MockShinySession-interne opbouw veranderd")
    expect_equal(length(export_history_list()), 0)
  })
})
