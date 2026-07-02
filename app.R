suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(mapgl)
  library(sf)
  library(dplyr)
})

gtfs_root <- "_data/gtfs"
tdm_routes_path <- "_data/tdm/tdm_routes.geojson"
tdm_stops_path <- "_data/tdm/tdm_stops.geojson"

available_dates <- sort(
  setdiff(list.dirs(gtfs_root, full.names = FALSE, recursive = FALSE), "raw"),
  decreasing = TRUE
)

read_gtfs_routes <- function(date) {
  st_read(file.path(gtfs_root, date, "routes_shapes.geojson"), quiet = TRUE)
}
read_gtfs_stops <- function(date) {
  st_read(file.path(gtfs_root, date, "stops.geojson"), quiet = TRUE)
}

# Loaded once, non-reactively, to build each map exactly one time. Every
# subsequent update goes through a proxy so the current pan/zoom is preserved
# instead of the map re-rendering (and re-zooming to bounds) on every control
# change. Switching comparison mode (overlay/swipe) is the one action that
# rebuilds its target map fresh, since that's a structural UI change, not a
# simple filter toggle.
initial_date <- available_dates[1]
initial_gtfs_routes_sf <- read_gtfs_routes(initial_date)
initial_gtfs_stops_sf <- read_gtfs_stops(initial_date)

tdm_routes_sf <- st_read(tdm_routes_path, quiet = TRUE)
tdm_stops_sf <- st_read(tdm_stops_path, quiet = TRUE)

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

tdm_mode_colors <- c(rail = "#E6194B", brt = "#3CB44B", core = "#4363D8")
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
  title = "WFRC TDM vs GTFS",
  sidebar = sidebar(
    width = 260,
    strong("GTFS"),
    selectInput("gtfs_date", "Snapshot", choices = available_dates, selected = initial_date),
    checkboxGroupInput("gtfs_display", "Show", choices = lines_stops_choices,
                        selected = c("lines", "stops"), inline = TRUE),
    checkboxInput("show_stop_labels", "Stop labels (zoom in)", value = TRUE),
    hr(),
    strong("TDM"),
    selectInput("tdm_year", "Year", choices = all_tdm_years, selected = default_tdm_year),
    selectInput("tdm_modes", "Lines", choices = all_tdm_modes, selected = all_tdm_modes, multiple = TRUE),
    checkboxGroupInput("tdm_display", "Show", choices = lines_stops_choices,
                        selected = c("lines", "stops"), inline = TRUE),
    hr(),
    selectInput("basemap", "Basemap",
                choices = c("Positron" = "positron", "Dark Matter" = "dark-matter"),
                selected = "positron"),
    helpText("GTFS: every shape_id drawn individually (GTFSx-style); stops",
             "colored by primary route, clustered below zoom 10.",
             "TDM: dashed lines colored by line type (rail/BRT/core).")
  ),
  nav_panel(
    title = "Map",
    card(full_screen = TRUE, uiOutput("map_container"))
  ),
  nav_spacer(),
  nav_item(
    div(
      class = "d-flex align-items-center gap-2 px-2",
      span("Overlay", class = "small text-muted"),
      input_switch("compare_swipe", NULL, value = FALSE),
      span("Swipe", class = "small text-muted")
    )
  )
)

server <- function(input, output, session) {

  compare_mode <- reactive(if (isTRUE(input$compare_swipe)) "swipe" else "overlay")

  gtfs_routes_sf <- reactive({
    req(input$gtfs_date)
    read_gtfs_routes(input$gtfs_date)
  })
  gtfs_stops_sf <- reactive({
    req(input$gtfs_date)
    read_gtfs_stops(input$gtfs_date)
  })

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

  gtfs_lines_vis <- reactive(if ("lines" %in% input$gtfs_display) "visible" else "none")
  gtfs_stops_vis <- reactive(if ("stops" %in% input$gtfs_display) "visible" else "none")
  gtfs_labels_vis <- reactive({
    if ("stops" %in% input$gtfs_display && isTRUE(input$show_stop_labels)) "visible" else "none"
  })
  tdm_lines_vis <- reactive(if ("lines" %in% input$tdm_display) "visible" else "none")
  tdm_stops_vis <- reactive(if ("stops" %in% input$tdm_display) "visible" else "none")

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
      maplibre(style = carto_style(input$basemap), bounds = initial_gtfs_routes_sf) |>
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
      gtfs_map <- maplibre(style = carto_style(input$basemap), bounds = initial_gtfs_routes_sf) |>
        add_gtfs_layers(gtfs_routes_sf(), gtfs_stops_sf(),
                         lines_visibility = gtfs_lines_vis(), stops_visibility = gtfs_stops_vis(),
                         labels_visibility = gtfs_labels_vis(), cluster = FALSE)
      tdm_map <- maplibre(style = carto_style(input$basemap), bounds = initial_gtfs_routes_sf) |>
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

  observeEvent(list(input$gtfs_display, input$show_stop_labels), {
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

  observeEvent(input$tdm_display, {
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
