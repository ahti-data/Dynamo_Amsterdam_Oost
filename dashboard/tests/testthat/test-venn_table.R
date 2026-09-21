# De venn in tabelvorm: dezelfde acht deelgebieden, maar met de hele
# risicoverdeling ernaast. Deze tests bewaken de twee dingen die hier mis
# kunnen gaan: een deelgebied dat in de figuur en in de tabel niet hetzelfde
# betekent, en een onderdrukte cel die als nul of als leeg leest.

CODES  <- c("O_MPG1", "O_MPG2", "O_MPG3")
LABELS <- c(O_MPG1 = "Jeugdhulp", O_MPG2 = "Psychosociale zorg",
            O_MPG3 = "Sociaaleconomische ondersteuning")
KEYS <- c("none", "A", "B", "C", "AB", "AC", "BC", "ABC")

mk_matrix <- function(waarden = c("0", "1", "2", "3plus")) {
  matrix(seq_len(length(KEYS) * length(waarden)) * 1.5,
         nrow = length(KEYS), dimnames = list(KEYS, waarden))
}
cellen <- function(html) regmatches(html, gregexpr("<td[^>]*>.*?</td>", html))[[1]]

test_that("venn_levels geeft de 8 deelgebieden onder de sleutels die venn_svg gebruikt", {
  lev <- venn_levels(CODES)
  expect_equal(names(lev), KEYS)
  expect_equal(unname(lev), c("none", "O_MPG1", "O_MPG2", "O_MPG3",
                              "O_MPG1 + O_MPG2", "O_MPG1 + O_MPG3", "O_MPG2 + O_MPG3",
                              "O_MPG1 + O_MPG2 + O_MPG3"))
  # De figuur tekent vals[names] -- die twee moeten dezelfde sleutels delen,
  # anders belandt een niveau in het verkeerde vakje.
  expect_silent(venn_svg(setNames(rep(1, 8), names(lev)), "rel", CODES, LABELS))
})

test_that("venn_levels laat zich niet door een genaamde codevector van de wijs brengen", {
  # names(COMBO_GROUP_LABELS[[pop]]) is genaamd noch ongenaamd gegarandeerd.
  expect_equal(venn_levels(setNames(CODES, CODES)), venn_levels(CODES))
})

test_that("de rijlabels zijn dezelfde groepsnamen als de tooltips in de figuur", {
  lab <- venn_region_labels(CODES, LABELS)
  expect_equal(names(lab), KEYS)
  expect_equal(unname(lab[["AB"]]), "Jeugdhulp + Psychosociale zorg")
  expect_equal(unname(lab[["ABC"]]),
               "Jeugdhulp + Psychosociale zorg + Sociaaleconomische ondersteuning")
  expect_equal(unname(lab[["none"]]), "Geen ondersteuningssignaal")
})

test_that("de tabel heeft een rij per deelgebied en een kolom per risicowaarde", {
  m <- mk_matrix()
  html <- venn_matrix_html(m, rep(100, 8), "abs", CODES, LABELS)
  expect_equal(length(gregexpr("<tr", html)[[1]]), 2 + 8)        # 2 kopregels
  expect_equal(length(cellen(html)), 8 * (1 + 4 + 1))            # groep + waarden + n
  for (lab in venn_region_labels(CODES, LABELS)) expect_true(grepl(lab, html, fixed = TRUE))
})

test_that("een onderdrukte cel wordt nooit een nul", {
  m <- mk_matrix(); m["AB", "2"] <- NA
  html <- venn_matrix_html(m, rep(100, 8), "abs", CODES, LABELS)
  expect_true(grepl(VENN_SUPPRESSED_MARK, html, fixed = TRUE))
  expect_true(grepl('title="onvoldoende waarnemingen"', html, fixed = TRUE))
  # geen enkele cel die alleen "0" bevat
  expect_false(any(grepl("^<td[^>]*>0</td>$", cellen(html))))
})

test_that("een onbekende n wordt ook onderdrukt weergegeven, niet leeg", {
  n <- rep(100, 8); n[3] <- NA
  html <- venn_matrix_html(mk_matrix(), n, "abs", CODES, LABELS)
  expect_false(any(grepl("^<td[^>]*></td>$", cellen(html))))
  expect_equal(length(gregexpr("venn-tab-na", html)[[1]]), 1)
})

test_that("weergave bepaalt de opmaak, maar n blijft altijd een aantal", {
  m <- matrix(12.34, nrow = 8, ncol = 1, dimnames = list(KEYS, "1"))
  rel <- venn_matrix_html(m, rep(4321, 8), "rel", CODES, LABELS)
  abs <- venn_matrix_html(m, rep(4321, 8), "abs", CODES, LABELS)
  # Komma, niet punt: het is een Nederlandse tabel en de aantallen ernaast
  # gebruiken hem ook.
  expect_true(grepl("12,3%", rel, fixed = TRUE))
  expect_false(grepl("12,3%", abs, fixed = TRUE))
  # de noemer is een aantal, ook in de procentweergave
  for (html in list(rel, abs)) expect_true(grepl("4.321", html, fixed = TRUE))
})

test_that("de none-rij is als zodanig gemarkeerd, net als in de figuur", {
  html <- venn_matrix_html(mk_matrix(), rep(100, 8), "abs", CODES, LABELS)
  expect_equal(length(gregexpr("venn-tab-none", html)[[1]]), 1)
  # ... en staat bovenaan, in dezelfde volgorde als venn_levels()
  expect_lt(regexpr("Geen ondersteuningssignaal", html), regexpr("Jeugdhulp<", html))
})

test_that("labels worden ge-escaped", {
  labs <- c(O_MPG1 = "Jeugd & gezin", O_MPG2 = "GGZ", O_MPG3 = "<b>Werk</b>")
  html <- venn_matrix_html(mk_matrix(), rep(100, 8), "abs", CODES, labs,
                           var_label = "Score & stapeling")
  expect_true(grepl("Jeugd &amp; gezin", html, fixed = TRUE))
  expect_true(grepl("&lt;b&gt;Werk&lt;/b&gt;", html, fixed = TRUE))
  expect_true(grepl("Score &amp; stapeling", html, fixed = TRUE))
  expect_false(grepl("<b>Werk", html, fixed = TRUE))
})

test_that("een matrix met de verkeerde rijen wordt geweigerd", {
  m <- mk_matrix()
  expect_error(venn_matrix_html(m[-1, ], rep(100, 7), "abs", CODES, LABELS))
  expect_error(venn_matrix_html(m[8:1, ], rep(100, 8), "abs", CODES, LABELS))
  expect_error(venn_matrix_html(m, rep(100, 7), "abs", CODES, LABELS))
})

# De risicofactor-tabel gebruikt dezelfde renderer met andere kolommen: korte
# codes in de kop (R1, R2, ...) en de volledige omschrijving als hover-title,
# want negen omschrijvingen passen niet in negen kolomkoppen.

test_that("kolomkoppen en hover-titels zijn los in te stellen", {
  m <- matrix(1, nrow = 8, ncol = 2,
              dimnames = list(KEYS, c("R_MPG1_armoede_hh", "R_MPG2_laagopl_hh")))
  html <- venn_matrix_html(m, rep(100, 8), "rel", CODES, LABELS,
                           var_label = "Risicofactor",
                           kolomlabels = c("R1", "R2"),
                           kolomtitels = c("Armoede", "Laag opleidingsniveau"),
                           n_label = "populatie")
  expect_true(grepl(">R1</th>", html, fixed = TRUE))
  expect_true(grepl('title="Armoede"', html, fixed = TRUE))
  expect_true(grepl(">populatie</th>", html, fixed = TRUE))
  # de ruwe kolomnaam hoort niet in de kop te staan
  expect_false(grepl("R_MPG1_armoede_hh", html, fixed = TRUE))
})

test_that("kolomlabels en -titels moeten bij de matrix passen", {
  m <- matrix(1, nrow = 8, ncol = 2, dimnames = list(KEYS, c("a", "b")))
  expect_error(venn_matrix_html(m, rep(100, 8), "rel", CODES, LABELS, kolomlabels = "R1"))
  expect_error(venn_matrix_html(m, rep(100, 8), "rel", CODES, LABELS,
                                kolomtitels = c("een", "twee", "drie")))
})

test_that("zonder hover-titels komt er geen leeg title-attribuut", {
  m <- matrix(1, nrow = 8, ncol = 1, dimnames = list(KEYS, "1"))
  html <- venn_matrix_html(m, rep(100, 8), "rel", CODES, LABELS)
  expect_false(grepl('title=""', html, fixed = TRUE))
})

# ------------------------------------------------------- generieke kruistabel --

# venn_matrix_html() is sinds de ondersteuningsvormen-tabel een dunne laag over
# kruistabel_html(): dezelfde opmaak, andere rijen. Deze tests bewaken het
# generieke deel -- de venn-specifieke tests hierboven dekken de laag erover.

test_that("kruistabel_html zet rijen, kolommen en de n-kolom neer", {
  m <- matrix(c(40, 130, 370, 740), nrow = 2, byrow = TRUE,
              dimnames = list(c("3", "2"), c("0", "3plus")))
  h <- kruistabel_html(m, n = c(250, 1460), weergave = "abs",
                       rij_labels = c("Alle 3 de vormen", "2 vormen"),
                       groep_label = "Aantal vormen ondersteuning")
  expect_true(grepl("Aantal vormen ondersteuning", h, fixed = TRUE))
  expect_true(grepl("Alle 3 de vormen", h, fixed = TRUE))
  expect_true(grepl(">130<", h, fixed = TRUE))
  expect_true(grepl("1.460", h, fixed = TRUE))   # n, met duizendscheiding
})

test_that("zonder n-vector blijft de n-kolom weg", {
  m <- matrix(10, nrow = 1, dimnames = list("0", "1"))
  h <- kruistabel_html(m, n = NULL, weergave = "abs", rij_labels = "Geen",
                       groep_label = "Groep")
  # Let op de volledige klassenaam: "venn-tab-n" zit ook in "venn-tab-num",
  # en dan slaagt de test terwijl de kolom er gewoon staat.
  expect_false(grepl('class="venn-tab-n"', h, fixed = TRUE))
})

test_that("het aandeel komt achter het aantal te staan", {
  # De vorm uit de tabel die hiervoor gevraagd werd: "300 (2,0%)".
  m <- matrix(300, nrow = 1, dimnames = list("0", "3plus"))
  h <- kruistabel_html(m, n = 300, weergave = "abs", rij_labels = "Geen signaal",
                       groep_label = "Groep", aandeel = matrix(2.0, nrow = 1))
  expect_true(grepl("300", h, fixed = TRUE))
  expect_true(grepl("(2,0%)", h, fixed = TRUE))
})

test_that("een onderdrukte cel blijft een streepje, ook met een aandeel erbij", {
  # Nooit een nul, en ook geen "0,0%" achter een cel die niet bestaat.
  m <- matrix(NA_real_, nrow = 1, dimnames = list("0", "3plus"))
  h <- kruistabel_html(m, n = 100, weergave = "abs", rij_labels = "Geen signaal",
                       groep_label = "Groep", aandeel = matrix(NA_real_, nrow = 1))
  expect_true(grepl("onvoldoende waarnemingen", h, fixed = TRUE))
  expect_false(grepl("%)", h, fixed = TRUE))
})

test_that("de venn-tabel gedraagt zich nog als vanouds", {
  # De acht deelgebieden in de volgorde van venn_levels(), en de none-rij met
  # zijn eigen klasse -- dat mag door de generieke laag niet verschoven zijn.
  codes <- c("O_MPG1", "O_MPG2", "O_MPG3")
  keys  <- names(venn_levels(codes))
  m <- matrix(10, nrow = 8, ncol = 1, dimnames = list(keys, "1"))
  h <- venn_matrix_html(m, n = rep(100, 8), weergave = "abs",
                        group_codes = codes,
                        group_labels = setNames(c("A", "B", "C"), codes))
  expect_true(grepl("venn-tab-none", h, fixed = TRUE))
  expect_true(grepl("Ondersteuningscombinatie", h, fixed = TRUE))
})
