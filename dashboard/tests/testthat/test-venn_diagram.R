# utils/venn_diagram.R builds SVG by hand, so these tests are mostly about the
# document staying well-formed and about the two CBS rules the figure has to
# keep: a suppressed region is never drawn as a zero, and it never takes a
# colour off the scale.

VALS <- c(none = 61.4, A = 12.3, B = 8.1, C = 9.4,
          AB = 3.2, AC = 2.6, BC = 1.9, ABC = 1.1)
CODES  <- c("O_MPG1", "O_MPG2", "O_MPG3")
LABELS <- c(O_MPG1 = "Jeugdhulp", O_MPG2 = "Psychosociale zorg",
            O_MPG3 = "Sociaaleconomische ondersteuning")

# <title>-keyed fills, so a region can be identified by what it means rather
# than by its position in the string.
region_fills <- function(svg) {
  m <- regmatches(svg, gregexpr('<rect[^>]*/?>\\s*<title>[^<]*</title>', svg))[[1]]
  fills <- sub('.*fill="([^"]*)".*', "\\1", m)
  names(fills) <- sub('.*<title>([^:]*):.*', "\\1", m)
  fills
}

test_that("the 8 region names are required", {
  expect_error(venn_svg(VALS[-1], "rel", CODES, LABELS))
  expect_error(venn_svg(VALS, "rel", CODES[-1], LABELS))
})

test_that("every container tag is balanced and every id reference resolves", {
  # A cheap stand-in for a parser, so the check does not need a package the
  # rest of the suite has no other use for.
  for (standalone in c(FALSE, TRUE)) {
    svg <- venn_svg(VALS, "rel", CODES, LABELS, title = "T", caption = "C",
                    standalone = standalone)
    for (tag in c("svg", "defs", "g", "mask", "clipPath", "filter", "text", "title")) {
      opens  <- gregexpr(sprintf("<%s[ >]", tag), svg)[[1]]
      closes <- gregexpr(sprintf("</%s>", tag), svg)[[1]]
      expect_equal(sum(opens > 0), sum(closes > 0), info = tag)
    }
    # Every "&" must open an entity, or the file will not open as XML.
    expect_false(grepl("&(?!(amp|lt|gt|quot|apos|#[0-9]+);)", svg, perl = TRUE))
    ids  <- unique(regmatches(svg, gregexpr('(?<=id=")[^"]+', svg, perl = TRUE))[[1]])
    refs <- unique(regmatches(svg, gregexpr('(?<=url\\(#)[^)]+', svg, perl = TRUE))[[1]])
    expect_length(setdiff(refs, ids), 0)
  }
})

test_that("output parses as XML", {
  skip_if_not_installed("xml2")
  for (standalone in c(FALSE, TRUE)) {
    svg <- venn_svg(VALS, "rel", CODES, LABELS, title = "T", caption = "C",
                    standalone = standalone)
    expect_s3_class(xml2::read_xml(svg), "xml_document")
  }
})

test_that("output carries no non-ASCII byte", {
  # Shiny Server can run under a C locale, where a literal en dash in the
  # source is no longer one character; the suppression mark is an entity.
  svg <- venn_svg(c(VALS[1:7], ABC = NA_real_), "rel", CODES, LABELS)
  expect_false(grepl("[^\x01-\x7f]", svg))
  expect_true(grepl(VENN_SUPPRESSED_MARK, svg, fixed = TRUE))
})

test_that("ids are unique per call, so two figures can share a document", {
  a <- venn_svg(VALS, "rel", CODES, LABELS)
  b <- venn_svg(VALS, "rel", CODES, LABELS)
  ids <- function(s) unique(regmatches(s, gregexpr('(?<=id=")[^"]+', s, perl = TRUE))[[1]])
  expect_length(intersect(ids(a), ids(b)), 0)
})

test_that("text is XML-escaped", {
  svg <- venn_svg(VALS, "rel", CODES, c(O_MPG1 = "Wmo & Jeugd", O_MPG2 = "b", O_MPG3 = "c"),
                  title = "R & D <x>", standalone = TRUE)
  expect_match(svg, "Wmo &amp; Jeugd", fixed = TRUE)
  expect_match(svg, "R &amp; D &lt;x&gt;", fixed = TRUE)
})

test_that("a suppressed region is grey and says so, never a zero", {
  vals <- VALS
  vals[["AB"]] <- NA_real_
  svg <- venn_svg(vals, "rel", CODES, LABELS)
  fills <- region_fills(svg)
  expect_equal(unname(fills["Jeugdhulp + Psychosociale zorg"]), VENN_NA_FILL)
  expect_match(svg, "Jeugdhulp + Psychosociale zorg: onvoldoende waarnemingen", fixed = TRUE)
  expect_false(grepl(">0.0%<", svg, fixed = TRUE))
})

test_that("the none region is painted off the scale", {
  # It is nearly always the large majority; on the shared scale it pinned the
  # top of the ramp and flattened all seven circle regions.
  svg <- venn_svg(VALS, "rel", CODES, LABELS)
  fills <- region_fills(svg)
  expect_equal(unname(fills["Geen ondersteuningssignaal"]), VENN_NONE_FILL)
  expect_false(VENN_NONE_FILL %in% fills[names(fills) != "Geen ondersteuningssignaal"])
})

test_that("the scale spreads across the circle regions", {
  svg <- venn_svg(VALS, "rel", CODES, LABELS)
  circles <- region_fills(svg)[names(region_fills(svg)) != "Geen ondersteuningssignaal"]
  expect_gt(length(unique(circles)), 3)
  # Highest and lowest of the seven must not land in the same bin.
  expect_false(circles[["Jeugdhulp"]] ==
                 circles[["Jeugdhulp + Psychosociale zorg + Sociaaleconomische ondersteuning"]])
})

test_that("every offered palette renders, by key and by explicit ramp", {
  for (key in names(VENN_PALETTES)) {
    expect_match(venn_svg(VALS, "rel", CODES, LABELS, palette = key), "^<svg")
  }
  expect_match(venn_svg(VALS, "rel", CODES, LABELS,
                        palette = c("#ffffff", "#000000")), "^<svg")
})

test_that("all-suppressed renders a key but no scale", {
  vals <- setNames(rep(NA_real_, 8), names(VALS))
  svg <- venn_svg(vals, "rel", CODES, LABELS)
  expect_true(all(region_fills(svg) == VENN_NA_FILL))
  expect_match(svg, "onvoldoende waarnemingen (CBS-onderdrukking)", fixed = TRUE)
  expect_false(grepl("Aandeel (%)", svg, fixed = TRUE))  # no legend bar
})

test_that("one distinct value still produces a scale", {
  vals <- setNames(rep(5, 8), names(VALS))
  expect_match(venn_svg(vals, "rel", CODES, LABELS), "Aandeel (%)", fixed = TRUE)
})

test_that("weergave drives the number format and the legend unit", {
  rel <- venn_svg(VALS, "rel", CODES, LABELS)
  abs <- venn_svg(c(none = 18420, A = 3120, B = 2110, C = 2460,
                    AB = 820, AC = 640, BC = 470, ABC = 260),
                  "abs", CODES, LABELS)
  expect_match(rel, ">12.3%<", fixed = TRUE)
  expect_match(rel, "Aandeel (%)", fixed = TRUE)
  expect_match(abs, ">3.120<", fixed = TRUE)   # Dutch thousands separator
  expect_match(abs, ">Aantal<", fixed = TRUE)
})

test_that("standalone adds what a file needs and inline does not", {
  inline <- venn_svg(VALS, "rel", CODES, LABELS)
  file   <- venn_svg(VALS, "rel", CODES, LABELS, title = "Titel", caption = "Bron: x",
                     standalone = TRUE)
  expect_match(file, "^<\\?xml version")
  expect_match(file, '<svg viewBox="0 0 480 [0-9]+" width="480" height="[0-9]+"')
  expect_match(file, '<rect x="0" y="0" width="480" height="[0-9]+" fill="#ffffff"/>')
  expect_match(file, ">Titel<", fixed = TRUE)
  expect_match(file, "Bron: x", fixed = TRUE)
  expect_match(inline, "^<svg")
  expect_match(inline, "max-width:480px", fixed = TRUE)
  expect_false(grepl(">Titel<", inline, fixed = TRUE))
})

test_that("a long title wraps instead of running off the canvas", {
  long <- paste(rep("Risicostapeling naar ondersteuningscombinatie", 4), collapse = " | ")
  svg  <- venn_svg(VALS, "rel", CODES, LABELS, title = long, standalone = TRUE)
  n_lines <- length(regmatches(svg, gregexpr('font-size="13.5"', svg))[[1]])
  expect_gt(n_lines, 1)
  # Taller canvas than the same figure without a title.
  vb <- function(s) as.numeric(strsplit(sub('.*viewBox="([^"]*)".*', "\\1", s), " ")[[1]][4])
  expect_gt(vb(svg), vb(venn_svg(VALS, "rel", CODES, LABELS)))
})
