# Icon lookup for the app's own primary glyphs (section headers, chip icons,
# tooltip triggers) -- routes through Font Awesome (already an renv/bslib
# dependency via the `fontawesome` package) instead of hand-drawn SVGs, since
# the bespoke set didn't read as professional enough.

icon_fa_names <- list(
  shuffle = "shuffle",
  bus = "bus",
  map = "map",
  route = "route",
  pin = "location-dot",
  info = "circle-info"
)

# Every call site pairs the icon with a visible text label already, so it's
# decorative rather than the only cue -- icon()'s own role="presentation"
# covers that.
brand_icon <- function(name, class = NULL) {
  fa_name <- icon_fa_names[[name]]
  if (is.null(fa_name)) stop("Unknown brand icon: ", name)
  shiny::icon(fa_name, class = paste(c("brand-icon", class), collapse = " "))
}
