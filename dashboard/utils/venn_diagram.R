#' Static 3-circle Venn/Euler diagram as an inline SVG string, filled
#' choropleth-style by value for each of the 8 O_MPG_combination/
#' O_OUD_combination levels: "none" (dead space outside every circle, boxed in
#' as a rounded "universe" rect) plus the 7 overlap regions.
#'
#' Built with SVG clip-path (intersection: nest one clip-path group inside
#' another) and mask (subtraction: a black shape on a white mask knocks that
#' area out) rather than a plotting library -- there's no CRAN package for a
#' three-circle Venn that also supports independent per-region choropleth
#' fills and hover tooltips.
#'
#' One function renders both the on-screen figure and the file behind
#' "Download figuur (svg)": `standalone = TRUE` is what turns the fragment into
#' something that opens on its own (XML declaration, white background, a pixel
#' size instead of a CSS width), and `title`/`caption` are what make the
#' downloaded file readable away from the dashboard that produced it.

# Suppressed cells get their own neutral grey, never a colour from the scale,
# so "onvoldoende waarnemingen" can't be misread as a low value.
VENN_NA_FILL <- "#e0e0e0"

# "none" -- everything outside all three circles -- is deliberately painted off
# the scale, in a quiet neutral. It is nearly always the large majority (60-90%
# of a selection), and putting it on the shared scale pinned the top of the
# ramp to it and collapsed all seven circle regions, the part of the figure
# that actually carries signal, into one indistinguishable pale tint. Its
# number, caption and tooltip still report the value; only the fill is out of
# the comparison.
VENN_NONE_FILL <- "#EDF2F5"

VENN_FONT <- "'Segoe UI','Helvetica Neue',Helvetica,Arial,sans-serif"

# The short form of "onvoldoende waarnemingen", written as an XML numeric
# character reference rather than a literal en dash so the generated SVG holds
# no non-ASCII byte of its own. Shiny Server can run under a C locale, where an
# en dash in the source is no longer one character as far as R is concerned.
VENN_SUPPRESSED_MARK <- "&#8211;"

#' Colour scales offered for the venn fill, in the order the UI lists them.
#' Every value is something leaflet::colorNumeric() takes as `palette`: the
#' name of an RColorBrewer or viridis palette, or an explicit light -> dark
#' ramp to interpolate over the bins. The first entry is the default and is
#' the scale the choropleth on the Kaart tab uses, so the two figures stay
#' comparable unless the user deliberately switches.
#'
#' Every ramp starts well clear of VENN_NA_FILL -- a suppressed region has to
#' stay visibly distinct from the lightest real value, on any scale.
VENN_PALETTES <- list(
  "Geel-oranje-rood (als de kaart)"   = "YlOrRd",
  "ahti blauw"                        = c("#EAF6FC", "#009DDC", "#002737"),
  "ahti rood"                         = c("#FDECEA", "#EE3124", "#380C09"),
  "ahti groen"                        = c("#E7F7EF", "#00A55D", "#0C3A25"),
  "Blauw-groen"                       = "YlGnBu",
  "Viridis (kleurenblindvriendelijk)" = "viridis"
)

# Every id in the document gets this suffix. The figure is built once for the
# page and again for each download, and duplicate clip-path/mask ids would make
# two copies interfere if they ever landed in one document. A counter rather
# than sample(), so rendering a figure never disturbs the session's RNG state.
.venn_next_uid <- local({
  n <- 0L
  function() {
    n <<- n + 1L
    sprintf("v%d", n)
  }
})

# Text nodes carry label text from variable_labels.R and a user-visible title;
# an unescaped "&" alone is enough to make the downloaded .svg fail to open.
venn_esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

venn_has_text <- function(x) {
  !is.null(x) && length(x) > 0L && !is.na(x[1]) && nzchar(x[1])
}

# WCAG relative luminance, used to flip a value label to white where its region
# is dark. YlOrRd never got dark enough for this to matter; viridis and the
# ahti ramps do.
venn_luminance <- function(hex) {
  ch <- col2rgb(hex)[1:3, 1] / 255
  lin <- ifelse(ch <= 0.03928, ch / 12.92, ((ch + 0.055) / 1.055)^2.4)
  sum(c(0.2126, 0.7152, 0.0722) * lin)
}

#' @param vals Named numeric vector with exactly these 8 names: none, A, B,
#'   C, AB, AC, BC, ABC. NA renders as "onvoldoende waarnemingen" (same
#'   suppression convention as the map), shortened to VENN_SUPPRESSED_MARK in
#'   the region itself.
#' @param weergave "rel" (percentage) or "abs" (count) -- affects number
#'   formatting and the legend's unit caption.
#' @param group_codes Character vector of length 3, e.g.
#'   c("O_MPG1","O_MPG2","O_MPG3") -- the raw codes shown on the circles.
#' @param group_labels Named character vector (short names, same names as
#'   group_codes) used in hover tooltips -- see
#'   data/metadata/variable_labels.R.
#' @param palette A name from VENN_PALETTES, or anything colorNumeric() takes
#'   as a palette.
#' @param title Figure title, drawn above the diagram and wrapped over as many
#'   lines as it needs. NULL on screen, where the surrounding HTML already
#'   carries the title.
#' @param caption Small print under the legend (provenance, footnotes).
#' @param standalone TRUE for the download: XML declaration, white background
#'   and a fixed pixel size instead of a CSS width.
#' @param stroke_col Hex colour for circle/box outlines.
#' @return A single HTML/SVG string, ready for `HTML()`/`renderUI()` or for
#'   writing straight to a .svg file.
venn_svg <- function(vals, weergave, group_codes, group_labels,
                     palette = names(VENN_PALETTES)[1],
                     title = NULL, caption = NULL, standalone = FALSE,
                     stroke_col = ahti_branding$colors$grijs_blauw) {
  stopifnot(length(group_codes) == 3,
           setequal(names(vals), c("none", "A", "B", "C", "AB", "AC", "BC", "ABC")))

  uid   <- .venn_next_uid()
  ink   <- ahti_branding$colors$donker_grijs
  muted <- ahti_branding$colors$midden_grijs

  fmt <- function(v) {
    if (is.na(v)) "onvoldoende waarnemingen"
    else if (weergave == "rel") sprintf("%.1f%%", v)
    else format(round(v), big.mark = ".", decimal.mark = ",")
  }
  # Short form for the inline SVG label: some regions (the triple overlap
  # especially) are too small for the full suppression phrase, which would
  # otherwise overflow into neighbouring regions. The full phrase is still
  # the hover <title>. Returns XML rather than text -- the suppression mark is
  # an entity already.
  fmt_short_xml <- function(v) if (is.na(v)) VENN_SUPPRESSED_MARK else venn_esc(fmt(v))
  # Legend breaks come from pretty(), so they are round numbers already and
  # need none of fmt()'s one-decimal treatment.
  fmt_break <- function(v) {
    if (weergave == "rel") sprintf("%g%%", v)
    else format(round(v), big.mark = ".", decimal.mark = ",", trim = TRUE, scientific = FALSE)
  }

  # ---- colour scale --------------------------------------------------------
  # Binning is done here rather than handed to colorBin() so the legend
  # swatches and the region fills are provably the same colours, and so the
  # degenerate case (every region carrying the same value, one bin) stays a
  # normal code path instead of a factor palette with a single level.
  pal_spec <- if (is.character(palette) && length(palette) == 1L &&
                  palette %in% names(VENN_PALETTES)) {
    VENN_PALETTES[[palette]]
  } else {
    palette
  }

  scale_keys <- c("A", "B", "C", "AB", "AC", "BC", "ABC")
  ok <- vals[scale_keys][!is.na(vals[scale_keys])]
  if (length(ok) == 0) {
    breaks <- numeric(0)
    bin_cols <- character(0)
  } else {
    breaks <- unique(pretty(range(ok), 6))
    if (length(breaks) < 2) breaks <- c(min(ok) - 0.5, max(ok) + 0.5)
    nbin <- length(breaks) - 1L
    ramp <- colorNumeric(pal_spec, domain = c(0, 1))
    # One bin: take a mid-scale colour rather than the ramp's lightest end,
    # which would render the whole figure as near-white.
    bin_cols <- ramp(if (nbin == 1L) 0.6 else seq(0, 1, length.out = nbin))
  }

  fillcol <- function(key) {
    v <- vals[[key]]
    if (is.na(v)) return(VENN_NA_FILL)
    if (key == "none") return(VENN_NONE_FILL)
    if (length(bin_cols) == 0) return(VENN_NA_FILL)
    bin_cols[findInterval(v, breaks, rightmost.closed = TRUE, all.inside = TRUE)]
  }

  # ---- geometry ------------------------------------------------------------
  # Equilateral triangle layout: r=100, side=120 -- generous overlap, a
  # clearly visible (if small) triple-intersection region.
  Ax <- 180; Ay <- 160
  Bx <- 300; By <- 160
  Cx <- 240; Cy <- 263.9
  r  <- 100
  VBW <- 480; DIA_H <- 392

  # "Universe" box: comfortably contains the 3 circles. The dead space inside
  # this box but outside every circle is "none".
  Ux <- 45; Uy <- 35; Uw <- 390; Uh <- 345

  cA <- sprintf('cx="%g" cy="%g" r="%g"', Ax, Ay, r)
  cB <- sprintf('cx="%g" cy="%g" r="%g"', Bx, By, r)
  cC <- sprintf('cx="%g" cy="%g" r="%g"', Cx, Cy, r)

  # Hand-tuned centroids for this one fixed, known layout -- there is no
  # general formula worth writing for a diagram that never changes shape.
  lab <- list(
    none = c(88, 58),   A = c(133, 108), B = c(347, 108), C = c(240, 305),
    AB = c(240, 138),   AC = c(178, 232), BC = c(302, 232), ABC = c(240, 197)
  )
  name_lab <- list(
    A = c(Ax, Ay - r + 24), B = c(Bx, By - r + 24), C = c(Cx, Cy + r - 12)
  )

  # ---- vertical bands ------------------------------------------------------
  # Title band (optional), then the fixed diagram block, then the legend, then
  # the caption (optional). Only the bands move; the geometry above is drawn
  # into its own translated group and never has to be re-tuned.
  TITLE_LH <- 17; CAP_LH <- 13
  title_lines <- if (venn_has_text(title)) strwrap(title, width = 60) else character(0)
  cap_lines   <- if (venn_has_text(caption)) strwrap(caption, width = 84) else character(0)

  title_base <- if (length(title_lines)) 20 + TITLE_LH * (seq_along(title_lines) - 1) else numeric(0)
  # The diagram block carries 35px of padding above its own box already, so the
  # gap the title needs on top of that is small.
  dia_top    <- if (length(title_base)) max(title_base) + 4 else 0

  leg_y   <- dia_top + DIA_H + 2
  BAR_X   <- 84; BAR_W <- 312; BAR_H <- 13
  unit_y  <- leg_y + 9
  bar_y   <- leg_y + 15
  tick_y  <- leg_y + 40
  # With every region suppressed there is no scale to draw, and the grey key is
  # the only thing left worth showing -- so it moves up into the empty band
  # rather than sitting under a bar that is not there.
  has_scale <- length(breaks) >= 2
  has_na    <- anyNA(vals)
  has_none  <- !is.na(vals[["none"]])
  key_y     <- (if (has_scale) leg_y + 50 else leg_y + 8) +
    c(none = 0, na = if (has_none) 16 else 0)
  leg_h     <- (if (has_scale) 46 else 0) +
    (if (has_none) 16 else 0) + (if (has_na) 18 else 0)

  cap_base <- if (length(cap_lines)) leg_y + leg_h + 12 + CAP_LH * (seq_along(cap_lines) - 1) else numeric(0)
  VBH <- ceiling(if (length(cap_base)) max(cap_base) + 8 else leg_y + leg_h + 4)

  # ---- pieces --------------------------------------------------------------
  mk_region <- function(key, clips, mask_id, tooltip_label) {
    open  <- paste0(sprintf('<g clip-path="url(#clip%s%s)">', clips, uid), collapse = "")
    close <- paste0(rep("</g>", length(clips)), collapse = "")
    mask_attr <- if (!is.null(mask_id)) sprintf(' mask="url(#%s%s)"', mask_id, uid) else ""
    sprintf('%s<rect x="0" y="0" width="%d" height="%d" fill="%s"%s><title>%s: %s</title></rect>%s',
            open, VBW, DIA_H, fillcol(key), mask_attr,
            venn_esc(tooltip_label), venn_esc(fmt(vals[[key]])), close)
  }

  lbl <- function(...) paste(group_labels[c(...)], collapse = " + ")

  bg_none <- sprintf(
    '<rect x="%g" y="%g" width="%g" height="%g" rx="20" fill="%s" stroke="%s" stroke-width="1.5" filter="url(#boxshadow%s)"><title>Geen ondersteuningssignaal: %s</title></rect>',
    Ux, Uy, Uw, Uh, fillcol("none"), stroke_col, uid, venn_esc(fmt(vals[["none"]])))

  regions <- paste0(
    mk_region("A",   "A",           "maskBC", lbl(1)),
    mk_region("B",   "B",           "maskAC", lbl(2)),
    mk_region("C",   "C",           "maskAB", lbl(3)),
    mk_region("AB",  c("A", "B"),   "maskC",  lbl(1, 2)),
    mk_region("AC",  c("A", "C"),   "maskB",  lbl(1, 3)),
    mk_region("BC",  c("B", "C"),   "maskA",  lbl(2, 3)),
    mk_region("ABC", c("A", "B", "C"), NULL,  lbl(1, 2, 3))
  )

  # `txt` is XML, not plain text: callers escape, or hand over an entity.
  halo_text <- function(x, y, txt, size = 13, weight = 600,
                        fill = ink, halo = "#ffffff", halo_w = 3.2) {
    sprintf('<text x="%g" y="%g" text-anchor="middle" font-size="%g" font-weight="%d" fill="%s" stroke="%s" stroke-width="%g" stroke-linejoin="round" paint-order="stroke" font-family="%s">%s</text>',
            x, y, size, weight, fill, halo, halo_w, VENN_FONT, txt)
  }

  # The halo alone stops carrying a dark label once a scale runs to near-black,
  # so the label follows the fill it sits on instead of being fixed.
  on_dark <- function(key) venn_luminance(fillcol(key)) < 0.42

  value_labels <- paste0(vapply(names(lab), function(k) {
    dark <- on_dark(k)
    halo_text(lab[[k]][1], lab[[k]][2], fmt_short_xml(vals[[k]]),
              fill = if (dark) "#ffffff" else ink,
              halo = if (dark) "#10202a" else "#ffffff",
              # A dark halo reads much heavier than a white one at this size,
              # so it gets less of it.
              halo_w = if (dark) 2.6 else 3.2)
  }, character(1)), collapse = "")

  # The "none" region is the one area whose meaning isn't readable off the
  # circles, so its number gets a caption.
  none_dark <- on_dark("none")
  none_caption <- halo_text(
    lab$none[1], lab$none[2] + 15, venn_esc("geen van de drie"), size = 9,
    weight = 500, halo_w = 2.6,
    fill = if (none_dark) "#ffffff" else muted,
    halo = if (none_dark) "#10202a" else "#ffffff")

  # Group codes ride on a soft chip rather than a bare halo: at the top of a
  # filled circle a chip separates the name from the fill far more cleanly.
  chip <- function(x, y, txt) {
    w <- nchar(txt) * 7.6 + 22
    paste0(
      '<g filter="url(#chipshadow', uid, ')">',
      sprintf('<rect x="%g" y="%g" width="%g" height="20" rx="10" fill="#ffffff" fill-opacity="0.94" stroke="%s" stroke-opacity="0.35" stroke-width="1"/>',
              x - w / 2, y - 14, w, stroke_col),
      sprintf('<text x="%g" y="%g" text-anchor="middle" font-size="12" font-weight="700" fill="%s" font-family="%s" letter-spacing="0.3">%s</text>',
              x, y, ink, VENN_FONT, venn_esc(txt)),
      '</g>')
  }

  name_labels <- paste0(vapply(names(name_lab), function(k) {
    idx <- match(k, c("A", "B", "C"))
    chip(name_lab[[k]][1], name_lab[[k]][2], group_codes[idx])
  }, character(1)), collapse = "")

  # A white under-stroke keeps the circle edges legible whatever the fill on
  # either side of them happens to be.
  outline <- function(c_attr) sprintf(
    '<circle %s fill="none" stroke="#ffffff" stroke-width="3.4" stroke-opacity="0.5"/><circle %s fill="none" stroke="%s" stroke-width="1.6"/>',
    c_attr, c_attr, stroke_col)

  # ---- legend --------------------------------------------------------------
  # Keys for the two fills that sit outside the scale.
  key_row <- function(y, fill, txt) paste0(
    sprintf('<rect x="%g" y="%g" width="14" height="11" rx="2" fill="%s" stroke="%s" stroke-opacity="0.35" stroke-width="1"/>',
            BAR_X, y, fill, muted),
    sprintf('<text x="%g" y="%g" font-size="9.5" fill="%s" font-family="%s">%s</text>',
            BAR_X + 20, y + 9, muted, VENN_FONT, venn_esc(txt)))

  extra_keys <- paste0(
    if (has_none) key_row(key_y[["none"]], VENN_NONE_FILL,
                          "geen van de drie groepen (buiten de schaal)") else "",
    if (has_na) key_row(key_y[["na"]], VENN_NA_FILL,
                        "onvoldoende waarnemingen (CBS-onderdrukking)") else "")

  # The map has carried a legend from the start; the venn's fills were the one
  # choropleth in the app you had to hover to decode.
  legend_svg <- if (!has_scale) extra_keys else {
    nb <- length(breaks) - 1L
    bw <- BAR_W / nb
    swatches <- paste0(vapply(seq_len(nb), function(i) {
      sprintf('<rect x="%g" y="%g" width="%g" height="%g" fill="%s"/>',
              BAR_X + (i - 1) * bw, bar_y, bw, BAR_H, bin_cols[i])
    }, character(1)), collapse = "")

    # Break labels collide once the bins get narrow or the numbers get long
    # ("350.000" under a 45px bin); drop every other label rather than let them
    # overlap. 5.6px per character is a good enough stand-in for text metrics
    # we cannot measure here.
    tick_txt <- vapply(breaks, fmt_break, character(1))
    idx <- if (max(nchar(tick_txt)) * 5.6 + 6 > bw) {
      seq(1L, nb + 1L, by = 2L)
    } else {
      seq_len(nb + 1L)
    }
    ticks <- paste0(vapply(idx, function(i) {
      sprintf('<text x="%g" y="%g" text-anchor="middle" font-size="9.5" fill="%s" font-family="%s">%s</text>',
              BAR_X + (i - 1) * bw, tick_y, muted, VENN_FONT, venn_esc(tick_txt[i]))
    }, character(1)), collapse = "")

    paste0(
      sprintf('<text x="%g" y="%g" font-size="10" font-weight="600" fill="%s" font-family="%s" letter-spacing="0.2">%s</text>',
              BAR_X, unit_y, muted, VENN_FONT,
              venn_esc(if (weergave == "rel") "Aandeel (%)" else "Aantal")),
      swatches,
      sprintf('<rect x="%g" y="%g" width="%g" height="%g" rx="2" fill="none" stroke="%s" stroke-opacity="0.35" stroke-width="1"/>',
              BAR_X, bar_y, BAR_W, BAR_H, muted),
      ticks, extra_keys)
  }

  # ---- title / caption -----------------------------------------------------
  title_svg <- paste0(vapply(seq_along(title_lines), function(i) {
    sprintf('<text x="24" y="%g" font-size="13.5" font-weight="700" fill="%s" font-family="%s">%s</text>',
            title_base[i], ahti_branding$colors$grijs_blauw, VENN_FONT, venn_esc(title_lines[i]))
  }, character(1)), collapse = "")

  caption_svg <- paste0(vapply(seq_along(cap_lines), function(i) {
    sprintf('<text x="24" y="%g" font-size="9.5" fill="%s" font-family="%s">%s</text>',
            cap_base[i], muted, VENN_FONT, venn_esc(cap_lines[i]))
  }, character(1)), collapse = "")

  # ---- document ------------------------------------------------------------
  mask <- function(id, circles) paste0(
    '<mask id="', id, uid, '" maskUnits="userSpaceOnUse" x="0" y="0" width="', VBW, '" height="', DIA_H, '">',
    '<rect x="0" y="0" width="', VBW, '" height="', DIA_H, '" fill="white"/>',
    paste0(sprintf('<circle %s fill="black"/>', circles), collapse = ""),
    '</mask>')

  defs <- paste0(
    '<defs>',
    sprintf('<clipPath id="clipA%s"><circle %s/></clipPath>', uid, cA),
    sprintf('<clipPath id="clipB%s"><circle %s/></clipPath>', uid, cB),
    sprintf('<clipPath id="clipC%s"><circle %s/></clipPath>', uid, cC),
    mask("maskA", cA), mask("maskB", cB), mask("maskC", cC),
    mask("maskAB", c(cA, cB)), mask("maskAC", c(cA, cC)), mask("maskBC", c(cB, cC)),
    '<filter id="boxshadow', uid, '" x="-10%" y="-10%" width="120%" height="120%">',
    '<feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#0c2a38" flood-opacity="0.16"/></filter>',
    '<filter id="chipshadow', uid, '" x="-40%" y="-80%" width="180%" height="260%">',
    '<feDropShadow dx="0" dy="1" stdDeviation="1.4" flood-color="#0c2a38" flood-opacity="0.26"/></filter>',
    '</defs>')

  size_attr <- if (standalone) {
    sprintf('width="%d" height="%d"', VBW, VBH)
  } else {
    sprintf('style="width:100%%;max-width:%dpx;display:block;margin:0 auto;"', VBW)
  }

  paste0(
    if (standalone) '<?xml version="1.0" encoding="UTF-8"?>\n' else "",
    sprintf('<svg viewBox="0 0 %d %d" %s xmlns="http://www.w3.org/2000/svg" role="img" font-family="%s">',
            VBW, VBH, size_attr, VENN_FONT),
    if (standalone && venn_has_text(title)) sprintf('<title>%s</title>', venn_esc(title)) else "",
    if (standalone) sprintf('<rect x="0" y="0" width="%d" height="%d" fill="#ffffff"/>', VBW, VBH) else "",
    defs,
    title_svg,
    sprintf('<g transform="translate(0,%g)">', dia_top),
    bg_none, regions,
    outline(cA), outline(cB), outline(cC),
    value_labels, none_caption, name_labels,
    '</g>',
    legend_svg,
    caption_svg,
    '</svg>')
}

# ---------------------------------------------------------------------------
# De venn als tabel
# ---------------------------------------------------------------------------
#
# De figuur toont per deelgebied een waarde bij een gekozen risicowaarde. De
# tabel hieronder zet er de hele risicoverdeling naast: dezelfde acht
# deelgebieden als rijen, de categorieen van de risicoscore als kolommen. Dat
# is wat je uit de figuur niet kunt aflezen -- die is per definitie een
# momentopname bij een waarde -- en het is precies de kruising waar de
# risicostapeling zichtbaar wordt.

#' De 8 deelgebieden van de venn, in tekenvolgorde, met per sleutel het
#' combinatieniveau zoals het in split_level staat.
#' Een sleutelvector, gedeeld door de figuur en de tabel, zodat de twee niet
#' uiteen kunnen lopen over welk niveau in welk vakje hoort.
venn_levels <- function(group_codes) {
  stopifnot(length(group_codes) == 3)
  g <- unname(group_codes)
  c(none = "none", A = g[1], B = g[2], C = g[3],
    AB  = paste(g[1], g[2], sep = " + "),
    AC  = paste(g[1], g[3], sep = " + "),
    BC  = paste(g[2], g[3], sep = " + "),
    ABC = paste(g, collapse = " + "))
}

#' Dezelfde 8 sleutels, maar met de leesbare groepsnaam -- zoals de tooltips in
#' venn_svg() hem opbouwen.
venn_region_labels <- function(group_codes, group_labels) {
  g <- unname(group_codes)
  lab <- function(...) paste(group_labels[g[c(...)]], collapse = " + ")
  c(none = "Geen ondersteuningssignaal",
    A = lab(1), B = lab(2), C = lab(3),
    AB = lab(1, 2), AC = lab(1, 3), BC = lab(2, 3), ABC = lab(1, 2, 3))
}

#' De venn als HTML-tabel: rijen = de 8 deelgebieden, kolommen = de waarden
#' van de risicoscore.
#'
#' @param m Numerieke matrix met 8 rijen (namen = de sleutels van
#'   venn_levels(), in die volgorde) en een kolom per risicowaarde
#'   (kolomnamen = de waarden zelf). NA = onderdrukt.
#' @param n Numerieke vector van 8, het totaal per deelgebied over de
#'   risicowaarden (de noemer achter een percentage). NA waar onbekend.
#' @param weergave "rel" of "abs" -- bepaalt of de cellen percentages of
#'   aantallen zijn, net als in de figuur.
#' @param group_codes,group_labels Zoals bij venn_svg().
#' @param var_label Omschrijving boven de waardekolommen.
#' @param kolomlabels Korte koppen boven de kolommen; standaard de kolomnamen
#'   van `m` zelf. Voor de risicofactor-tabel zijn dat codes (R1, R2, ...) die
#'   in een kolomkop passen, met de volledige omschrijving in `kolomtitels`.
#' @param kolomtitels Volledige omschrijving per kolom, als hover-title. NULL
#'   betekent geen title-attribuut.
#' @param n_label Kop boven de laatste kolom.
#' @return Een HTML-string voor HTML()/renderUI().
venn_matrix_html <- function(m, n, weergave, group_codes, group_labels,
                             var_label = "Risicoscore",
                             kolomlabels = colnames(m), kolomtitels = NULL,
                             n_label = "n") {
  keys <- names(venn_levels(group_codes))
  stopifnot(is.matrix(m), identical(rownames(m), keys), length(n) == length(keys))

  labels <- venn_region_labels(group_codes, group_labels)
  waarden <- colnames(m)
  stopifnot(length(kolomlabels) == length(waarden),
            is.null(kolomtitels) || length(kolomtitels) == length(waarden))

  fmt <- function(v, rel) {
    if (is.na(v)) {
      return(sprintf('<span class="venn-tab-na" title="onvoldoende waarnemingen">%s</span>',
                     VENN_SUPPRESSED_MARK))
    }
    if (rel) sprintf("%.1f%%", v)
    else venn_esc(format(round(v), big.mark = ".", decimal.mark = ","))
  }
  rel <- weergave == "rel"

  kop <- paste0(
    '<thead>',
    '<tr>',
    '<th rowspan="2" class="venn-tab-groep">Ondersteuningscombinatie</th>',
    sprintf('<th colspan="%d" class="venn-tab-span">%s</th>', length(waarden), venn_esc(var_label)),
    sprintf('<th rowspan="2" class="venn-tab-n">%s</th>', venn_esc(n_label)),
    '</tr><tr>',
    paste0(vapply(seq_along(waarden), function(i) {
      titel <- if (is.null(kolomtitels)) "" else sprintf(' title="%s"', venn_esc(kolomtitels[i]))
      sprintf('<th class="venn-tab-num"%s>%s</th>', titel, venn_esc(kolomlabels[i]))
    }, character(1)), collapse = ""),
    '</tr></thead>')

  rijen <- vapply(seq_along(keys), function(i) {
    k <- keys[i]
    paste0(
      # De "none"-rij staat buiten de cirkels en krijgt, net als in de figuur,
      # een eigen streepje mee zodat hij niet als vierde groep leest.
      sprintf('<tr%s>', if (k == "none") ' class="venn-tab-none"' else ""),
      sprintf('<td class="venn-tab-groep">%s</td>', venn_esc(labels[[k]])),
      paste0(vapply(waarden, function(w) sprintf('<td class="venn-tab-num">%s</td>',
                                                 fmt(m[k, w], rel)), character(1)),
             collapse = ""),
      sprintf('<td class="venn-tab-n">%s</td>', fmt(n[[i]], rel = FALSE)),
      '</tr>')
  }, character(1))

  paste0(
    '<table class="venn-tab">', kop,
    '<tbody>', paste0(rijen, collapse = ""), '</tbody></table>')
}
