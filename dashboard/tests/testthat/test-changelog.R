# utils/changelog_ui.R zet data/metadata/changelog.R om in de "wat is er
# nieuw"-knop en het venster erachter. Het stipje leeft in de browser, maar de
# rest is gewone HTML-opbouw -- en die moet niet omvallen op een regel die
# iemand haastig heeft toegevoegd.

LOG <- list(
  list(datum = "2026-09-17", titel = "Nieuwste", punten = c("een", "twee")),
  list(datum = "2026-09-01", titel = "Ouder", punten = "drie")
)

test_that("de datum wordt leesbaar, zonder van de locale af te hangen", {
  expect_equal(changelog_datum("2026-09-17"), "17 sep 2026")
  expect_equal(changelog_datum("2026-01-05"), "5 jan 2026")
  expect_equal(changelog_datum("2026-12-31"), "31 dec 2026")
})

test_that("een onbruikbare datum laat de pagina staan", {
  # as.Date() gooit hier een fout in plaats van NA terug te geven; dat zou de
  # hele kop meenemen.
  expect_equal(changelog_datum("kapot"), "kapot")
  expect_silent(changelog_datum("2026-13-01"))
  expect_silent(changelog_datum(NA))
})

test_that("de knop draagt de datum van de bovenste regel", {
  h <- as.character(changelog_knop(log = LOG))
  expect_true(grepl('data-laatste="2026-09-17"', h, fixed = TRUE))
  # de stip begint zichtbaar: gaat er iets mis in de browser, dan blijft de
  # melding staan in plaats van stilletjes weg te vallen
  expect_true(grepl("changelog-stip", h, fixed = TRUE))
  expect_false(grepl("display: none", h, fixed = TRUE))
})

test_that("het venster toont elke regel met al zijn punten", {
  h <- as.character(changelog_inhoud(LOG))
  expect_equal(length(gregexpr("changelog-regel", h)[[1]]), 2)
  expect_equal(length(gregexpr("<li>", h)[[1]]), 3)
  expect_true(grepl("Nieuwste", h, fixed = TRUE))
  expect_true(grepl("17 sep 2026", h, fixed = TRUE))
})

test_that("de nieuwste regel staat bovenaan", {
  h <- as.character(changelog_inhoud(LOG))
  expect_lt(regexpr("Nieuwste", h), regexpr("Ouder", h))
})

test_that("een lege of ontbrekende lijst valt niet om", {
  expect_silent(changelog_inhoud(list()))
  expect_true(grepl("Nog niets", as.character(changelog_inhoud(list())), fixed = TRUE))
  expect_silent(changelog_knop(log = list()))
})

test_that("de meegeleverde changelog is bruikbaar", {
  # Dit is de lijst die de gebruikers echt zien, dus die moet compleet zijn.
  expect_gt(length(CHANGELOG), 0)
  for (regel in CHANGELOG) {
    expect_true(all(c("datum", "titel", "punten") %in% names(regel)))
    expect_match(regel$datum, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
    expect_gt(nchar(regel$titel), 0)
    expect_gt(length(regel$punten), 0)
  }
  # Nieuwste bovenaan -- daar hangt de stip op de knop van af.
  datums <- vapply(CHANGELOG, function(r) r$datum, character(1))
  expect_equal(datums, sort(datums, decreasing = TRUE))
})
