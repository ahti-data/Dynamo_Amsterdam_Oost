# data-prep/derive_support_splits.R leidt twee uitsplitsingen af die niet als
# kolom in de CBS-levering zitten. Deze tests bewaken vooral de
# onderdrukkingsregel: een som over combinatieniveaus mag een ontbrekende
# (= onderdrukte) cel nooit als nul meetellen, dus komt er dan geen rij.

CODES <- c("O_MPG1", "O_MPG2", "O_MPG3")
ALLE_NIVEAUS <- c("none", CODES,
                  "O_MPG1 + O_MPG2", "O_MPG1 + O_MPG3", "O_MPG2 + O_MPG3",
                  "O_MPG1 + O_MPG2 + O_MPG3")

# Een slice zoals de levering hem aanlevert: per variable_value een totaalrij
# plus de 8 combinatieniveaus. `niveaus` laat weg wat onderdrukt is.
maak_slice <- function(waarden, totaal, variable_value = "1",
                       variable_name = "R_MPG_totaal",
                       niveaus = ALLE_NIVEAUS, region_code = "0363AA") {
  vast <- list(population = "huishoudens met kinderen", region_level = "wijk",
               region_code = region_code, region_name = "Testwijk",
               stadsdeel = "Oost", year = 2024L, variable_name = variable_name,
               variable_value = variable_value, metric_name = "n_households",
               n_totaal = 1000)
  combo <- data.table::as.data.table(c(vast, list(
    metric_value = unname(waarden[niveaus]),
    split_var = "O_MPG_combination", split_level = niveaus)))
  tot <- data.table::as.data.table(c(vast, list(
    metric_value = totaal, split_var = "(totaal)", split_level = "(totaal)")))
  rbind(tot, combo)
}

# 8 niveaus die samen precies op 1000 uitkomen.
WAARDEN <- c(none = 600, O_MPG1 = 100, O_MPG2 = 80, O_MPG3 = 70,
             "O_MPG1 + O_MPG2" = 50, "O_MPG1 + O_MPG3" = 40,
             "O_MPG2 + O_MPG3" = 30, "O_MPG1 + O_MPG2 + O_MPG3" = 30)

niveau <- function(d, sv, sl) d[split_var == sv & split_level == sl]$metric_value

test_that("support_n_forms telt de groepen in een combinatieniveau", {
  expect_equal(support_n_forms(ALLE_NIVEAUS), c(0L, 1L, 1L, 1L, 2L, 2L, 2L, 3L))
})

test_that("een complete slice levert beide uitsplitsingen, sluitend op het totaal", {
  out <- derive_support_split_rows(maak_slice(WAARDEN, 1000))

  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "geen"), 600)
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)

  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "0"), 600)
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "1"), 250)   # 100 + 80 + 70
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "2"), 120)   # 50 + 40 + 30
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "3"), 30)

  # De twee uitsplitsingen beschrijven dezelfde populatie.
  expect_equal(sum(out[split_var == SUPPORT_SPLIT_SIGNAL]$metric_value),
               sum(out[split_var == SUPPORT_SPLIT_COUNT]$metric_value))
})

test_that("'wel' komt uit de totaalrij, niet uit de som van de 7 niveaus", {
  # Twee paren onderdrukt: de som van de zichtbare niveaus is 330, maar het
  # echte aantal met ondersteuning is 400. Het verschil met de totaalrij vangt
  # de onderdrukte cellen op; een som zou ze als nul meetellen.
  slice <- maak_slice(WAARDEN, 1000,
                      niveaus = setdiff(ALLE_NIVEAUS, c("O_MPG1 + O_MPG3", "O_MPG2 + O_MPG3")))
  out <- derive_support_split_rows(slice)
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)
})

test_that("een onvolledige groepsgrootte levert geen rij in plaats van een te laag getal", {
  slice <- maak_slice(WAARDEN, 1000, niveaus = setdiff(ALLE_NIVEAUS, "O_MPG2"))
  out <- derive_support_split_rows(slice)

  expect_length(niveau(out, SUPPORT_SPLIT_COUNT, "1"), 0)   # 1 van de 3 mist
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "2"), 120)  # paren zijn compleet
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "3"), 30)
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)
})

test_that("zonder none-rij is noch 'geen' noch 'wel' af te leiden", {
  out <- derive_support_split_rows(maak_slice(WAARDEN, 1000,
                                              niveaus = setdiff(ALLE_NIVEAUS, "none")))
  expect_length(niveau(out, SUPPORT_SPLIT_SIGNAL, "geen"), 0)
  expect_length(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 0)
  expect_length(niveau(out, SUPPORT_SPLIT_COUNT, "0"), 0)
})

test_that("zonder totaalrij is 'wel' niet af te leiden, 'geen' wel", {
  slice <- maak_slice(WAARDEN, 1000)
  out <- derive_support_split_rows(slice[split_var != "(totaal)"])
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "geen"), 600)
  expect_length(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 0)
})

test_that("een afgeleid 'wel' onder de CBS-drempel valt af", {
  # Totaal 600, none 600: het verschil is 0 -- geen rij, geen nul op de kaart.
  out <- derive_support_split_rows(maak_slice(WAARDEN, 600))
  expect_length(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 0)

  # Afronding op tientallen kan het verschil negatief maken; ook dat valt af.
  out <- derive_support_split_rows(maak_slice(WAARDEN, 590))
  expect_length(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 0)
})

test_that("de indicatorvorm telt over de risicowaarden en gebruikt de hele populatie als noemer", {
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1"))
  out <- add_support_derivations(dt)

  ind <- out[variable_name == "O_MPG_ondersteuning"]
  expect_setequal(ind$variable_value, c("geen", "wel"))
  expect_equal(ind[variable_value == "geen"]$metric_value, 1200)  # 2 x 600
  expect_equal(ind[variable_value == "wel"]$metric_value, 800)    # 2 x 400
  # Een indicator staat op de totaalrij: hij kruist niet met een splitsing.
  expect_true(all(ind$split_var == SUPPORT_TOTAL_LABEL))

  aantal <- out[variable_name == "O_MPG_aantal_vormen"]
  expect_setequal(aantal$variable_value, c("0", "1", "2", "3"))
  expect_equal(sum(aantal$metric_value), 2000)
})

test_that("een indicator verschijnt alleen als zijn hele partitie er is", {
  # Bij variable_value "1" is een losse groep onderdrukt, dus "1 vorm" ontbreekt
  # daar. Dan is de som over de risicowaarden onvolledig en valt de hele
  # aantal-vormen-indicator weg -- anders zou het percentage te hoog uitvallen.
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1",
                         niveaus = setdiff(ALLE_NIVEAUS, "O_MPG2")))
  out <- add_support_derivations(dt)

  expect_equal(nrow(out[variable_name == "O_MPG_aantal_vormen"]), 0)
  # Het signaal staat los en blijft wel compleet.
  expect_equal(nrow(out[variable_name == "O_MPG_ondersteuning"]), 2)
})

test_that("de bron valt terug op een losse risicoscore als de cumulatieve incompleet is", {
  # De cumulatieve score mist bij waarde "3plus" zijn none-rij, dus zijn reeks
  # is niet compleet. De binaire score is dat wel en neemt het over -- dezelfde
  # populatie, alleen anders ingedeeld.
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1"),
              maak_slice(WAARDEN, 1000, variable_value = "3plus",
                         niveaus = setdiff(ALLE_NIVEAUS, "none")),
              maak_slice(WAARDEN, 1000, variable_value = "0", variable_name = "R_MPG1_armoede_hh"),
              maak_slice(WAARDEN, 1000, variable_value = "1", variable_name = "R_MPG1_armoede_hh"))
  out <- add_support_derivations(dt)

  ind <- out[variable_name == "O_MPG_ondersteuning"]
  expect_setequal(ind$variable_value, c("geen", "wel"))
  expect_equal(ind[variable_value == "geen"]$metric_value, 1200)  # 2 x 600, uit R_MPG1
  expect_equal(ind[variable_value == "wel"]$metric_value, 800)
})

test_that("zonder enige complete bron komt er geen indicator", {
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1",
                         niveaus = setdiff(ALLE_NIVEAUS, "none")))
  out <- add_support_derivations(dt)
  expect_equal(nrow(out[variable_name %like% "^O_"]), 0)
})

test_that("de cumulatieve score gaat voor als meerdere bronnen compleet zijn", {
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1"),
              maak_slice(WAARDEN, 1000, variable_value = "0", variable_name = "R_MPG1_armoede_hh"),
              maak_slice(WAARDEN, 1000, variable_value = "1", variable_name = "R_MPG1_armoede_hh"))
  out <- add_support_derivations(dt)

  # Twee losse risicoscores zouden de populatie dubbel tellen.
  expect_equal(out[variable_name == "O_MPG_ondersteuning" & variable_value == "wel"]$metric_value, 800)
  # De splitsvorm bestaat wel voor elke risicoscore -- dat is juist de kruising
  # die gevraagd is.
  expect_setequal(out[split_var == SUPPORT_SPLIT_SIGNAL]$variable_name,
                  c("R_MPG_totaal", "R_MPG1_armoede_hh"))
})

test_that("add_support_derivations is idempotent", {
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1"))
  een  <- add_support_derivations(dt)
  twee <- add_support_derivations(copy(een))
  expect_equal(nrow(een), nrow(twee))
  expect_equal(sum(een$metric_value), sum(twee$metric_value))
})

test_that("de originele rijen blijven ongemoeid", {
  dt <- maak_slice(WAARDEN, 1000)
  out <- add_support_derivations(copy(dt))
  origineel <- out[split_var %in% c("(totaal)", "O_MPG_combination") &
                   variable_name == "R_MPG_totaal"]
  expect_equal(nrow(origineel), nrow(dt))
  expect_equal(sum(origineel$metric_value), sum(dt$metric_value))
})

test_that("ouderen gebruiken hun eigen combinatie- en indicatornamen", {
  dt <- maak_slice(WAARDEN, 1000)
  dt[, `:=`(population = "ouderen (65+)", variable_name = "R_OUD_totaal",
            metric_name = "n_ouderen_with_var_value")]
  dt[split_var == "O_MPG_combination", split_var := "O_OUD_combination"]
  dt[, split_level := gsub("O_MPG", "O_OUD", split_level)]

  out <- add_support_derivations(dt)
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)
  expect_true("O_OUD_ondersteuning" %in% out$variable_name)
  expect_false("O_MPG_ondersteuning" %in% out$variable_name)
})
