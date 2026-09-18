# data-prep/01_build_app_data.R zet een levering om naar het lange schema. Dat
# script is niet te sourcen -- het leest geometrie en schrijft parquet -- maar
# zijn kernstuk, reshape_delivery(), is pure logica en is precies het stuk dat
# met output_1b veranderde: een rij mag naar meer dan een variabele tegelijk
# uitgesplitst zijn, en dat wordt hier tot een sleutel samengesteld.
#
# Daarom worden alleen de losse toekenningen eruit gehaald die deze functie
# nodig heeft. Verhuist er iets, dan valt dit hard om met de naam erbij -- veel
# beter dan een ongeteste prep-stap.

# testthat draait vanuit tests/testthat/, maar test_file() vanuit tests/ -- dus
# het pad niet vastzetten.
prep_script <- function() {
  kandidaten <- file.path(c("../..", "..", "."), "data-prep", "01_build_app_data.R")
  gevonden <- kandidaten[file.exists(kandidaten)]
  if (length(gevonden)) gevonden[1] else kandidaten[1]
}

haal_uit_script <- function(namen, pad = prep_script()) {
  if (!file.exists(pad)) stop("prep-script niet gevonden vanaf ", getwd())
  env <- new.env(parent = globalenv())
  gevonden <- character(0)
  for (expr in parse(pad)) {
    if (!is.call(expr) || !identical(as.character(expr[[1]]), "<-")) next
    doel <- as.character(expr[[2]])
    if (length(doel) != 1L || !doel %in% namen) next
    eval(expr, envir = env)
    gevonden <- c(gevonden, doel)
  }
  ontbreekt <- setdiff(namen, gevonden)
  if (length(ontbreekt)) {
    stop("Niet gevonden in ", pad, ": ", paste(ontbreekt, collapse = ", "),
         ". Is het script herschikt? Werk deze test bij.")
  }
  env
}

PREP <- haal_uit_script(c("LEVEL_LABELS", "TOTAL_LABEL", "DELIVERY_FIXED_COLS",
                          "SPLIT_ALL", "reshape_delivery"))

# Een levering zoals hij binnenkomt: vaste kolommen plus splitskolommen die
# "all" dragen waar die rij niet naar die variabele is uitgesplitst.
levering <- function(...) {
  rijen <- list(...)
  vast <- data.table::data.table(
    region_code = "0363AA", region_agg_level = "wc", year = 2024L,
    variable_name = "R_MPG_totaal", variable_value = "1",
    n_totaal_population_in_region = 1000, n_totaal_region_splitvar = 1000,
    metric_name = "n_households", metric_value = 100,
    # De levering draagt zelf een population-kolom, met op elke rij dezelfde
    # waarde. Geen uitsplitsing dus -- en de prep-stap overschrijft hem met het
    # label dat de app gebruikt (hier met een spatie in plaats van een _).
    population = "huishoudens_met_kinderen")
  data.table::rbindlist(lapply(rijen, function(r) {
    d <- data.table::copy(vast)
    for (nm in names(r)) data.table::set(d, j = nm, value = r[[nm]])
    d
  }), fill = TRUE)
}

rij <- function(geslacht = "all", O_MPG_combination = "all", ...) {
  c(list(geslacht = geslacht, O_MPG_combination = O_MPG_combination), list(...))
}

test_that("een totaalrij en een enkele marginaal houden hun oude vorm", {
  uit <- PREP$reshape_delivery(levering(rij(), rij(geslacht = "vrouw")), "huishoudens met kinderen")
  expect_equal(uit[split_var == "(totaal)"]$split_level, "(totaal)")
  expect_equal(uit[split_var == "geslacht"]$split_level, "vrouw")
  expect_equal(nrow(uit), 2L)
})

test_that("twee splitsvariabelen tegelijk worden een samengestelde sleutel", {
  # Met een totaalrij erbij, zoals elke echte levering: zonder rij waarin een
  # splitskolom "all" is zou die kolom niet als uitsplitsing herkend worden.
  uit <- PREP$reshape_delivery(
    levering(rij(), rij(geslacht = "vrouw", O_MPG_combination = "O_MPG1")),
    "huishoudens met kinderen")
  uit <- uit[split_var != "(totaal)"]
  expect_equal(uit$split_var, split_key(c("geslacht", "O_MPG_combination")))
  # De waarden staan in dezelfde volgorde als de namen in de sleutel.
  namen <- split_parts(uit$split_var)
  waarden <- split_parts(uit$split_level)
  expect_equal(waarden[match("geslacht", namen)], "vrouw")
  expect_equal(waarden[match("O_MPG_combination", namen)], "O_MPG1")
})

test_that("de sleutel is die welke de app bouwt, ongeacht de kolomvolgorde", {
  # De app kent de aanklikvolgorde van de gebruiker, het bestand de
  # kolomvolgorde; allebei moeten op dezelfde sleutel uitkomen.
  d <- levering(rij(), rij(geslacht = "vrouw", O_MPG_combination = "O_MPG1"))
  data.table::setcolorder(d, rev(names(d)))
  uit <- PREP$reshape_delivery(d, "huishoudens met kinderen")
  expect_equal(uit[split_var != "(totaal)"]$split_var,
               split_key(c("O_MPG_combination", "geslacht")))
})

test_that("de kolommen krijgen de namen die de app verwacht", {
  uit <- PREP$reshape_delivery(levering(rij()), "huishoudens met kinderen")
  expect_true(all(c("n_totaal", "n_split", "population", "region_level") %in% names(uit)))
  expect_false("n_totaal_region_splitvar" %in% names(uit))
  expect_equal(uit$region_level, "wijk")     # wc -> wijk
  expect_equal(uit$n_split, 1000)
  # De population-kolom uit de levering is geen uitsplitsing geworden, en draagt
  # het label van de app in plaats van de schrijfwijze van het bestand.
  expect_equal(uit$population, "huishoudens met kinderen")
  expect_false(any(grepl("population", uit$split_var, fixed = TRUE)))
})

test_that("een lege cel telt als 'niet uitgesplitst'", {
  uit <- PREP$reshape_delivery(levering(rij(geslacht = ""), rij(geslacht = NA)),
                               "huishoudens met kinderen")
  expect_true(all(uit$split_var == "(totaal)"))
})

test_that("een ontbrekende verplichte kolom stopt de bouw", {
  d <- levering(rij())
  d[, n_totaal_region_splitvar := NULL]
  expect_error(PREP$reshape_delivery(d, "huishoudens met kinderen"),
               "n_totaal_region_splitvar", fixed = TRUE)
})

test_that("een kolom zonder 'all' is geen uitsplitsing en stopt de bouw", {
  # Zo'n kolom is een nieuwe vaste kolom uit de levering; die zou anders als
  # splitsvariabele in de keuzelijst van het dashboard belanden.
  d <- levering(rij(), rij())
  d[, bronbestand := "OT_HHKIND"]
  expect_error(PREP$reshape_delivery(d, "huishoudens met kinderen"),
               "DELIVERY_FIXED_COLS", fixed = TRUE)
})

test_that("een waarde met het scheidingsteken erin stopt de bouw", {
  # Die zou bij het uitpakken in tweeen vallen en stil de verkeerde rijen
  # selecteren.
  d <- levering(rij(geslacht = paste0("man", SPLIT_SEP, "vrouw")), rij())
  expect_error(PREP$reshape_delivery(d, "huishoudens met kinderen"),
               SPLIT_SEP, fixed = TRUE)
})
