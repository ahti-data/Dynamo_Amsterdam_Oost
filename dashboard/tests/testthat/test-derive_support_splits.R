# data-prep/derive_support_splits.R leidt twee uitsplitsingen af die niet als
# kolom in de CBS-levering zitten. Deze tests bewaken twee dingen:
#
#   - de onderdrukkingsregel: een som over combinatieniveaus mag een ontbrekende
#     (= onderdrukte) cel nooit als nul meetellen, dus komt er dan geen rij;
#   - wat levering output_1b veranderde: de omvang van elk combinatieniveau
#     staat nu als `n_split` in de data, dus hoeft die niet meer teruggerekend te
#     worden uit de som over de risicowaarden.

CODES <- c("O_MPG1", "O_MPG2", "O_MPG3")
ALLE_NIVEAUS <- c("none", CODES,
                  "O_MPG1 + O_MPG2", "O_MPG1 + O_MPG3", "O_MPG2 + O_MPG3",
                  "O_MPG1 + O_MPG2 + O_MPG3")

# Een slice zoals de levering hem aanlevert: per variable_value een totaalrij
# plus de 8 combinatieniveaus. `niveaus` laat weg wat onderdrukt is.
#
# `groottes` is de gepubliceerde omvang van elk combinatieniveau
# (n_totaal_region_split): die hangt niet van de risicowaarde af, dus in een
# fixture met twee risicowaarden is hij het dubbele van de celwaarden.
maak_slice <- function(waarden, totaal, variable_value = "1",
                       variable_name = "R_MPG_totaal",
                       niveaus = ALLE_NIVEAUS, region_code = "0363AA",
                       metric_name = "n_households",
                       groottes = waarden, n_totaal = sum(groottes)) {
  vast <- list(population = "huishoudens met kinderen", region_level = "wijk",
               region_code = region_code, region_name = "Testwijk",
               stadsdeel = "Oost", year = 2024L, variable_name = variable_name,
               variable_value = variable_value, metric_name = metric_name,
               n_totaal = n_totaal)
  combo <- data.table::as.data.table(c(vast, list(
    metric_value = unname(waarden[niveaus]), n_split = unname(groottes[niveaus]),
    split_var = "O_MPG_combination", split_level = niveaus)))
  tot <- data.table::as.data.table(c(vast, list(
    metric_value = totaal, n_split = n_totaal,
    split_var = "(totaal)", split_level = "(totaal)")))
  rbind(tot, combo)
}

# 8 niveaus die samen precies op 1000 uitkomen.
WAARDEN <- c(none = 600, O_MPG1 = 100, O_MPG2 = 80, O_MPG3 = 70,
             "O_MPG1 + O_MPG2" = 50, "O_MPG1 + O_MPG3" = 40,
             "O_MPG2 + O_MPG3" = 30, "O_MPG1 + O_MPG2 + O_MPG3" = 30)
GROOTTES <- WAARDEN * 2   # twee risicowaarden samen

# Twee risicowaarden naast elkaar: samen de hele populatie van 2000.
maak_twee <- function(niveaus_0 = ALLE_NIVEAUS, niveaus_1 = ALLE_NIVEAUS,
                      groottes = GROOTTES, metric_name = "n_households") {
  rbind(
    maak_slice(WAARDEN, 1000, variable_value = "0", niveaus = niveaus_0,
               groottes = groottes, n_totaal = 2000, metric_name = metric_name),
    maak_slice(WAARDEN, 1000, variable_value = "1", niveaus = niveaus_1,
               groottes = groottes, n_totaal = 2000, metric_name = metric_name))
}

niveau <- function(d, sv, sl) d[split_var == sv & split_level == sl]$metric_value
omvang <- function(d, sv, sl) d[split_var == sv & split_level == sl]$n_split

test_that("support_n_forms telt de groepen in een combinatieniveau", {
  expect_equal(support_n_forms(ALLE_NIVEAUS), c(0L, 1L, 1L, 1L, 2L, 2L, 2L, 3L))
})

# ---------------------------------------------------------------- splitsvorm --

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

test_that("de afgeleide splitsrijen dragen de gepubliceerde groepsomvang", {
  out <- derive_support_split_rows(maak_slice(WAARDEN, 1000))
  # Niet de som van de cellen in deze slice, maar de omvang van de groep zelf.
  expect_equal(omvang(out, SUPPORT_SPLIT_SIGNAL, "geen"), 600)
  expect_equal(omvang(out, SUPPORT_SPLIT_SIGNAL, "wel"), 400)
  expect_equal(omvang(out, SUPPORT_SPLIT_COUNT, "1"), 250)
})

test_that("de groepsomvang blijft exact als een risicocel onderdrukt is", {
  # Bij waarde "1" ontbreekt een paar, dus de celwaarde voor "2 vormen" is daar
  # niet op te tellen -- maar de omvang van die groep staat gewoon in de data en
  # blijft het volledige aantal, niet een som van wat toevallig gepubliceerd is.
  dt <- maak_twee(niveaus_1 = setdiff(ALLE_NIVEAUS, "O_MPG2 + O_MPG3"))
  out <- derive_support_split_rows(dt)
  expect_equal(unique(omvang(out, SUPPORT_SPLIT_COUNT, "2")), 240)   # 2 x 120
  expect_equal(unique(omvang(out, SUPPORT_SPLIT_SIGNAL, "wel")), 800)
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

# ------------------------------------------------- samengestelde uitsplitsing --

test_that("een kruising houdt zijn andere splitsvariabele", {
  # De combinatie gekruist met geslacht: de afleiding vervangt de combinatie en
  # laat het geslacht staan, met de sleutel in dezelfde volgorde als split_key().
  helft <- function(x) x / 2
  bouw <- function(g) {
    s <- maak_slice(helft(WAARDEN), 500, groottes = helft(WAARDEN), n_totaal = 500)
    s[split_var == "O_MPG_combination",
      `:=`(split_var = "O_MPG_combination | geslacht",
           split_level = paste(split_level, g, sep = SPLIT_SEP))]
    s[split_var == "(totaal)", `:=`(split_var = "geslacht", split_level = g)]
    s
  }
  dt <- rbind(bouw("man"), bouw("vrouw"))
  out <- derive_support_split_rows(dt)

  expect_setequal(unique(out$split_var),
                  c("aantal_ondersteuningsvormen | geslacht",
                    "geslacht | ondersteuningssignaal"))
  # De waarden staan in dezelfde volgorde als de namen in de sleutel.
  expect_equal(niveau(out, "aantal_ondersteuningsvormen | geslacht", "1 | man"), 125)
  expect_equal(niveau(out, "geslacht | ondersteuningssignaal", "man | wel"), 200)
  expect_equal(omvang(out, "geslacht | ondersteuningssignaal", "vrouw | geen"), 300)
})

# ------------------------------------------------------------- indicatorvorm --

test_that("de indicatorvorm komt uit de gepubliceerde groepsgroottes", {
  out <- add_support_derivations(maak_twee())

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

test_that("een enkele gepubliceerde risicowaarde is genoeg voor de indicator", {
  # Dit is de winst van output_1b. De oude route had een complete reeks
  # risicocategorieen nodig om een niveautotaal te kunnen optellen; n_split hangt
  # niet van de risicowaarde af, dus een enkele rij van dat niveau volstaat.
  dt <- maak_twee()
  dt <- dt[variable_value == "1" | split_var == "(totaal)"]
  out <- add_support_derivations(dt)

  ind <- out[variable_name == "O_MPG_ondersteuning"]
  expect_equal(ind[variable_value == "wel"]$metric_value, 800)
  expect_equal(ind[variable_value == "geen"]$metric_value, 1200)
})

test_that("een onderdrukte losse groep haalt de indicator niet onderuit", {
  # Bij variable_value "1" is O_MPG2 onderdrukt. Dat raakt de celwaarden, maar
  # niet de groepsgroottes: die staan er bij variable_value "0" gewoon.
  out <- add_support_derivations(maak_twee(niveaus_1 = setdiff(ALLE_NIVEAUS, "O_MPG2")))

  aantal <- out[variable_name == "O_MPG_aantal_vormen"]
  expect_equal(aantal[variable_value == "0"]$metric_value, 1200)
  expect_equal(aantal[variable_value == "1"]$metric_value, 500)   # 200 + 160 + 140
  expect_equal(aantal[variable_value == "2"]$metric_value, 240)
  expect_equal(aantal[variable_value == "3"]$metric_value, 60)
  expect_equal(sum(aantal$metric_value), 2000)                    # de hele populatie
})

test_that("wat niet toe te wijzen is wordt een eigen categorie, geen weggelaten slice", {
  # Een combinatieniveau dat in deze regio nergens voorkomt: dan is zijn omvang
  # onbekend en is "1 vorm" niet te bepalen. De categorieen die wel bekend zijn
  # blijven staan, en de rest komt als "onbekend" op tafel -- zo is de noemer nog
  # steeds de hele populatie en klopt elk percentage.
  zonder <- setdiff(ALLE_NIVEAUS, c("O_MPG2", "O_MPG1 + O_MPG2"))
  out <- add_support_derivations(maak_twee(niveaus_0 = zonder, niveaus_1 = zonder))

  aantal <- out[variable_name == "O_MPG_aantal_vormen"]
  expect_true(SUPPORT_UNKNOWN %in% aantal$variable_value)
  expect_equal(aantal[variable_value == "0"]$metric_value, 1200)
  expect_equal(aantal[variable_value == "3"]$metric_value, 60)
  # De categorieen tellen samen op tot de populatie, dus de noemer klopt.
  expect_equal(sum(aantal$metric_value), 2000)
  expect_equal(nrow(out[variable_name == "O_MPG_ondersteuning"]), 2)
})

test_that("de combinatie is ook als indicator beschikbaar, zonder risicoscore", {
  out <- add_support_derivations(maak_twee())

  comb <- out[variable_name == "O_MPG_combinatie"]
  expect_setequal(comb$variable_value, ALLE_NIVEAUS)     # geen restcategorie nodig
  expect_equal(comb[variable_value == "none"]$metric_value, 1200)
  expect_equal(comb[variable_value == "O_MPG1 + O_MPG2 + O_MPG3"]$metric_value, 60)
  expect_equal(sum(comb$metric_value), 2000)             # de hele populatie
  # Staat op de totaalrij: dit is een indicator, geen uitsplitsing.
  expect_true(all(comb$split_var == SUPPORT_TOTAL_LABEL))
})

test_that("twee risicoscores tellen de populatie niet dubbel", {
  dt <- rbind(maak_twee(),
              maak_twee()[, variable_name := "R_MPG1_armoede_hh"])
  out <- add_support_derivations(dt)

  expect_equal(out[variable_name == "O_MPG_ondersteuning" &
                   variable_value == "wel"]$metric_value, 800)
  # De splitsvorm bestaat wel voor elke risicoscore -- dat is juist de kruising
  # die gevraagd is.
  expect_setequal(out[split_var == SUPPORT_SPLIT_SIGNAL]$variable_name,
                  c("R_MPG_totaal", "R_MPG1_armoede_hh"))
})

test_that("zonder none-rij is er geen signaalindicator", {
  dt <- maak_slice(WAARDEN, 1000, variable_value = "0",
                   niveaus = setdiff(ALLE_NIVEAUS, "none"))
  out <- add_support_derivations(dt)
  expect_equal(nrow(out[variable_name == "O_MPG_ondersteuning"]), 0)
})

# ------------------------------------- terugrekenroute: metrics die geen
# ------------------------------------- populatie-eenheden tellen

test_that("een kindermetric wordt nog wel teruggerekend uit de categorieen", {
  # n_kinderen_hh telt kinderen, niet huishoudens, dus n_split is er de verkeerde
  # eenheid voor: daar blijft de som over de risicocategorieen de enige route.
  dt <- maak_twee(metric_name = "n_kinderen_hh")
  out <- add_support_derivations(dt)
  ind <- out[variable_name == "O_MPG_ondersteuning" & metric_name == "n_kinderen_hh"]
  expect_equal(ind[variable_value == "wel"]$metric_value, 800)
  # Zo'n rij kent zijn groepsomvang niet in de eenheid van deze metric.
  expect_true(all(is.na(ind$n_split)))
})

test_that("een bron die zijn eigen regiototaal niet haalt telt niet mee", {
  # Alleen nog van belang op de terugrekenroute. R_MPG_totaal mist hier een
  # categorie: zijn totaalrijen tellen op tot 900 terwijl de regio er 1000 heeft.
  dt <- rbind(
    maak_slice(WAARDEN, 900, variable_value = "0", metric_name = "n_kinderen_hh"),
    maak_slice(WAARDEN, 1000, variable_value = "0", metric_name = "n_kinderen_hh",
               variable_name = "R_MPG1_armoede_hh"))
  dt[variable_name == "R_MPG_totaal" & split_var == "(totaal)", metric_value := 900]
  out <- add_support_derivations(dt)

  # De complete bron bepaalt het cijfer, niet de incomplete.
  expect_equal(out[variable_name == "O_MPG_ondersteuning" &
                   variable_value == "wel"]$metric_value, 400)
})

# ------------------------------------------------------------------ overig --

test_that("zonder n_split-kolom stopt de afleiding met een leesbare melding", {
  dt <- maak_slice(WAARDEN, 1000)
  dt[, n_split := NULL]
  expect_error(add_support_derivations(dt), "n_split", fixed = TRUE)
})

test_that("een uitsplitsing die de levering zelf publiceert wordt niet afgeleid", {
  dt <- maak_slice(WAARDEN, 1000)
  eigen <- copy(dt[split_var == "O_MPG_combination"])[
    , `:=`(split_var = SUPPORT_SPLIT_COUNT, split_level = "1", metric_value = 7)]
  out <- add_support_derivations(rbind(dt, eigen[1]))
  expect_equal(niveau(out, SUPPORT_SPLIT_COUNT, "1"), 7)          # die van de levering
  expect_false("O_MPG_ondersteuning" %in% out$variable_name)      # en verder niets afgeleid
})

test_that("add_support_derivations is idempotent", {
  dt   <- maak_twee()
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
