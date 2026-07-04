# Shared TDM extraction pipeline used by app.R -- reads the TDM transit
# network live out of a zipped file geodatabase (via GDAL's /vsizip/), layer
# names discovered dynamically from CITILABS_TRANSITGROUPS so this keeps
# working as more transit groups (e.g. local bus) get added to the gdb.
# Mirrors R/gtfs_pipeline.R: one live extraction path, no pre-baked cache.

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
})

# Returns list(routes_sf = ..., stops_sf = ...) built from a TDM zipped file
# geodatabase, across every transit group found in CITILABS_TRANSITGROUPS.
build_tdm_layers <- function(gdb_zip_path) {
  gdb <- paste0("/vsizip/", gdb_zip_path)
  groups <- st_read(gdb, layer = "CITILABS_TRANSITGROUPS", quiet = TRUE)

  read_group <- function(group_name) {
    line_layer <- paste0(group_name, "_PTLine")
    node_layer <- paste0(group_name, "_PTNode")

    # line_id = row_number() at read time, before any select()/rbind() --
    # confirmed against the raw gdb that _PTNode's LINEID is exactly the
    # 1-based row position of its line within this same group's _PTLine
    # (not a NAME/foreign-key match: LINEID is an integer like 1, 2, 3,
    # while NAME is a string like "Blue"). Capturing it explicitly here
    # keeps the stops-to-routes join in app.R (for stop_color) an
    # intentional key rather than an implicit "row order never changes"
    # assumption living downstream.
    routes <- st_read(gdb, layer = line_layer, quiet = TRUE) |>
      mutate(tdm_group = group_name, line_id = row_number()) |>
      select(tdm_group, line_id, NAME, LONGNAME, MODE, OPERATOR,
             HEADWAY_1, HEADWAY_2, HEADWAY_3, HEADWAY_4, HEADWAY_5)

    stops <- st_read(gdb, layer = node_layer, quiet = TRUE) |>
      filter(STOPNODE == 1) |>
      mutate(tdm_group = group_name) |>
      select(tdm_group, LINEID, SEQNO, NODES)

    list(routes = routes, stops = stops)
  }

  results <- lapply(groups$TRANSITGROUP_NAME, read_group)

  routes_sf <- do.call(rbind, lapply(results, `[[`, "routes")) |> st_transform(4326)
  stops_sf <- do.call(rbind, lapply(results, `[[`, "stops")) |> st_transform(4326)

  list(routes_sf = routes_sf, stops_sf = stops_sf)
}
