# utils/map_download.R tekent de choropleth opnieuw voor de download. De
# tekenstap zelf heeft sf en een device nodig; de klasse-indeling eronder niet,
# en dat is het stuk dat fout kan gaan. Die moet exact dezelfde grenzen
# aanhouden als de kaart op het scherm, want anders lijkt de gedownloade
# figuur er niet meer op.

BINS <- seq(0, 50, 10)

test_that("elke waarde valt in de klasse waar hij hoort", {
  k <- choropleth_klassen(c(0, 9.9, 10, 25, 49.9), BINS, "rel")
  expect_equal(as.character(k$klasse),
               c("0% - 10%", "0% - 10%", "10% - 20%",
                 "20% - 30%", "40% - 50%"))
})

test_that("de bovengrens valt binnen de laatste klasse, niet erbuiten", {
  # findInterval() zou 50 anders in een zesde, niet-bestaande klasse zetten.
  k <- choropleth_klassen(50, BINS, "rel")
  expect_equal(as.character(k$klasse), "40% - 50%")
  expect_false(is.na(k$klasse))
})

test_that("een onderdrukte waarde blijft NA en krijgt geen klasse", {
  k <- choropleth_klassen(c(15, NA), BINS, "rel")
  expect_true(is.na(k$klasse[2]))
})

test_that("er is precies een kleur per klasse, in dezelfde volgorde", {
  k <- choropleth_klassen(c(5, 45), BINS, "rel")
  expect_equal(length(k$kleuren), length(levels(k$klasse)))
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}", k$kleuren)))
})

test_that("alle klassen blijven levels, ook als geen enkele regio erin valt", {
  # Anders zou de legenda van de figuur korter zijn dan die van de kaart.
  k <- choropleth_klassen(c(5, 5), BINS, "rel")
  expect_equal(length(levels(k$klasse)), length(BINS) - 1L)
})

test_that("zonder schaal is er niets in te delen en niets te kleuren", {
  k <- choropleth_klassen(c(1, 2), numeric(0), "rel")
  expect_equal(length(levels(k$klasse)), 0)
  expect_equal(length(k$kleuren), 0)
  expect_true(all(is.na(k$klasse)))
})

test_that("een enkele klasse krijgt een kleur uit het midden van de schaal", {
  k <- choropleth_klassen(3000, c(2000, 5000), "abs")
  expect_equal(length(k$kleuren), 1)
  # niet de lichtste kleur van de ramp -- die zou als bijna wit uitkomen
  licht <- colorNumeric("YlOrRd", domain = c(0, 1))(0)
  expect_false(identical(k$kleuren, licht))
})

test_that("de weergave bepaalt de opmaak van de klasse-labels", {
  expect_true(grepl("%", levels(choropleth_klassen(5, BINS, "rel")$klasse)[1]))
  abs <- levels(choropleth_klassen(3000, c(0, 2000, 4000), "abs")$klasse)
  expect_false(any(grepl("%", abs)))
  expect_true(any(grepl("2.000", abs, fixed = TRUE)))   # duizendtallen met een punt
})

# De legenda toonde lege vakjes voor klassen waar geen enkele regio in viel:
# geom_sf tekent zijn vakjes met draw_key_polygon(), die de afmeting uit de
# rij haalt, en die rij is er voor zo'n klasse niet. Twee dingen houden dat nu
# tegen -- kleuren op naam, en een glyph die alleen naar de vulling kijkt.

test_that("de kleuren zijn benoemd naar hun klasse", {
  # Zonder namen koppelt scale_fill_manual() op volgorde tegen de klassen die
  # in de data voorkomen, en schuift de hele schaal op zodra er een ontbreekt.
  k <- choropleth_klassen(c(17, 33), seq(16, 34, 2), "rel")
  expect_equal(names(k$kleuren), levels(k$klasse))
})

test_that("ook een klasse zonder enkele regio houdt zijn eigen kleur", {
  # 22%-24% en 26%-28% zijn leeg; hun kleur moet dezelfde zijn als wanneer ze
  # wel gevuld waren geweest.
  bins <- seq(16, 34, 2)
  vol <- choropleth_klassen(seq(17, 33, 2), bins, "rel")
  leeg <- choropleth_klassen(c(17, 33), bins, "rel")
  expect_equal(leeg$kleuren, vol$kleuren)
})

test_that("de legenda-glyph tekent op de vulling alleen", {
  # draw_key_polygon() valt om op een ontbrekende linewidth; deze niet.
  g <- draw_key_vlak(list(fill = "#FD8D3C"), list(), 1)
  expect_s3_class(g, "rect")
  expect_equal(g$gp$fill, "#FD8D3C")
  # geen fill in de rij (een klasse zonder data) levert nog steeds een vakje
  expect_s3_class(draw_key_vlak(list(), list(), 1), "rect")
})
