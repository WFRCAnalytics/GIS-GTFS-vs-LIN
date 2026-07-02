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

lines_stops_choices <- c("Lines" = "lines", "Stops" = "stops")
muted_label <- function(text) span(text, class = "small text-muted")

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
  theme = bs_theme(brand = brand_data) |>
    bs_add_rules(c(
      ".card { border-radius: .75rem; }",
      # mapgl's add_legend() and MapLibre's own controls (attribution, zoom,
      # fullscreen) ship a hardcoded Helvetica Neue/Arial stack, completely
      # disconnected from the brand font -- confirmed via the actual rendered
      # DOM (.mapboxgl-legend / .mapgl-legend-title / .maplibregl-ctrl), not
      # guessed. !important is needed to beat their inline-level specificity.
      ".mapboxgl-legend, .maplibregl-ctrl, .maplibregl-ctrl-attrib {",
      "  font-family: 'Poppins', sans-serif !important;",
      "}",
      ".mapgl-legend-title {",
      "  font-family: 'Inter', sans-serif !important;",
      "  color: #023c5b !important;",
      "}"
    )),
  window_title = "WFRC TDM vs GTFS",
  header = tagList(
    tags$head(
      tags$link(rel = "icon", type = "image/png",
                href = "brand/logo/abbreviated/WFRC_logo_abbreviated_color_transparent.png")
    ),
    busyIndicatorOptions(spinner_type = "ring", spinner_color = "#52b6d5")
  ),
  sidebar = sidebar(
    width = 280,
    div(
      class = "d-flex align-items-center gap-2 mb-1",
      icon("shuffle"), strong("Comparison mode")
    ),
    div(class = "mb-3", uiOutput("compare_mode_control", inline = TRUE)),
    hr(class = "my-2"),
    div(class = "d-flex align-items-center gap-2 mb-2", icon("bus"), strong("GTFS")),
    input_switch("gtfs_enabled", "Enable", value = TRUE),
    radioButtons("gtfs_source", muted_label("Source"),
                 choices = c("Saved snapshot" = "snapshot", "Upload zip" = "upload", "Feed URL" = "url"),
                 selected = "snapshot"),
    conditionalPanel(
      "input.gtfs_source == 'snapshot'",
      selectInput("gtfs_date", muted_label("Snapshot"),
                  choices = available_dates, selected = initial_date)
    ),
    conditionalPanel(
      "input.gtfs_source != 'snapshot'",
      p(class = "small text-muted", "Configure via the gear icon above.")
    ),
    div(
      class = "d-flex align-items-center gap-1",
      checkboxGroupInput("gtfs_display", muted_label("Show"), choices = lines_stops_choices,
                          selected = c("lines", "stops"), inline = TRUE),
      tooltip(
        icon("circle-info"),
        "Every GTFS route shape is drawn individually. Stops are colored by",
        "their primary route, cluster below zoom 10 in overlay mode, and",
        "show name labels on zoom-in."
      )
    ),
    hr(class = "my-2"),
    div(class = "d-flex align-items-center gap-2 mb-2", icon("map"), strong("TDM")),
    input_switch("tdm_enabled", "Enable", value = TRUE),
    selectInput("tdm_year", muted_label("Year"), choices = all_tdm_years, selected = default_tdm_year),
    selectInput("tdm_modes", muted_label("Lines"), choices = all_tdm_modes,
                selected = all_tdm_modes, multiple = TRUE),
    div(
      class = "d-flex align-items-center gap-1",
      checkboxGroupInput("tdm_display", muted_label("Show"), choices = lines_stops_choices,
                          selected = c("lines", "stops"), inline = TRUE),
      tooltip(
        icon("circle-info"),
        "Dashed lines colored by line type (rail/BRT/core), so the model",
        "network reads clearly regardless of nearby GTFS route colors."
      )
    )
  ),
  nav_panel(
    title = "Map",
    div(
      style = "position: relative; height: 100%;",
      uiOutput("map_container"),
      div(
        class = "position-absolute top-0 start-0 m-3 px-3 py-2 bg-body rounded shadow-sm",
        style = "z-index: 10;",
        textOutput("comparison_summary", inline = TRUE)
      )
    )
  ),
  nav_spacer(),
  nav_item(input_dark_mode()),
  nav_item(actionButton("open_settings", label = "Configure", icon = icon("gear"),
                         class = "btn-outline-light"))
)

server <- function(input, output, session) {

  both_enabled <- reactive(isTRUE(input$gtfs_enabled) && isTRUE(input$tdm_enabled))
  # Swipe only makes sense when both datasets are on -- force overlay
  # whenever one is disabled, regardless of the switch's last position.
  compare_mode <- reactive(if (both_enabled() && isTRUE(input$compare_swipe)) "swipe" else "overlay")

  # Reopening the settings modal re-renders these inputs from scratch, so
  # each one's initial value has to come from the current input (falling
  # back to a default only the first time) or it would silently reset on
  # every reopen. Only gtfs_url/basemap still live in the modal -- everything
  # else moved to the always-present sidebar, which doesn't need this.
  val <- function(id, default) if (is.null(input[[id]])) default else input[[id]]

  settings_modal <- function() {
    modalDialog(
      title = "Data source & basemap",
      easyClose = TRUE,
      footer = modalButton("Close"),
      conditionalPanel(
        "input.gtfs_source == 'upload'",
        fileInput("gtfs_upload", "GTFS zip file", accept = ".zip")
      ),
      conditionalPanel(
        "input.gtfs_source == 'url'",
        textInput("gtfs_url", "Feed URL", value = val("gtfs_url", ""),
                  placeholder = "https://.../gtfs.zip"),
        actionButton("gtfs_url_load", "Load feed")
      ),
      conditionalPanel(
        "input.gtfs_source == 'snapshot'",
        p(class = "text-muted small", "Using a saved GTFS snapshot -- pick the date from the sidebar.")
      ),
      hr(),
      selectInput("basemap", "Basemap",
                  choices = c("Positron" = "positron", "Dark Matter" = "dark-matter"),
                  selected = val("basemap", "positron"))
    )
  }

  observeEvent(input$open_settings, showModal(settings_modal()))

  output$comparison_summary <- renderText({
    gtfs_part <- if (!isTRUE(input$gtfs_enabled)) {
      "GTFS off"
    } else {
      switch(input$gtfs_source %||% "snapshot",
        snapshot = paste("GTFS", input$gtfs_date %||% ""),
        upload = "GTFS (uploaded feed)",
        url = "GTFS (feed URL)",
        "GTFS"
      )
    }
    tdm_part <- if (!isTRUE(input$tdm_enabled)) {
      "TDM off"
    } else {
      paste0("TDM ", input$tdm_year %||% "",
             " (", paste(input$tdm_modes %||% character(0), collapse = ", "), ")")
    }
    paste(gtfs_part, "·", tdm_part)
  })

  # Rendered as its own output (not inlined in the sidebar) so it can
  # live-update -- grey out and lock as soon as GTFS or TDM gets disabled.
  # input_switch()'s wrapping .shiny-input-container defaults to width:100%,
  # which as a flex child stretches to fill the row and strands the "Swipe"
  # label at the far edge -- wrap it at width:auto to keep the three pieces
  # (Overlay / switch / Swipe) tight together.
  output$compare_mode_control <- renderUI({
    div(
      class = "d-flex align-items-center gap-2",
      style = if (!both_enabled()) "opacity: 0.4; pointer-events: none;" else NULL,
      span("Overlay", class = "small text-muted"),
      div(style = "width: auto;", input_switch("compare_swipe", NULL, value = isTRUE(input$compare_swipe))),
      span("Swipe", class = "small text-muted")
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

  # basemap lives in the modal, which (unlike the sidebar) only renders once
  # the user opens it -- the initial map build happens before that, so
  # input$basemap can still be NULL at that point. Fall back to the same
  # default the modal's own selectInput uses.
  current_basemap <- reactive(input$basemap %||% "positron")

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

  observeEvent(input$basemap, {
    gtfs_proxy() |> set_style(carto_style(input$basemap), preserve_layers = TRUE)
    tdm_proxy() |> set_style(carto_style(input$basemap), preserve_layers = TRUE)
  }, ignoreInit = TRUE)
}

shinyApp(ui, server)
