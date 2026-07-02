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

tdm_routes_sf <- st_read(tdm_routes_path, quiet = TRUE)
tdm_stops_sf <- st_read(tdm_stops_path, quiet = TRUE)

tdm_group_colors <- c(rail = "#E6194B", brt = "#3CB44B")
default_tdm_color <- "#808080"
tdm_routes_sf$tdm_color <- unname(ifelse(
  tdm_routes_sf$tdm_group %in% names(tdm_group_colors),
  tdm_group_colors[tdm_routes_sf$tdm_group],
  default_tdm_color
))

ui <- page_sidebar(
  title = "WFRC TDM vs GTFS",
  sidebar = sidebar(
    selectInput("gtfs_date", "GTFS snapshot", choices = available_dates, selected = available_dates[1]),
    radioButtons("gtfs_detail", "GTFS route detail",
                 choices = c("Route (dissolved)" = "dissolved", "Shape (detail)" = "shapes"),
                 selected = "dissolved"),
    checkboxGroupInput("tdm_groups", "TDM transit groups",
                        choices = sort(unique(tdm_routes_sf$tdm_group)),
                        selected = sort(unique(tdm_routes_sf$tdm_group))),
    checkboxInput("show_stop_labels", "Show GTFS stop labels (zoom in)", value = TRUE),
    radioButtons("basemap", "Basemap",
                 choices = c("Positron" = "positron", "Dark Matter" = "dark-matter"),
                 selected = "positron"),
    helpText("Solid lines colored by each route's official GTFS color.",
             "Dashed lines are the TDM model network, colored by transit group.")
  ),
  card(
    full_screen = TRUE,
    maplibreOutput("map", height = "100%")
  )
)

server <- function(input, output, session) {

  gtfs_routes_sf <- reactive({
    req(input$gtfs_date, input$gtfs_detail)
    file <- if (input$gtfs_detail == "dissolved") "routes_dissolved.geojson" else "routes_shapes.geojson"
    st_read(file.path(gtfs_root, input$gtfs_date, file), quiet = TRUE)
  })

  gtfs_stops_sf <- reactive({
    req(input$gtfs_date)
    st_read(file.path(gtfs_root, input$gtfs_date, "stops.geojson"), quiet = TRUE)
  })

  tdm_routes_filtered <- reactive({
    req(input$tdm_groups)
    filter(tdm_routes_sf, tdm_group %in% input$tdm_groups)
  })

  tdm_stops_filtered <- reactive({
    req(input$tdm_groups)
    filter(tdm_stops_sf, tdm_group %in% input$tdm_groups)
  })

  output$map <- renderMaplibre({
    m <- maplibre(style = carto_style(input$basemap), bounds = gtfs_routes_sf()) |>
      add_line_layer(
        id = "tdm_routes",
        source = tdm_routes_filtered(),
        line_color = get_column("tdm_color"),
        line_width = 3,
        line_dasharray = c(2, 1),
        popup = "LONGNAME",
        tooltip = "NAME"
      ) |>
      add_circle_layer(
        id = "tdm_stops",
        source = tdm_stops_filtered(),
        circle_color = "#000000",
        circle_radius = 4,
        circle_stroke_color = "#ffffff",
        circle_stroke_width = 1
      ) |>
      add_line_layer(
        id = "gtfs_routes",
        source = gtfs_routes_sf(),
        line_color = get_column("route_color"),
        line_width = 2,
        popup = "route_long_name",
        tooltip = "route_short_name"
      ) |>
      add_circle_layer(
        id = "gtfs_stops",
        source = gtfs_stops_sf(),
        circle_color = "#333333",
        circle_radius = 3,
        circle_stroke_color = "#ffffff",
        circle_stroke_width = 1,
        popup = "stop_name"
      ) |>
      add_legend(
        "TDM transit group",
        values = names(tdm_group_colors),
        colors = unname(tdm_group_colors),
        type = "categorical",
        position = "bottom-right"
      )

    if (isTRUE(input$show_stop_labels)) {
      m <- add_symbol_layer(
        m,
        id = "gtfs_stop_labels",
        source = gtfs_stops_sf(),
        text_field = get_column("stop_name"),
        text_size = 11,
        text_color = "#222222",
        text_halo_color = "#ffffff",
        text_halo_width = 1,
        min_zoom = 14
      )
    }

    m
  })
}

shinyApp(ui, server)
