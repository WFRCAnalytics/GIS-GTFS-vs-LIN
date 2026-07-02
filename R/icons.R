# Bespoke brand icon set -- replaces Font Awesome for the app's own primary
# glyphs (section headers, chip icons, tooltip triggers). Font Awesome stays
# loaded for everything else (bslib/dark-mode chrome etc.); only our own
# iconography moves off it, the same "single source of truth icon map" idea
# GTFSx uses for its own icons (studied as a UX pattern only -- these paths
# are original, hand-drawn for this app, not GTFSx's assets).
#
# Stroke-only line icons on a 24x24 viewBox, sized in em so they scale with
# the surrounding text the same way a font-based icon would.

icon_paths <- list(
  shuffle = tagList(
    tags$path(d = "M3 17h4l10-11h4"),
    tags$path(d = "M17 3l4 3-4 3"),
    tags$path(d = "M3 7h4l10 11h4"),
    tags$path(d = "M17 21l4-3-4-3")
  ),
  bus = tagList(
    tags$rect(x = "3", y = "6", width = "18", height = "11", rx = "2"),
    tags$path(d = "M3 12h18"),
    tags$path(d = "M7 6v6M12 6v6M17 6v6"),
    tags$circle(cx = "7.5", cy = "19.5", r = "1.5"),
    tags$circle(cx = "16.5", cy = "19.5", r = "1.5")
  ),
  map = tagList(
    tags$path(d = "M9 3 3 5v16l6-2 6 2 6-2V3l-6 2-6-2z"),
    tags$path(d = "M9 3v16M15 5v16")
  ),
  route = tagList(
    tags$path(d = "M7 17.5C10 14 8 10 12 9s2-5 5-4.5"),
    tags$circle(cx = "5", cy = "19", r = "2"),
    tags$circle(cx = "19", cy = "5", r = "2")
  ),
  pin = tagList(
    tags$path(d = "M12 21s7-7.58 7-12.5A7 7 0 0 0 5 8.5C5 13.42 12 21 12 21z"),
    tags$circle(cx = "12", cy = "8.5", r = "2.5")
  ),
  info = tagList(
    tags$circle(cx = "12", cy = "12", r = "9"),
    tags$path(d = "M12 11v6"),
    tags$circle(cx = "12", cy = "7.5", r = "0.9", fill = "currentColor", stroke = "none")
  )
)

# aria-hidden by default -- every call site pairs the icon with a visible
# text label already, so it's decorative, not the only cue.
brand_icon <- function(name, class = NULL) {
  paths <- icon_paths[[name]]
  if (is.null(paths)) stop("Unknown brand icon: ", name)
  tags$svg(
    class = paste(c("brand-icon", class), collapse = " "),
    viewBox = "0 0 24 24", fill = "none", stroke = "currentColor",
    `stroke-width` = "1.75", `stroke-linecap` = "round", `stroke-linejoin` = "round",
    role = "img", `aria-hidden` = "true",
    paths
  )
}
