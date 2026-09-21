test_that("vergelijk_regio_keuzes perkt in tot een stadsdeel", {
  meta <- data.frame(
    region_code = c("WK036300", "WK036301", "WK036302"),
    region_name = c("Indische Buurt", "Oostelijk Havengebied", "De Baarsjes"),
    stadsdeel   = c("Oost", "Oost", "West"),
    stringsAsFactors = FALSE
  )

  alles <- vergelijk_regio_keuzes(meta, "Heel Amsterdam")
  expect_equal(unname(alles), meta$region_code)
  expect_equal(names(alles), meta$region_name)

  oost <- vergelijk_regio_keuzes(meta, "Oost")
  expect_equal(unname(oost), c("WK036300", "WK036301"))
  expect_equal(names(oost), c("Indische Buurt", "Oostelijk Havengebied"))
})

test_that("een niveau zonder stadsdeel wordt niet weggefilterd", {
  # Het gemeentevlak ligt in geen enkel stadsdeel; zou "Toon" daar toch
  # snijden, dan bleef de keuzelijst leeg in plaats van dat hij korter werd.
  meta <- data.frame(region_code = "Amsterdam", region_name = "Heel Amsterdam",
                     stadsdeel = NA_character_, stringsAsFactors = FALSE)
  expect_equal(unname(vergelijk_regio_keuzes(meta, "Oost")), "Amsterdam")
})

test_that("vergelijk_regio_keuzes verdraagt een leeg niveau", {
  leeg <- data.frame(region_code = character(0), region_name = character(0),
                     stadsdeel = character(0), stringsAsFactors = FALSE)
  expect_equal(vergelijk_regio_keuzes(leeg, "Oost"), character(0))
  expect_equal(vergelijk_regio_keuzes(NULL, "Oost"), character(0))
})

test_that("de startselectie pakt alles tot het maximum", {
  keuzes <- stats::setNames(sprintf("WK%02d", 1:20), sprintf("Wijk %d", 1:20))
  expect_equal(vergelijk_start_selectie(keuzes, 15L), unname(keuzes)[1:15])
  expect_equal(vergelijk_start_selectie(keuzes[1:4], 15L), unname(keuzes[1:4]))
  expect_equal(vergelijk_start_selectie(character(0)), character(0))
})

test_that("de reeksvolgorde loopt van hoog naar laag in het laatste jaar", {
  d <- data.frame(
    naam   = c("A", "B", "C", "A", "B", "C"),
    jaar   = c(2023, 2023, 2023, 2024, 2024, 2024),
    waarde = c(1, 2, 3,  10, 30, 20)
  )
  expect_equal(vergelijk_reeks_volgorde(d$naam, d$jaar, d$waarde), c("B", "C", "A"))
})

test_that("een regio zonder cijfer in het laatste jaar staat achteraan", {
  d <- data.frame(
    naam   = c("A", "B", "C"),
    jaar   = c(2024, 2024, 2024),
    waarde = c(10, NA, 20)
  )
  expect_equal(vergelijk_reeks_volgorde(d$naam, d$jaar, d$waarde), c("C", "A", "B"))
})

test_that("het laatste jaar is het laatste jaar mét cijfers", {
  # 2024 is wel geleverd maar overal onderdrukt; dan bepaalt 2023 de volgorde,
  # niet een kolom NA's.
  d <- data.frame(
    naam   = c("A", "B", "A", "B"),
    jaar   = c(2023, 2023, 2024, 2024),
    waarde = c(5, 9, NA, NA)
  )
  expect_equal(vergelijk_reeks_volgorde(d$naam, d$jaar, d$waarde), c("B", "A"))
})

test_that("zonder enig cijfer blijft de volgorde alfabetisch", {
  d <- data.frame(naam = c("B", "A"), jaar = c(2024, 2024), waarde = c(NA_real_, NA_real_))
  expect_equal(vergelijk_reeks_volgorde(d$naam, d$jaar, d$waarde), c("A", "B"))
  expect_equal(vergelijk_reeks_volgorde(character(0), numeric(0), numeric(0)), character(0))
})

test_that("het palet herhaalt geen kleur", {
  merk <- c("#EE3124", "#009DDC", "#336A88", "#00A55D", "#20153E")
  expect_equal(vergelijk_palet(3, merk), merk[1:3])
  expect_equal(vergelijk_palet(5, merk), merk)

  veel <- vergelijk_palet(15, merk)
  expect_length(veel, 15)
  expect_length(unique(veel), 15)
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}", veel)))

  expect_equal(vergelijk_palet(0, merk), character(0))
})
