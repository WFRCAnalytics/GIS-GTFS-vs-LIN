# Shared GTFS extraction pipeline used by app.R for every GTFS source --
# saved snapshots (read live from _data/gtfs/), user uploads, and feed
# URLs -- so there's exactly one extraction code path, not a pre-baked one
# for snapshots and a separate live one for everything else.

suppressPackageStartupMessages({
  library(tidytransit)
  library(sf)
  library(dplyr)
})

extract_date <- function(filename) {
  m <- regmatches(filename, regexpr("[0-9]{8}", filename))
  if (length(m) == 0) stop("Could not find an 8-digit date in: ", filename)
  m
}

# Some raw zips have their GTFS .txt files nested inside a subfolder (e.g.
# 20230723.zip contains 20230723/agency.txt, .../routes.txt, ...) instead of
# at the zip root. gtfsio doesn't handle that cleanly -- it can end up
# reading files from both the root and the subfolder, corrupting columns
# like shapes.txt's lat/lon. Normalize every zip to a flat, single-copy
# layout before handing it to read_gtfs().
flatten_gtfs_zip <- function(zip_path) {
  extract_dir <- file.path(tempdir(), paste0("gtfs_extract_", tools::file_path_sans_ext(basename(zip_path))))
  unlink(extract_dir, recursive = TRUE)
  dir.create(extract_dir, recursive = TRUE)
  utils::unzip(zip_path, exdir = extract_dir)

  agency_files <- list.files(extract_dir, pattern = "^agency\\.txt$", recursive = TRUE, full.names = TRUE)
  if (length(agency_files) == 0) stop("Could not find agency.txt inside ", zip_path)
  gtfs_dir <- dirname(agency_files[1])

  txt_files <- list.files(gtfs_dir, pattern = "\\.txt$")
  flat_zip <- file.path(tempdir(), paste0(tools::file_path_sans_ext(basename(zip_path)), "_flat.zip"))
  if (file.exists(flat_zip)) file.remove(flat_zip)

  old_wd <- setwd(gtfs_dir)
  on.exit(setwd(old_wd), add = TRUE)
  zip::zip(flat_zip, txt_files)

  flat_zip
}

normalize_color <- function(x, default) {
  x <- trimws(x)
  ifelse(is.na(x) | x == "", paste0("#", default), paste0("#", x))
}

# The GTFS feed's own effective date *range*, independent of where it came
# from (saved snapshot, upload, or feed URL) or what its filename happens
# to say -- confirmed these can genuinely disagree: _data/gtfs/20230723.zip
# (named for its 2023-07-23 capture/publish date) actually reports a
# feed_start_date of 2023-04-16 internally. A GTFS feed is valid over a
# date range, not a single day, so both endpoints are pulled from the same
# source rather than mixing e.g. feed_info's start with calendar's end.
# feed_info.txt is optional in the GTFS spec (and feed_end_date is only
# conditionally required even when feed_info.txt exists), so this falls
# back to calendar.txt's min(start_date)/max(end_date), then
# calendar_dates.txt's min/max(date). tidytransit::read_gtfs() already
# parses all of these as real Date columns, so no yyyymmdd string parsing
# is needed here.
extract_gtfs_validity_range <- function(gtfs) {
  no_range <- list(start = as.Date(NA), end = as.Date(NA))

  if (!is.null(gtfs$feed_info) &&
      all(c("feed_start_date", "feed_end_date") %in% names(gtfs$feed_info))) {
    start <- gtfs$feed_info$feed_start_date[1]
    end <- gtfs$feed_info$feed_end_date[1]
    if (!is.na(start) && !is.na(end)) return(list(start = start, end = end))
  }
  if (!is.null(gtfs$calendar) &&
      all(c("start_date", "end_date") %in% names(gtfs$calendar)) &&
      nrow(gtfs$calendar) > 0) {
    start <- suppressWarnings(min(gtfs$calendar$start_date, na.rm = TRUE))
    end <- suppressWarnings(max(gtfs$calendar$end_date, na.rm = TRUE))
    if (is.finite(start) && is.finite(end)) return(list(start = start, end = end))
  }
  if (!is.null(gtfs$calendar_dates) && "date" %in% names(gtfs$calendar_dates) &&
      nrow(gtfs$calendar_dates) > 0) {
    start <- suppressWarnings(min(gtfs$calendar_dates$date, na.rm = TRUE))
    end <- suppressWarnings(max(gtfs$calendar_dates$date, na.rm = TRUE))
    if (is.finite(start) && is.finite(end)) return(list(start = start, end = end))
  }
  no_range
}

# Returns list(routes_shapes_sf = ..., stops_sf = ..., validity_start = ...,
# validity_end = ...) built from a raw GTFS zip, regardless of its internal
# layout (flatten_gtfs_zip() normalizes it first) or where it came from
# (local file, upload, or downloaded feed URL).
build_gtfs_layers <- function(zip_path) {
  gtfs <- read_gtfs(flatten_gtfs_zip(zip_path))
  validity <- extract_gtfs_validity_range(gtfs)

  routes <- gtfs$routes |>
    mutate(
      route_color = normalize_color(route_color, "FFFFFF"),
      route_text_color = normalize_color(route_text_color, "000000")
    ) |>
    select(route_id, route_short_name, route_long_name, route_type,
           route_color, route_text_color)

  trip_shapes <- gtfs$trips |>
    filter(!is.na(shape_id), shape_id != "") |>
    distinct(shape_id, route_id, direction_id)

  # Shape-level detail: one row per shape_id, full route attributes attached.
  routes_shapes_sf <- shapes_as_sf(gtfs$shapes) |>
    inner_join(trip_shapes, by = "shape_id") |>
    inner_join(routes, by = "route_id") |>
    select(shape_id, route_id, direction_id, route_short_name,
           route_long_name, route_type, route_color, route_text_color)

  # Stops: retain serving route_ids, plus a stop_color matching GTFSx's stop
  # styling -- the primary (first, alphabetically) serving route's
  # route_color, falling back to GTFSx's default #8B7E74 for stops with no
  # assigned route.
  stop_route_pairs <- gtfs$stop_times |>
    distinct(stop_id, trip_id) |>
    inner_join(distinct(gtfs$trips, trip_id, route_id), by = "trip_id") |>
    distinct(stop_id, route_id) |>
    arrange(stop_id, route_id)

  stop_routes <- stop_route_pairs |>
    group_by(stop_id) |>
    summarise(route_ids = paste(unique(route_id), collapse = ","),
              primary_route_id = dplyr::first(route_id), .groups = "drop") |>
    left_join(select(routes, route_id, route_color),
              by = c("primary_route_id" = "route_id")) |>
    mutate(stop_color = ifelse(is.na(route_color), "#8B7E74", route_color)) |>
    select(stop_id, route_ids, stop_color)

  stops_sf <- stops_as_sf(gtfs$stops) |>
    left_join(stop_routes, by = "stop_id") |>
    mutate(stop_color = ifelse(is.na(stop_color), "#8B7E74", stop_color)) |>
    select(stop_id, stop_name, route_ids, stop_color)

  list(routes_shapes_sf = routes_shapes_sf, stops_sf = stops_sf,
       validity_start = validity$start, validity_end = validity$end)
}
