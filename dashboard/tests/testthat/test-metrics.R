# utils/metrics.R beslist wat er met een metric mag: optellen, delen, of geen
# van beide. Dat is geen cosmetiek -- een gemiddelde dat als telling behandeld
# wordt komt als opgeteld getal op de kaart terecht.

test_that("average_score is een gemiddelde", {
  expect_true(metric_is_gemiddelde("average_score"))
  expect_false(metric_is_optelbaar("average_score"))
  expect_false(metric_telt_populatie("average_score"))
})

test_that("de tellingen zijn optelbaar", {
  tellingen <- c("n_households", "n_ouderen_with_var_value", "n_kinderen_hh",
                 "n_kinderen_0tot2_hh")
  expect_false(any(metric_is_gemiddelde(tellingen)))
  expect_true(all(metric_is_optelbaar(tellingen)))
})

test_that("alleen de populatietellingen hebben n_split als noemer", {
  expect_true(metric_telt_populatie("n_households"))
  expect_true(metric_telt_populatie("n_ouderen_with_var_value"))
  # De kindermetrics tellen kinderen tegen een huishoudnoemer; n_split telt
  # huishoudens en is er dus de verkeerde eenheid voor (PLAN.md 2b).
  expect_false(metric_telt_populatie("n_kinderen_hh"))
})

test_that("een volgend gemiddelde wordt aan zijn naam herkend", {
  # Zodat een nieuwe metric niet stilzwijgend als telling wordt opgeteld.
  expect_true(metric_is_gemiddelde("average_leeftijd"))
  expect_true(metric_is_gemiddelde("mean_score"))
  expect_true(metric_is_gemiddelde("gemiddelde_score"))
  # Maar niet alles wat toevallig met dezelfde letters begint.
  expect_false(metric_is_gemiddelde("averaged_out_hh"))
  expect_false(metric_is_gemiddelde("n_meanders"))
})

test_that("NA is geen van beide", {
  expect_false(metric_is_gemiddelde(NA_character_))
  expect_false(metric_telt_populatie(NA_character_))
})

test_that("de functies zijn gevectoriseerd", {
  x <- c("n_households", "average_score", "n_kinderen_hh")
  expect_equal(metric_is_gemiddelde(x), c(FALSE, TRUE, FALSE))
  expect_equal(metric_telt_populatie(x), c(TRUE, FALSE, FALSE))
})
