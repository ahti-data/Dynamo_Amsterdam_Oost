#' Static 3-circle Venn/Euler diagram as an inline SVG string, filled
#' choropleth-style (same YlOrRd scale as the map) by value for each of the
#' 8 O_MPG_combination/O_OUD_combination levels: "none" (dead space outside
#' every circle, boxed in as a rounded "universe" rect) plus the 7 overlap
#' regions.
#'
#' Built with SVG clip-path (intersection: nest one clip-path group inside
#' another) and mask (subtraction: a black shape on a white mask knocks that
#' area out) rather than a plotting library -- there's no CRAN package for a
#' three-circle Venn that also supports independent per-region choropleth
#' fills and hover tooltips.
#'
#' @param vals Named numeric vector with exactly these 8 names: none, A, B,
#'   C, AB, AC, BC, ABC. NA renders as "onvoldoende waarnemingen" (same
#'   suppression convention as the map), short form "–" inline.
#' @param weergave "rel" (percentage) or "abs" (count) -- only affects number
#'   formatting.
#' @param group_codes Character vector of length 3, e.g.
#'   c("O_MPG1","O_MPG2","O_MPG3") -- the raw codes shown on the circles.
#' @param group_labels Named character vector (short names, same names as
#'   group_codes) used in hover tooltips -- see
#'   data/metadata/variable_labels.R.
#' @param stroke_col Hex colour for circle/box outlines.
#' @return A single HTML/SVG string, ready for `HTML()`/`renderUI()`.
venn_svg <- function(vals, weergave, group_codes, group_labels,
                     stroke_col = ahti_branding$colors$grijs_blauw) {
  stopifnot(length(group_codes) == 3,
           setequal(names(vals), c("none", "A", "B", "C", "AB", "AC", "BC", "ABC")))

  fmt <- function(v) {
    if (is.na(v)) "onvoldoende waarnemingen"
    else if (weergave == "rel") sprintf("%.1f%%", v)
    else format(round(v), big.mark = ".")
  }
  # Short form for the inline SVG label: some regions (the triple overlap
  # especially) are too small for the full suppression phrase, which would
  # otherwise overflow into neighbouring regions. The full phrase is still
  # the hover <title>.
  fmt_short <- function(v) if (is.na(v)) "–" else fmt(v)

  pal <- if (all(is.na(vals))) {
    function(x) rep("#e0e0e0", length(x))
  } else {
    colorBin("YlOrRd", domain = vals[!is.na(vals)], bins = 6, na.color = "#e0e0e0", pretty = TRUE)
  }
  fillcol <- function(key) if (is.na(vals[[key]])) "#e0e0e0" else pal(vals[[key]])

  # Equilateral triangle layout: r=100, side=120 -- generous overlap, a
  # clearly visible (if small) triple-intersection region.
  Ax <- 180; Ay <- 160
  Bx <- 300; By <- 160
  Cx <- 240; Cy <- 263.9
  r  <- 100
  VBW <- 480; VBH <- 420

  # "Universe" box: comfortably contains the 3 circles. The dead space inside
  # this box but outside every circle is "none".
  Ux <- 45; Uy <- 35; Uw <- 390; Uh <- 345

  cA <- sprintf('cx="%g" cy="%g" r="%g"', Ax, Ay, r)
  cB <- sprintf('cx="%g" cy="%g" r="%g"', Bx, By, r)
  cC <- sprintf('cx="%g" cy="%g" r="%g"', Cx, Cy, r)

  # Hand-tuned centroids for this one fixed, known layout -- there is no
  # general formula worth writing for a diagram that never changes shape.
  lab <- list(
    none = c(90, 58),   A = c(133, 108), B = c(347, 108), C = c(240, 305),
    AB = c(240, 138),   AC = c(178, 232), BC = c(302, 232), ABC = c(240, 197)
  )
  name_lab <- list(
    A = c(Ax, Ay - r + 24), B = c(Bx, By - r + 24), C = c(Cx, Cy + r - 12)
  )

  mk_region <- function(key, clips, mask_id, tooltip_label) {
    open  <- paste0(sprintf('<g clip-path="url(#clip%s)">', clips), collapse = "")
    close <- paste0(rep("</g>", length(clips)), collapse = "")
    mask_attr <- if (!is.null(mask_id)) sprintf(' mask="url(#%s)"', mask_id) else ""
    sprintf('%s<rect x="0" y="0" width="%d" height="%d" fill="%s"%s><title>%s: %s</title></rect>%s',
            open, VBW, VBH, fillcol(key), mask_attr, tooltip_label, fmt(vals[[key]]), close)
  }

  lbl <- function(...) paste(group_labels[c(...)], collapse = " + ")

  bg_none <- sprintf(
    '<rect x="%g" y="%g" width="%g" height="%g" rx="18" fill="%s" stroke="%s" stroke-width="1.5"><title>Geen ondersteuningssignaal: %s</title></rect>',
    Ux, Uy, Uw, Uh, fillcol("none"), stroke_col, fmt(vals[["none"]]))

  regions <- paste0(
    mk_region("A",   "A",           "maskBC", lbl(1)),
    mk_region("B",   "B",           "maskAC", lbl(2)),
    mk_region("C",   "C",           "maskAB", lbl(3)),
    mk_region("AB",  c("A", "B"),   "maskC",  lbl(1, 2)),
    mk_region("AC",  c("A", "C"),   "maskB",  lbl(1, 3)),
    mk_region("BC",  c("B", "C"),   "maskA",  lbl(2, 3)),
    mk_region("ABC", c("A", "B", "C"), NULL,  lbl(1, 2, 3))
  )

  halo_text <- function(x, y, txt, size = 13, weight = 600, fill = "#222") {
    sprintf('<text x="%g" y="%g" text-anchor="middle" font-size="%d" font-weight="%d" fill="%s" stroke="#fff" stroke-width="3" paint-order="stroke" font-family="sans-serif">%s</text>',
            x, y, size, weight, fill, txt)
  }

  value_labels <- paste0(vapply(names(lab), function(k) {
    halo_text(lab[[k]][1], lab[[k]][2], fmt_short(vals[[k]]))
  }, character(1)), collapse = "")

  name_labels <- paste0(vapply(names(name_lab), function(k) {
    idx <- match(k, c("A", "B", "C"))
    halo_text(name_lab[[k]][1], name_lab[[k]][2], group_codes[idx], weight = 700, fill = "#272727")
  }, character(1)), collapse = "")

  sprintf('
<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg" style="width:100%%;max-width:480px;display:block;margin:0 auto;">
  <defs>
    <clipPath id="clipA"><circle %s/></clipPath>
    <clipPath id="clipB"><circle %s/></clipPath>
    <clipPath id="clipC"><circle %s/></clipPath>
    <mask id="maskA"><rect width="100%%" height="100%%" fill="white"/><circle %s fill="black"/></mask>
    <mask id="maskB"><rect width="100%%" height="100%%" fill="white"/><circle %s fill="black"/></mask>
    <mask id="maskC"><rect width="100%%" height="100%%" fill="white"/><circle %s fill="black"/></mask>
    <mask id="maskAB"><rect width="100%%" height="100%%" fill="white"/><circle %s fill="black"/><circle %s fill="black"/></mask>
    <mask id="maskAC"><rect width="100%%" height="100%%" fill="white"/><circle %s fill="black"/><circle %s fill="black"/></mask>
    <mask id="maskBC"><rect width="100%%" height="100%%" fill="white"/><circle %s fill="black"/><circle %s fill="black"/></mask>
  </defs>
  %s
  %s
  <circle %s fill="none" stroke="%s" stroke-width="1.5"/>
  <circle %s fill="none" stroke="%s" stroke-width="1.5"/>
  <circle %s fill="none" stroke="%s" stroke-width="1.5"/>
  %s
  %s
</svg>', VBW, VBH,
    cA, cB, cC,
    cA, cB, cC,
    cA, cB, cB, cC, cA, cC,
    bg_none, regions,
    cA, stroke_col, cB, stroke_col, cC, stroke_col,
    name_labels, value_labels)
}
