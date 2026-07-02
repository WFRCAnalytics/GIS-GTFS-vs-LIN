# Extracts GTFS route/shape/stop geometry directly from the raw GTFS zips in
# _data/gtfs/raw/, replacing the lossy output of QGIS's GTFS2GIS plugin
# (which dissolves routes and drops route_color/route_type/shape_id).
#
# Run from the repo root: Rscript R/prepare_gtfs.R

suppressPackageStartupMessages({
  library(tidytransit)
  library(sf)
  library(dplyr)
})

raw_dir <- "_data/gtfs/raw"
out_root <- "_data/gtfs"

extract_date <- function(filename) {
  m <- regmatches(filename, regexpr("[0-9]{8}", filename))
  if (length(m) == 0) stop("Could not find an 8-digit date in: ", filename)
  m
}

normalize_color <- function(x, default) {
  x <- trimws(x)
  ifelse(is.na(x) | x == "", paste0("#", default), paste0("#", x))
}

process_feed <- function(zip_path, date) {
  message("Processing ", date, " (", basename(zip_path), ")")
  out_dir <- file.path(out_root, date)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  gtfs <- read_gtfs(zip_path)

  routes <- gtfs$routes %>%
    mutate(
      route_color = normalize_color(route_color, "FFFFFF"),
      route_text_color = normalize_color(route_text_color, "000000")
    ) %>%
    select(route_id, route_short_name, route_long_name, route_type,
           route_color, route_text_color)

  trip_shapes <- gtfs$trips %>%
    filter(!is.na(shape_id), shape_id != "") %>%
    distinct(shape_id, route_id, direction_id)

  # Shape-level detail: one row per shape_id, full route attributes attached.
  routes_shapes_sf <- shapes_as_sf(gtfs$shapes) %>%
    inner_join(trip_shapes, by = "shape_id") %>%
    inner_join(routes, by = "route_id") %>%
    select(shape_id, route_id, direction_id, route_short_name,
           route_long_name, route_type, route_color, route_text_color)

  # Route-level dissolve: matches the granularity of the TDM PTLine layer
  # for a cleaner visual side-by-side.
  routes_dissolved_sf <- routes_shapes_sf %>%
    group_by(route_id, route_short_name, route_long_name, route_type,
             route_color, route_text_color) %>%
    summarise(.groups = "drop")

  # Stops: unchanged retention (stop_id, stop_name, serving route_ids),
  # rebuilt from the raw zip instead of the GTFS2GIS output.
  stop_routes <- gtfs$stop_times %>%
    distinct(stop_id, trip_id) %>%
    inner_join(distinct(gtfs$trips, trip_id, route_id), by = "trip_id") %>%
    distinct(stop_id, route_id) %>%
    group_by(stop_id) %>%
    summarise(route_ids = paste(sort(unique(route_id)), collapse = ","), .groups = "drop")

  stops_sf <- stops_as_sf(gtfs$stops) %>%
    left_join(stop_routes, by = "stop_id") %>%
    select(stop_id, stop_name, route_ids)

  old_routes_geojson <- file.path(out_dir, "routes.geojson")
  if (file.exists(old_routes_geojson)) file.remove(old_routes_geojson)

  st_write(routes_shapes_sf, file.path(out_dir, "routes_shapes.geojson"),
           delete_dsn = TRUE, quiet = TRUE)
  st_write(routes_dissolved_sf, file.path(out_dir, "routes_dissolved.geojson"),
           delete_dsn = TRUE, quiet = TRUE)
  st_write(stops_sf, file.path(out_dir, "stops.geojson"),
           delete_dsn = TRUE, quiet = TRUE)
}

zip_files <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE)
for (zip_path in zip_files) {
  process_feed(zip_path, extract_date(basename(zip_path)))
}
