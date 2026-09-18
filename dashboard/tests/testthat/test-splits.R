# utils/splits.R codeert een uitsplitsing naar meer dan een variabele tegelijk
# als een samengestelde sleutel. De hele afspraak staat of valt met twee dingen:
# dezelfde verzameling geeft altijd dezelfde sleutel (ongeacht aanklikvolgorde
# en ongeacht de locale), en de sleutel valt weer in precies dezelfde onderdelen
# uiteen.

test_that("een enkele variabele is gewoon zichzelf", {
  expect_equal(split_key("geslacht"), "geslacht")
  expect_equal(split_parts("geslacht"), "geslacht")
})

test_that("leeg betekent niet uitsplitsen", {
  expect_equal(split_key(character(0)), SPLIT_TOTAL_LABEL)
  expect_equal(split_key(NULL), SPLIT_TOTAL_LABEL)
  expect_equal(split_key(SPLIT_TOTAL_LABEL), SPLIT_TOTAL_LABEL)
  expect_equal(split_parts(SPLIT_TOTAL_LABEL), character(0))
  expect_equal(split_parts(NA_character_), character(0))
})

test_that("de volgorde van aanklikken maakt niet uit", {
  a <- split_key(c("geslacht", "herkomst7"))
  b <- split_key(c("herkomst7", "geslacht"))
  expect_identical(a, b)
  expect_equal(split_parts(a), c("geslacht", "herkomst7"))
})

test_that("de sleutel is dezelfde onder een andere collatie", {
  # De prep-stap en de Shiny-server draaien niet per se onder dezelfde locale.
  # Volgt de sortering de locale, dan bouwt de app een andere sleutel dan die in
  # de parquet staat en blijft de selectie zonder melding leeg.
  vars <- c("geslacht", "O_MPG_combination", "langwonende_hh")
  oud <- Sys.getlocale("LC_COLLATE")
  on.exit(suppressWarnings(Sys.setlocale("LC_COLLATE", oud)), add = TRUE)

  suppressWarnings(Sys.setlocale("LC_COLLATE", "C"))
  onder_c <- split_key(vars)
  gelukt <- suppressWarnings(Sys.setlocale("LC_COLLATE", "en_US.UTF-8"))
  skip_if(!nzchar(gelukt), "geen tweede collatie beschikbaar op deze machine")
  expect_identical(split_key(vars), onder_c)
})

test_that("dubbele en lege namen tellen niet mee", {
  expect_equal(split_key(c("geslacht", "geslacht")), "geslacht")
  expect_equal(split_key(c("geslacht", "", NA)), "geslacht")
})

test_that("split_vars_available noemt de losse variabelen, niet de samenstellingen", {
  keys <- c(SPLIT_TOTAL_LABEL, "geslacht", "O_MPG_combination | geslacht")
  expect_equal(split_vars_available(keys), c("O_MPG_combination", "geslacht"))
})

test_that("split_key_bestaat kijkt naar wat er echt geleverd is", {
  keys <- c("geslacht", "O_MPG_combination | geslacht")
  expect_true(split_key_bestaat(split_key(c("geslacht", "O_MPG_combination")), keys))
  expect_false(split_key_bestaat(split_key(c("geslacht", "herkomst7")), keys))
})

test_that("split_pretty labelt elk onderdeel apart", {
  labeller <- function(deel, i) toupper(deel)
  expect_equal(split_pretty("a | b", labeller), "A \u00b7 B")
  expect_equal(split_pretty(SPLIT_TOTAL_LABEL, labeller), SPLIT_TOTAL_LABEL)
  # De index zegt bij welk onderdeel je zit, zodat een niveau langs de labeller
  # van zijn eigen variabele kan.
  expect_equal(split_pretty("a | b", function(deel, i) paste0(deel, i)), "a1 \u00b7 b2")
})

test_that("een waarde met het scheidingsteken erin wordt tegengehouden", {
  # Zo'n waarde zou bij het uitpakken in tweeen vallen en stil de verkeerde
  # rijen selecteren; dat hoort in de prep-stap om te vallen.
  expect_error(split_check_sep(c("man", "vrouw | anders")), SPLIT_SEP, fixed = TRUE)
  expect_true(split_check_sep(c("man", "vrouw")))
  expect_true(split_check_sep(character(0)))
})
