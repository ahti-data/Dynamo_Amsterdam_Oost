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
  expect_true(grepl("12.3%", rel, fixed = TRUE))
  expect_false(grepl("12.3%", abs, fixed = TRUE))
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
