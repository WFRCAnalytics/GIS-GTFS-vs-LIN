suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(brand.yml)
  library(yaml)
  library(mapgl)
  library(sf)
  library(dplyr)
})

source("R/gtfs_pipeline.R")
source("R/tdm_pipeline.R")

# WFRC's brand.yml lives inside a git submodule (a Quarto-extension layout,
# not a root-level _brand.yml, so bslib's auto-discovery won't find it --
# point bs_theme() at it explicitly instead). Logo assets are served without
# copying them into www/ via addResourcePath().
brand_yml_path <- "_brand/_extensions/wfrc-brand/brand.yml"
addResourcePath("brand", "_brand/_extensions/wfrc-brand/assets")

# The R brand.yml package (0.1.0) requires a single string for every
# color.* theme field and every typography.*.color/background-color field
# (confirmed in its source, brand_color.R/brand_typography.R -- both check
# these with ptype = "string", no light/dark map support), unlike e.g.
# logo.*, where light/dark maps are a documented, supported part of the
# spec. Checked WFRC's brand.yml directly (grep light:/dark:) -- exactly
# three fields use a light/dark map outside of logo.*: color.foreground,
# color.background, and typography.headings.color. Flatten those three to
# their light-mode value before handing the brand off to bs_theme(). Dark
# mode itself still works via Bootstrap's own input_dark_mode() mechanism;
# it just won't pick up WFRC's specific dark-mode values for these three
# until the R package supports this.
brand_data <- yaml::read_yaml(brand_yml_path)
flatten_light_dark <- function(x) if (is.list(x) && !is.null(x$light)) x$light else x
brand_data$color$foreground <- flatten_light_dark(brand_data$color$foreground)
brand_data$color$background <- flatten_light_dark(brand_data$color$background)
brand_data$typography$headings$color <- flatten_light_dark(brand_data$typography$headings$color)

gtfs_raw_dir <- "_data/gtfs"
tdm_gdb_path <- "_data/tdm/WFv1000_MasterNet_20260430.gdb.zip"

gtfs_raw_zips <- list.files(gtfs_raw_dir, pattern = "\\.zip$", full.names = TRUE)
names(gtfs_raw_zips) <- vapply(gtfs_raw_zips, function(f) extract_date(basename(f)), character(1))
available_dates <- sort(names(gtfs_raw_zips), decreasing = TRUE)

# Raw GTFS snapshot ids are yyyymmdd (e.g. "20250227"); render them as a
# readable date for the snapshot picker and the map badge, while the control
# value stays the raw id used to key into gtfs_raw_zips.
fmt_snapshot <- function(d) {
  if (is.null(d) || !grepl("^[0-9]{8}$", d)) return(d %||% "")
  format(as.Date(d, "%Y%m%d"), "%b %e, %Y")
}
snapshot_choices <- setNames(available_dates, vapply(available_dates, fmt_snapshot, character(1)))

# Loaded once, non-reactively, to build each map exactly one time. Every
# subsequent update goes through a proxy so the current pan/zoom is preserved
# instead of the map re-rendering (and re-zooming to bounds) on every control
# change. Switching comparison mode (overlay/swipe) is the one action that
# rebuilds its target map fresh, since that's a structural UI change, not a
# simple filter toggle. GTFS is processed live from the raw zip every time
# (snapshot, upload, or feed URL alike -- one pipeline, no pre-baked cache).
initial_date <- available_dates[1]
initial_gtfs <- build_gtfs_layers(gtfs_raw_zips[[initial_date]])
initial_gtfs_routes_sf <- initial_gtfs$routes_shapes_sf
initial_gtfs_stops_sf <- initial_gtfs$stops_sf

tdm_data <- build_tdm_layers(tdm_gdb_path)
tdm_routes_sf <- tdm_data$routes_sf
tdm_stops_sf <- tdm_data$stops_sf

# tdm_group (e.g. "rail_2023", "wfrc_brt_2055UF") bundles year + line type
# together; split them out so each can be its own control.
parse_tdm_mode <- function(group) {
  case_when(
    grepl("rail", group, ignore.case = TRUE) ~ "rail",
    grepl("brt", group, ignore.case = TRUE) ~ "brt",
    grepl("core", group, ignore.case = TRUE) ~ "core",
    TRUE ~ "other"
  )
}
parse_tdm_year <- function(group) {
  m <- regmatches(group, regexpr("[0-9]{4}(UF)?$", group))
  ifelse(nchar(m) == 0, "unknown", m)
}

tdm_routes_sf$tdm_mode <- parse_tdm_mode(tdm_routes_sf$tdm_group)
tdm_routes_sf$tdm_year <- parse_tdm_year(tdm_routes_sf$tdm_group)
tdm_stops_sf$tdm_mode <- parse_tdm_mode(tdm_stops_sf$tdm_group)
tdm_stops_sf$tdm_year <- parse_tdm_year(tdm_stops_sf$tdm_group)

# WFRC's own Wasatch Choice transit colors (wc-light-rail/wc-brt); "core"
# (local bus) has no official swatch yet since that network isn't in the TDM
# data, so it borrows a distinct purple from their broader Core Palette.
tdm_mode_colors <- c(rail = "#3762ad", brt = "#24949a", core = "#553c8f")
default_tdm_mode_color <- "#808080"
tdm_routes_sf$tdm_color <- unname(ifelse(
  tdm_routes_sf$tdm_mode %in% names(tdm_mode_colors),
  tdm_mode_colors[tdm_routes_sf$tdm_mode],
  default_tdm_mode_color
))

all_tdm_years <- sort(unique(tdm_routes_sf$tdm_year))
# The gdb also carries forecast-year groups (e.g. 2055UF) alongside the 2023
# base year -- default to base-year only so we're not comparing a future
# planning scenario against present-day GTFS by default.
default_tdm_year <- if ("2023" %in% all_tdm_years) "2023" else all_tdm_years[1]
all_tdm_modes <- intersect(c("brt", "rail", "core"), unique(tdm_routes_sf$tdm_mode))

# A small uppercase field label (Source / Year / Show / ...). Deliberately a
# neutral gray tier (see .field-label in www/custom.css), one step below the
# section headers, so the sidebar has real hierarchy instead of every label
# competing at the same brand-cyan weight.
field_label <- function(text) span(text, class = "field-label")

# Section header for the sidebar's top-level groups: a tinted "icon tile"
# (colored background + matching icon, brand-palette category badge) + an
# uppercase label, with an optional control (the dataset Enable switch)
# parked at the right edge -- the switch-in-header pattern turns each dataset
# into a self-contained module you flip on/off, and removes a whole redundant
# "Enable" row per section. Tints come from WFRC's own brand palette
# (brand_data$color$palette), not any borrowed color.
section_tint <- brand_data$color$palette
section_header <- function(icon_name, label, tint, control = NULL) {
  div(class = "section-head d-flex align-items-center gap-2",
    span(icon(icon_name), class = "section-tile",
         style = sprintf("background: %s26; color: %s;", tint, tint)),
    span(label, class = "section-label"),
    if (!is.null(control)) div(class = "hdr-switch", control)
  )
}

# A labelled field block: uppercase field label (with optional inline info
# tooltip) stacked above its control, on a consistent 12px rhythm.
sb_field <- function(label, control, info = NULL) {
  div(class = "sb-field",
    div(class = "d-flex align-items-center gap-1",
      field_label(label),
      if (!is.null(info)) info
    ),
    control
  )
}

# A dataset "layer card" (kepler.gl / CARTO pattern): each dataset is a
# self-contained module with a left accent edge tinted to its on-map color,
# a subtle surface, and its Enable switch parked in the header -- so the two
# datasets read as color-keyed layers, not a flat stack of form sections.
# The accent color is exposed as a CSS custom property (--accent) so the
# left border, tinted surface, and active-chip color all derive from it.
layer_card <- function(accent, ...) {
  div(class = "sb-section sb-card", style = sprintf("--accent: %s;", accent), ...)
}

# Leading glyphs for the Lines / Stops visibility toggles -- a polyline glyph
# and a stop-marker glyph, so the chips read as map-layer visibility controls
# (kepler.gl sublayer toggles) rather than generic text checkboxes. Values
# stay "lines"/"stops" so every server-side reference is unchanged.
lines_stops_names <- list(
  tagList(icon("route"), span("Lines")),
  tagList(icon("location-dot"), span("Stops"))
)
lines_stops_values <- c("lines", "stops")

# Shared by GTFS and TDM stop circles so both sides render at the same size.
stop_radius_expr <- list("interpolate", list("linear"), list("zoom"), 10, 3, 14, 6)

gtfs_cluster_options <- function() {
  cluster_options(
    max_zoom = 10,
    cluster_radius = 50,
    color_stops = rep("#3E7C8B", 3),
    radius_stops = c(14, 20, 30),
    count_stops = c(0, 50, 1000),
    circle_stroke_color = "#ffffff",
    circle_stroke_width = 1.5,
    circle_opacity = 0.85,
    text_color = "#ffffff",
    count_format = "abbreviated"
  )
}
tdm_cluster_options <- function() {
  cluster_options(
    max_zoom = 10,
    cluster_radius = 50,
    color_stops = rep("#333333", 3),
    radius_stops = c(14, 20, 30),
    count_stops = c(0, 50, 1000),
    circle_stroke_color = "#ffffff",
    circle_stroke_width = 1.5,
    circle_opacity = 0.85,
    text_color = "#ffffff",
    count_format = "abbreviated"
  )
}

# GTFSx-style layers: routes colored by route_color, stops colored (ring) by
# their primary serving route and clustered below zoom 10, labels gated to
# zoom 14+. `cluster` is forced off in swipe mode -- mapgl's compare widget
# (inst/htmlwidgets/maplibregl_compare.js) drops cluster/clusterMaxZoom/
# clusterRadius when it builds each side's GeoJSON source, so clustering
# silently never activates there; a confirmed upstream mapgl limitation, not
# fixable from this app.
add_gtfs_layers <- function(map, routes_sf, stops_sf, lines_visibility = "visible",
                             stops_visibility = "visible", labels_visibility = "visible",
                             cluster = TRUE) {
  map <- map |>
    add_line_layer(
      id = "gtfs_routes",
      source = routes_sf,
      line_color = get_column("route_color"),
      line_width = 3,
      popup = "route_long_name",
      tooltip = "route_short_name",
      visibility = lines_visibility
    )

  map <- if (cluster) {
    add_circle_layer(
      map,
      id = "gtfs_stops",
      source = stops_sf,
      circle_color = get_column("stop_color"),
      circle_radius = stop_radius_expr,
      circle_stroke_color = "#ffffff",
      circle_stroke_width = 1,
      popup = "stop_name",
      visibility = stops_visibility,
      cluster_options = gtfs_cluster_options()
    )
  } else {
    add_circle_layer(
      map,
      id = "gtfs_stops",
      source = stops_sf,
      circle_color = get_column("stop_color"),
      circle_radius = stop_radius_expr,
      circle_stroke_color = "#ffffff",
      circle_stroke_width = 1,
      popup = "stop_name",
      visibility = stops_visibility
    )
  }

  map |>
    add_symbol_layer(
      id = "gtfs_stop_labels",
      source = stops_sf,
      text_field = get_column("stop_name"),
      text_size = 11,
      text_color = "#222222",
      text_halo_color = "#ffffff",
      text_halo_width = 1,
      min_zoom = 14,
      visibility = labels_visibility
    )
}

# TDM lines are dashed and colored by mode (rail/BRT/core) so they read as
# the model network regardless of which GTFS route colors sit nearby.
# `cluster` is forced off in swipe mode -- see add_gtfs_layers().
add_tdm_layers <- function(map, routes_sf, stops_sf, lines_visibility = "visible",
                            stops_visibility = "visible", cluster = TRUE) {
  map <- map |>
    add_line_layer(
      id = "tdm_routes",
      source = routes_sf,
      line_color = get_column("tdm_color"),
      line_width = 3,
      line_dasharray = c(2, 1),
      popup = "LONGNAME",
      tooltip = "NAME",
      visibility = lines_visibility
    )

  map <- if (cluster) {
    add_circle_layer(
      map,
      id = "tdm_stops",
      source = stops_sf,
      circle_color = "#000000",
      circle_radius = stop_radius_expr,
      circle_stroke_color = "#ffffff",
      circle_stroke_width = 1,
      visibility = stops_visibility,
      cluster_options = tdm_cluster_options()
    )
  } else {
    add_circle_layer(
      map,
      id = "tdm_stops",
      source = stops_sf,
      circle_color = "#000000",
      circle_radius = stop_radius_expr,
      circle_stroke_color = "#ffffff",
      circle_stroke_width = 1,
      visibility = stops_visibility
    )
  }

  map |>
    add_legend(
      "TDM line type",
      values = names(tdm_mode_colors),
      colors = unname(tdm_mode_colors),
      type = "categorical",
      position = "bottom-right"
    )
}

ui <- page_navbar(
  title = tagList(
    img(src = "brand/logo/horizontal/WFRC_logo_horizontal_white_transparent.png",
        height = "28px", alt = "WFRC logo", class = "me-2"),
    "TDM vs GTFS"
  ),
  # The whole design system now lives in www/custom.css (a more maintainable
  # pattern than a giant embedded bs_add_rules() string). All of it is plain,
  # theme-aware CSS -- no Sass compilation needed -- so a stylesheet link that
  # loads after the bslib/brand-compiled Bootstrap is the right home for it.
  theme = bs_theme(brand = brand_data),
  window_title = "WFRC TDM vs GTFS",
  header = tagList(
    tags$head(
      tags$link(rel = "icon", type = "image/png",
                href = "brand/logo/abbreviated/WFRC_logo_abbreviated_color_transparent.png"),
      # bslib self-hosts brand.yml's Google Fonts by downloading each
      # weight/style/subset combo and serving it locally (see the
      # Poppins-0.4.10/Inter-0.4.10/Fira_Code-0.4.10 links this generates).
      # On this machine several of those cached files are corrupted -- byte-
      # diffed the self-hosted Poppins 600 "latin" file against the same file
      # fetched fresh from fonts.gstatic.com and it's 42 bytes larger,
      # diverging partway through; Chromium's font sanitizer (OTS) rejects it
      # ("Failed to convert WOFF 2.0 font to SFNT") and silently falls all
      # the way back to the browser's default serif font for any text set in
      # that specific weight -- e.g. the segmented control's active label
      # (font-weight: 600). Confirmed reproducible across many past
      # sessions' Rtmp caches, so this is a real upstream self-hosting bug,
      # not a one-off download glitch -- not something fixable from CSS.
      # Loading the same families/weights directly from Google's CDN adds a
      # second, working @font-face source for the browser to fall back to
      # (multiple @font-face rules for the same family/weight/style act as a
      # fallback list) without touching bslib's self-hosted CSS at all.
      tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
      tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = NA),
      tags$link(rel = "stylesheet", href = paste0(
        "https://fonts.googleapis.com/css2?",
        "family=Poppins:ital,wght@0,300;0,400;0,500;0,600;0,700;1,300;1,400;1,500;1,600;1,700",
        "&family=Inter:ital,wght@0,300;0,400;0,500;0,600;0,700;1,300;1,400;1,500;1,600;1,700",
        "&family=Fira+Code:wght@400;500;700",
        "&display=swap"
      )),
      tags$link(rel = "stylesheet", href = "custom.css")
    ),
    busyIndicatorOptions(spinner_type = "ring", spinner_color = "#52b6d5")
  ),
  sidebar = sidebar(
    width = 300,
    class = "app-sidebar",
    div(class = "sb-section",
      section_header("shuffle", "Comparison", section_tint$`wfrc-yellow`),
      uiOutput("compare_mode_control", inline = TRUE)
    ),
    layer_card(section_tint$`wfrc-secondary-blue`,
      section_header("bus", "GTFS", section_tint$`wfrc-secondary-blue`,
                     control = input_switch("gtfs_enabled", NULL, value = TRUE)),
      sb_field("Source",
        radioButtons("gtfs_source", NULL,
                     choices = c("Snapshot" = "snapshot", "Upload" = "upload", "URL" = "url"),
                     selected = "snapshot")
      ),
      conditionalPanel(
        "input.gtfs_source == 'snapshot'",
        sb_field("Snapshot",
          selectInput("gtfs_date", NULL, choices = snapshot_choices, selected = initial_date))
      ),
      conditionalPanel(
        "input.gtfs_source == 'upload'",
        sb_field("GTFS zip file",
          fileInput("gtfs_upload", NULL, accept = ".zip"))
      ),
      conditionalPanel(
        "input.gtfs_source == 'url'",
        sb_field("Feed URL",
          div(
            textInput("gtfs_url", NULL, placeholder = "https://.../gtfs.zip"),
            actionButton("gtfs_url_load", "Load feed", class = "btn-sm btn-outline-primary")
          ))
      ),
      sb_field("Show",
        div(class = "chip-group",
          checkboxGroupInput("gtfs_display", NULL,
                             choiceNames = lines_stops_names, choiceValues = lines_stops_values,
                             selected = c("lines", "stops"), inline = TRUE)),
        info = tooltip(
          span(icon("circle-info"), class = "field-info"),
          "Every GTFS route shape is drawn individually. Stops are colored by",
          "their primary route, cluster below zoom 10 in overlay mode, and",
          "show name labels on zoom-in."
        )
      )
    ),
    layer_card(section_tint$`wc-light-rail`,
      section_header("map", "TDM", section_tint$`wc-light-rail`,
                     control = input_switch("tdm_enabled", NULL, value = TRUE)),
      sb_field("Year",
        selectInput("tdm_year", NULL, choices = all_tdm_years, selected = default_tdm_year)),
      sb_field("Line types",
        selectInput("tdm_modes", NULL, choices = all_tdm_modes,
                    selected = all_tdm_modes, multiple = TRUE)),
      sb_field("Show",
        div(class = "chip-group",
          checkboxGroupInput("tdm_display", NULL,
                             choiceNames = lines_stops_names, choiceValues = lines_stops_values,
                             selected = c("lines", "stops"), inline = TRUE)),
        info = tooltip(
          span(icon("circle-info"), class = "field-info"),
          "Dashed lines colored by line type (rail/BRT/core), so the model",
          "network reads clearly regardless of nearby GTFS route colors."
        )
      )
    )
  ),
  nav_panel(
    title = "Map",
    div(
      style = "position: relative; height: 100%;",
      uiOutput("map_container"),
      div(
        class = "map-badge position-absolute top-0 start-0 m-3",
        uiOutput("comparison_summary", inline = TRUE)
      )
    )
  ),
  nav_spacer(),
  # id is required for the mode to be readable server-side (input$dark_mode);
  # the map's basemap style follows it instead of its own selector -- see
  # current_basemap() below.
  nav_item(input_dark_mode(id = "dark_mode"))
)

server <- function(input, output, session) {

  both_enabled <- reactive(isTRUE(input$gtfs_enabled) && isTRUE(input$tdm_enabled))
  # Swipe only makes sense when both datasets are on -- force overlay
  # whenever one is disabled, regardless of the switch's last position.
  compare_mode <- reactive(if (both_enabled() && isTRUE(input$compare_swipe)) "swipe" else "overlay")

  # A small colored dot, tinted to match the corresponding sidebar section
  # header, dimmed when that dataset is disabled -- ties the floating map
  # badge back to the sidebar's own color coding instead of being plain text.
  status_dot <- function(tint, enabled) {
    span(style = sprintf(
      "display:inline-block; width:8px; height:8px; border-radius:50%%; background:%s; opacity:%s;",
      tint, if (enabled) "1" else ".3"
    ))
  }

  output$comparison_summary <- renderUI({
    gtfs_part <- if (!isTRUE(input$gtfs_enabled)) {
      "Off"
    } else {
      switch(input$gtfs_source %||% "snapshot",
        snapshot = fmt_snapshot(input$gtfs_date),
        upload = "Uploaded feed",
        url = "Feed URL",
        "On"
      )
    }
    tdm_part <- if (!isTRUE(input$tdm_enabled)) {
      "Off"
    } else {
      paste0(input$tdm_year %||% "",
             " (", paste(input$tdm_modes %||% character(0), collapse = ", "), ")")
    }
    span(
      status_dot(section_tint$`wfrc-secondary-blue`, isTRUE(input$gtfs_enabled)),
      span("GTFS", class = "badge-dim ms-1 me-1"),
      span(gtfs_part, class = "badge-seg"),
      span("|", class = "badge-sep"),
      status_dot(section_tint$`wc-light-rail`, isTRUE(input$tdm_enabled)),
      span("TDM", class = "badge-dim ms-1 me-1"),
      span(tdm_part, class = "badge-seg")
    )
  })

  # Rendered as its own output (not inlined in the sidebar) so it can
  # live-update -- grey out and lock as soon as GTFS or TDM gets disabled.
  # input_switch()'s wrapping .shiny-input-container defaults to width:100%,
  # which as a flex child stretches to fill the row and strands the "Swipe"
  # label at the far edge -- wrap it at width:auto to keep the three pieces
  # (Overlay / switch / Swipe) tight together.
  output$compare_mode_control <- renderUI({
    div(
      class = "compare-row",
      style = if (!both_enabled()) "opacity: 0.4; pointer-events: none;" else NULL,
      span("Overlay", class = "compare-opt"),
      div(class = "hdr-switch",
          input_switch("compare_swipe", NULL, value = isTRUE(input$compare_swipe))),
      span("Swipe", class = "compare-opt")
    )
  })

  gtfs_snapshot_data <- reactive({
    req(input$gtfs_date)
    tryCatch(
      build_gtfs_layers(gtfs_raw_zips[[input$gtfs_date]]),
      error = function(e) {
        showNotification(paste("Could not process GTFS snapshot:", conditionMessage(e)),
                          type = "error", duration = 8)
        NULL
      }
    )
  })

  gtfs_upload_data <- reactive({
    req(input$gtfs_upload)
    tryCatch(
      build_gtfs_layers(input$gtfs_upload$datapath),
      error = function(e) {
        showNotification(paste("Could not process uploaded GTFS file:", conditionMessage(e)),
                          type = "error", duration = 8)
        NULL
      }
    )
  })

  gtfs_url_data <- eventReactive(input$gtfs_url_load, {
    req(input$gtfs_url)
    tmp <- tempfile(fileext = ".zip")
    tryCatch({
      download.file(input$gtfs_url, tmp, mode = "wb", quiet = TRUE)
      build_gtfs_layers(tmp)
    }, error = function(e) {
      showNotification(paste("Could not load GTFS feed:", conditionMessage(e)),
                        type = "error", duration = 8)
      NULL
    })
  })

  gtfs_data <- reactive({
    switch(req(input$gtfs_source),
      snapshot = gtfs_snapshot_data(),
      upload = gtfs_upload_data(),
      url = gtfs_url_data()
    )
  })

  gtfs_routes_sf <- reactive({ req(gtfs_data()); gtfs_data()$routes_shapes_sf })
  gtfs_stops_sf <- reactive({ req(gtfs_data()); gtfs_data()$stops_sf })

  # No separate basemap picker -- it follows the light/dark mode toggle
  # instead (Dark Matter in dark mode, Positron in light mode), since running
  # a light basemap under dark chrome (or vice versa) never looked
  # intentional. input$dark_mode can be NULL for an instant before the
  # client-side toggle's initial value round-trips to the server (see
  # input_dark_mode() docs -- id is required to read it reactively at all);
  # %||% covers that brief gap the same way the old selector's fallback did.
  current_basemap <- reactive(
    if (identical(input$dark_mode %||% "light", "dark")) "dark-matter" else "positron"
  )

  tdm_group_names <- reactive({
    req(input$tdm_year, input$tdm_modes)
    unique(tdm_routes_sf$tdm_group[
      tdm_routes_sf$tdm_year == input$tdm_year & tdm_routes_sf$tdm_mode %in% input$tdm_modes
    ])
  })
  tdm_routes_filtered <- reactive({
    groups <- tdm_group_names()
    if (length(groups) == 0) tdm_routes_sf[0, ] else filter(tdm_routes_sf, tdm_group %in% groups)
  })
  tdm_stops_filtered <- reactive({
    groups <- tdm_group_names()
    if (length(groups) == 0) tdm_stops_sf[0, ] else filter(tdm_stops_sf, tdm_group %in% groups)
  })

  gtfs_lines_vis <- reactive({
    if (isTRUE(input$gtfs_enabled) && "lines" %in% input$gtfs_display) "visible" else "none"
  })
  gtfs_stops_vis <- reactive({
    if (isTRUE(input$gtfs_enabled) && "stops" %in% input$gtfs_display) "visible" else "none"
  })
  # Labels always follow stop visibility; zoom-gating (min_zoom on the
  # symbol layer) handles when they actually appear, no separate toggle.
  gtfs_labels_vis <- gtfs_stops_vis
  tdm_lines_vis <- reactive({
    if (isTRUE(input$tdm_enabled) && "lines" %in% input$tdm_display) "visible" else "none"
  })
  tdm_stops_vis <- reactive({
    if (isTRUE(input$tdm_enabled) && "stops" %in% input$tdm_display) "visible" else "none"
  })

  # Resolves to whichever proxy currently targets the visible widget: the
  # single overlay map, or the relevant side of the swipe compare widget.
  gtfs_proxy <- reactive({
    if (compare_mode() == "swipe") maplibre_compare_proxy("compare_map", map_side = "before")
    else maplibre_proxy("map")
  })
  tdm_proxy <- reactive({
    if (compare_mode() == "swipe") maplibre_compare_proxy("compare_map", map_side = "after")
    else maplibre_proxy("map")
  })

  output$map_container <- renderUI({
    if (compare_mode() == "swipe") maplibreCompareOutput("compare_map", height = "100%")
    else maplibreOutput("map", height = "100%")
  })

  output$map <- renderMaplibre({
    req(compare_mode() == "overlay")
    isolate({
      maplibre(style = carto_style(current_basemap()), bounds = initial_gtfs_routes_sf) |>
        add_tdm_layers(tdm_routes_filtered(), tdm_stops_filtered(),
                        lines_visibility = tdm_lines_vis(), stops_visibility = tdm_stops_vis()) |>
        add_gtfs_layers(gtfs_routes_sf(), gtfs_stops_sf(),
                         lines_visibility = gtfs_lines_vis(), stops_visibility = gtfs_stops_vis(),
                         labels_visibility = gtfs_labels_vis())
    })
  })

  output$compare_map <- renderMaplibreCompare({
    req(compare_mode() == "swipe")
    isolate({
      gtfs_map <- maplibre(style = carto_style(current_basemap()), bounds = initial_gtfs_routes_sf) |>
        add_gtfs_layers(gtfs_routes_sf(), gtfs_stops_sf(),
                         lines_visibility = gtfs_lines_vis(), stops_visibility = gtfs_stops_vis(),
                         labels_visibility = gtfs_labels_vis(), cluster = FALSE)
      tdm_map <- maplibre(style = carto_style(current_basemap()), bounds = initial_gtfs_routes_sf) |>
        add_tdm_layers(tdm_routes_filtered(), tdm_stops_filtered(),
                        lines_visibility = tdm_lines_vis(), stops_visibility = tdm_stops_vis(),
                        cluster = FALSE)
      compare(gtfs_map, tdm_map, mode = "swipe", orientation = "vertical")
    })
  })

  observeEvent(gtfs_routes_sf(), {
    gtfs_proxy() |> set_source(layer_id = "gtfs_routes", source = gtfs_routes_sf())
  }, ignoreInit = TRUE)

  observeEvent(gtfs_stops_sf(), {
    gtfs_proxy() |>
      set_source(layer_id = "gtfs_stops", source = gtfs_stops_sf()) |>
      set_source(layer_id = "gtfs_stop_labels", source = gtfs_stops_sf())
  }, ignoreInit = TRUE)

  observeEvent(tdm_routes_filtered(), {
    tdm_proxy() |> set_source(layer_id = "tdm_routes", source = tdm_routes_filtered())
  }, ignoreInit = TRUE)

  observeEvent(tdm_stops_filtered(), {
    tdm_proxy() |> set_source(layer_id = "tdm_stops", source = tdm_stops_filtered())
  }, ignoreInit = TRUE)

  observeEvent(list(input$gtfs_display, input$gtfs_enabled), {
    p <- gtfs_proxy() |>
      set_layout_property("gtfs_routes", "visibility", gtfs_lines_vis()) |>
      set_layout_property("gtfs_stops", "visibility", gtfs_stops_vis()) |>
      set_layout_property("gtfs_stop_labels", "visibility", gtfs_labels_vis())
    # Cluster companion layers only exist in overlay mode -- clustering is
    # off in swipe mode (see add_gtfs_layers()).
    if (compare_mode() == "overlay") {
      p |>
        set_layout_property("gtfs_stops-clusters", "visibility", gtfs_stops_vis()) |>
        set_layout_property("gtfs_stops-cluster-count", "visibility", gtfs_stops_vis())
    }
  }, ignoreInit = TRUE)

  observeEvent(list(input$tdm_display, input$tdm_enabled), {
    p <- tdm_proxy() |>
      set_layout_property("tdm_routes", "visibility", tdm_lines_vis()) |>
      set_layout_property("tdm_stops", "visibility", tdm_stops_vis())
    # Cluster companion layers only exist in overlay mode -- see
    # add_tdm_layers().
    if (compare_mode() == "overlay") {
      p |>
        set_layout_property("tdm_stops-clusters", "visibility", tdm_stops_vis()) |>
        set_layout_property("tdm_stops-cluster-count", "visibility", tdm_stops_vis())
    }
  }, ignoreInit = TRUE)

  observeEvent(input$dark_mode, {
    gtfs_proxy() |> set_style(carto_style(current_basemap()), preserve_layers = TRUE)
    tdm_proxy() |> set_style(carto_style(current_basemap()), preserve_layers = TRUE)
  }, ignoreInit = TRUE)
}

shinyApp(ui, server)
