# utils/map.R deelt de kaartlogica tussen het scherm en de download. Twee
# stukken kunnen daar echt fout gaan, en die zijn allebei zonder sf of
# tekendevice te testen: de optelling van meerdere selecties (waar de noemer
# de valkuil is) en het bereik van de kleurschaal.

rijen <- function(...) {
  d <- data.table::rbindlist(list(...))
  d[, `:=`(population = "huishoudens met kinderen", region_level = "wijk",
           region_name = paste0("wijk ", region_code), stadsdeel = "Oost",
           year = 2024L, metric_name = "n_households", variable_name = "R_MPG_totaal")]
  d[]
}
cel <- function(region_code, split_level, variable_value, metric_value, denominator) {
  data.table::data.table(region_code = region_code, split_level = split_level,
                         variable_value = variable_value, metric_value = metric_value,
                         denominator = denominator, n_totaal = 1000,
                         split_var = "O_MPG_combination")
}

test_that("meerdere splitsniveaus tellen op, noemer inbegrepen", {
  # Twee deelgebieden van de venn samen: beide tellers en beide noemers erbij.
  d <- rijen(cel("A", "O_MPG1", "1", 30, 100),
             cel("A", "O_MPG2", "1", 20, 200))
  uit <- map_aggregate(d, 2)
  expect_equal(nrow(uit), 1)
  expect_equal(uit$metric_value, 50)
  expect_equal(uit$denominator, 300)
})

test_that("meerdere indicatorwaarden tellen op zonder de noemer te verdubbelen", {
  # Binnen een splitsniveau is de noemer voor elke waarde dezelfde -- hij is
  # per definitie de som over alle waarden. Optellen zou hem dubbel tellen en
  # het percentage halveren.
  d <- rijen(cel("A", "O_MPG1", "1", 30, 100),
             cel("A", "O_MPG1", "2", 20, 100))
  uit <- map_aggregate(d, 2)
  expect_equal(uit$metric_value, 50)
  expect_equal(uit$denominator, 100)
})

test_that("niveaus en waarden tegelijk: som over beide, noemer per uniek niveau", {
  d <- rijen(cel("A", "O_MPG1", "1", 30, 100), cel("A", "O_MPG1", "2", 10, 100),
             cel("A", "O_MPG2", "1", 20, 200), cel("A", "O_MPG2", "2", 40, 200))
  uit <- map_aggregate(d, 4)
  expect_equal(uit$metric_value, 100)
  expect_equal(uit$denominator, 300)
})

test_that("een regio met een onderdrukte cel blijft staan, maar wordt gemarkeerd", {
  # Bewust anders dan elders in dit dashboard: bij een handmatig samengestelde
  # groep is een ondergrens mét waarschuwing bruikbaarder dan een grijs vlak.
  # De markering is wat dat verschil draagt -- kaart, tooltip en export lezen
  # hem -- dus die moet er zijn en moet kloppen.
  d <- rijen(cel("A", "O_MPG1", "1", 30, 100), cel("A", "O_MPG2", "1", 20, 200),
             cel("B", "O_MPG1", "1", 40, 150))          # B mist O_MPG2
  uit <- map_aggregate(d, 2)[order(region_code)]

  expect_equal(uit$region_code, c("A", "B"))
  expect_equal(uit$compleet, c(TRUE, FALSE))
  # B telt op wat er is: een ondergrens, geen nul en geen weggelaten regio.
  expect_equal(uit[region_code == "B"]$metric_value, 40)
  expect_equal(uit[region_code == "B"]$denominator, 150)
})

test_that("bij een enkelvoudige keuze is elke regio compleet", {
  d <- rijen(cel("A", "O_MPG1", "1", 30, 100), cel("B", "O_MPG1", "1", 40, 150))
  expect_true(all(map_aggregate(d, 1)$compleet))
})

test_that("een regio zonder enkele gevraagde cel komt niet in beeld", {
  # Anders dan een halve optelling: hier is er niets om op te tellen.
  d <- rijen(cel("A", "O_MPG1", "1", 30, 100))
  uit <- map_aggregate(d, 2)
  expect_equal(uit$region_code, "A")
  expect_false(uit$compleet)
})

test_that("de samenvatting vertelt zelf wat er opgeteld is", {
  # Komma's, want de niveaunamen dragen zelf al een " + ".
  d <- rijen(cel("A", "O_MPG2", "1", 20, 200), cel("A", "O_MPG1", "1", 30, 100))
  uit <- map_aggregate(d, 2)
  expect_equal(uit$split_level, "O_MPG1, O_MPG2")    # gesorteerd, niet in ophaalvolgorde
  expect_equal(uit$variable_value, "1")
  expect_equal(uit$n_totaal, 1000)                    # regiototaal telt niet mee
})

test_that("een lege selectie geeft een lege tabel, geen fout", {
  expect_equal(nrow(map_aggregate(rijen(cel("A", "x", "1", 1, 1))[0], 2)), 0)
})

test_that("het kleurbereik volgt standaard de data", {
  expect_equal(map_domein(c(12, 5, NA, 30)), c(5, 30))
  expect_null(map_domein(c(NA_real_, NA_real_)))
})

test_that("een handmatig bereik gaat voor, maar alleen als het geldig is", {
  expect_equal(map_domein(c(5, 30), c(0, 100)), c(0, 100))
  expect_equal(map_domein(c(5, 30), c(NA, 100)), c(5, 30))   # half ingevuld
  expect_equal(map_domein(c(5, 30), c(100, 0)), c(5, 30))    # omgedraaid
  expect_equal(map_domein(c(5, 30), c(10, 10)), c(5, 30))    # nul breed
})

test_that("een selectie met overal dezelfde waarde houdt een tekenbare schaal", {
  d <- map_domein(c(20, 20, 20))
  expect_lt(d[1], d[2])
})

test_that("waarden buiten het bereik worden geklemd, niet weggegooid", {
  # Anders zou colorNumeric() ze de NA-kleur geven, wat als "onvoldoende
  # waarnemingen" leest terwijl het juist een hoge waarde is.
  expect_equal(map_klem(c(-5, 20, 150), c(0, 100)), c(0, 20, 100))
  expect_true(is.na(map_klem(NA_real_, c(0, 100))))
  expect_equal(map_klem(c(1, 2), NULL), c(1, 2))
})
