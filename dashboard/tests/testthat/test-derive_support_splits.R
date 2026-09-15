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

test_that("een onvolledige groepsgrootte wordt uit het complement gehaald", {
  # Een van de drie losse groepen is onderdrukt, dus "1 vorm" is niet op te
  # tellen. Maar 1 + 2 + 3 vormen samen zijn "wel", dus met de paren en de
  # drievoudige erbij is "1 vorm" alsnog exact: 400 - 120 - 30 = 250.
  slice <- maak_slice(WAARDEN, 1000, niveaus = setdiff(ALLE_NIVEAUS, "O_MPG2"))
  out <- derive_support_split_rows(slice)

  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "1"), 250)
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "2"), 120)
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "3"), 30)
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)
})

test_that("het complement slaat niet op zichzelf terug", {
  # Zowel een losse groep als een paar is onderdrukt: dan is noch "1 vorm" noch
  # "2 vormen" te bepalen, en mag geen van beide uit de ander volgen.
  slice <- maak_slice(WAARDEN, 1000,
                      niveaus = setdiff(ALLE_NIVEAUS, c("O_MPG2", "O_MPG1 + O_MPG2")))
  out <- derive_support_split_rows(slice)

  expect_length(niveau(out, SUPPORT_SPLIT_COUNT, "1"), 0)
  expect_length(niveau(out, SUPPORT_SPLIT_COUNT, "2"), 0)
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "3"), 30)
  expect_equal(niveau(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)
})

test_that("zonder totaalrij is er geen complement, want 'wel' is dan onbekend", {
  slice <- maak_slice(WAARDEN, 1000, niveaus = setdiff(ALLE_NIVEAUS, "O_MPG2"))
  out <- derive_support_split_rows(slice[split_var != "(totaal)"])
  expect_length(niveau(out, SUPPORT_SPLIT_COUNT, "1"), 0)
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

test_that("een onderdrukte losse groep haalt de indicator niet onderuit", {
  # Bij variable_value "1" is O_MPG2 onderdrukt, dus dat niveautotaal is niet
  # exact op te tellen en valt "1 vorm" niet direct te bepalen. Via het
  # complement wel: de vier categorieen komen precies op de populatie uit.
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1",
                         niveaus = setdiff(ALLE_NIVEAUS, "O_MPG2")))
  out <- add_support_derivations(dt)

  aantal <- out[variable_name == "O_MPG_aantal_vormen"]
  expect_equal(aantal[variable_value == "0"]$metric_value, 1200)
  expect_equal(aantal[variable_value == "1"]$metric_value, 500)   # 200 + 160 + 140
  expect_equal(aantal[variable_value == "2"]$metric_value, 240)
  expect_equal(aantal[variable_value == "3"]$metric_value, 60)
  expect_equal(sum(aantal$metric_value), 2000)                    # de hele populatie
})

test_that("de indicator valt weg zodra geen enkele route sluit", {
  # Nu is er bij waarde "1" zowel een losse groep als een paar onderdrukt: dan
  # is noch "1 vorm" noch "2 vormen" te bepalen, en verschijnt de hele
  # aantal-vormen-indicator niet -- een halve partitie zou het percentage te
  # hoog maken.
  dt <- rbind(maak_slice(WAARDEN, 1000, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "1",
                         niveaus = setdiff(ALLE_NIVEAUS, c("O_MPG2", "O_MPG1 + O_MPG2"))))
  out <- add_support_derivations(dt)

  expect_equal(nrow(out[variable_name == "O_MPG_aantal_vormen"]), 0)
  # Het signaal hangt alleen aan de none-rij en blijft wel staan.
  expect_equal(nrow(out[variable_name == "O_MPG_ondersteuning"]), 2)
})

test_that("een bron met een categorie in deze regio is bruikbaar, niet verdacht", {
  # Zoals R_MPG1_armoede_hh in Geuzenveld: maar een waarde, die in zijn eentje
  # de hele populatie telt. Geen kruising, dus geen onderdrukking in de
  # niveaurijen -- dat is de beste bron die er is. Een toets op "landelijk twee
  # categorieen, hier een" zou hem juist weggooien.
  dt <- maak_slice(WAARDEN, 1000, variable_value = "0", variable_name = "R_MPG1_armoede_hh")
  out <- add_support_derivations(dt)

  ind <- out[variable_name == "O_MPG_ondersteuning"]
  expect_equal(ind[variable_value == "geen"]$metric_value, 600)
  expect_equal(ind[variable_value == "wel"]$metric_value, 400)

  aantal <- out[variable_name == "O_MPG_aantal_vormen"]
  expect_setequal(aantal$variable_value, c("0", "1", "2", "3"))
  expect_equal(aantal[variable_value == "1"]$metric_value, 250)
})

test_that("een bron die zijn eigen regiototaal niet haalt telt niet mee", {
  # R_MPG_totaal mist hier waarde "3plus" helemaal: zijn totaalrijen tellen op
  # tot 900 terwijl de regio er 1000 heeft. Zo'n bron mist een categorie en zou
  # elk niveautotaal te laag maken.
  dt <- rbind(maak_slice(WAARDEN, 900, variable_value = "0"),
              maak_slice(WAARDEN, 1000, variable_value = "0",
                         variable_name = "R_MPG1_armoede_hh"))
  dt[variable_name == "R_MPG_totaal" & split_var == "(totaal)", metric_value := 900]
  out <- add_support_derivations(dt)

  # De complete bron bepaalt het cijfer, niet de incomplete.
  expect_equal(out[variable_name == "O_MPG_ondersteuning" & variable_value == "wel"]$metric_value, 400)
})

test_that("zonder none-rij is er geen signaalindicator", {
  dt <- maak_slice(WAARDEN, 1000, variable_value = "0",
                   niveaus = setdiff(ALLE_NIVEAUS, "none"))
  out <- add_support_derivations(dt)
  expect_equal(nrow(out[variable_name == "O_MPG_ondersteuning"]), 0)
})

test_that("bruikbare bronnen geven hetzelfde antwoord", {
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
