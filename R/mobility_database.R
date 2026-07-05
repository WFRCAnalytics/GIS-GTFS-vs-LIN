# Resolves a calendar date to a historical GTFS feed snapshot via the
# Mobility Database API (https://mobilitydatabase.org), so the "By date"
# GTFS source can fetch UTA's feed as it existed around an arbitrary past
# date instead of relying on a manually-curated _data/gtfs/ snapshot. The
# resulting zip is handed to the same build_gtfs_layers() every other GTFS
# source already uses (R/gtfs_pipeline.R) -- this module's only job is
# "date in, local zip path out".
#
# API contract below was NOT taken from the (incomplete) published OpenAPI
# spec alone -- the /v1/tokens endpoint isn't in that spec at all, so this
# was cross-checked against a real working third-party client
# (github.com/bdamokos/mobility-db-api's api.py) to confirm exact field
# names, since getting an underdocumented auth contract wrong fails
# silently in ways that are hard to debug from the Shiny side.

suppressPackageStartupMessages({
  library(httr2)
})

mdb_base_url <- "https://api.mobilitydatabase.org/v1"

# UTA's feed id in the Mobility Database catalog -- confirmed via the
# catalog UI (mobilitydatabase.org/feeds/gtfs/mdb-2349, "UTA GTFS Schedule
# Feed", producer https://gtfsfeed.rideuta.com/gtfs.zip). Hardcoded rather
# than looked up by name/location since this app only ever compares
# against UTA.
mdb_uta_feed_id <- "mdb-2349"

# Exchanges a Mobility Database refresh token (from the account page at
# mobilitydatabase.org, never committed to this repo -- read from the
# MOBILITY_DATABASE_REFRESH_TOKEN environment variable) for a short-lived
# access token. POST /v1/tokens with {"refresh_token": ...}, response
# field "access_token" -- confirmed against bdamokos/mobility-db-api's
# get_access_token(), since neither the field name nor even the endpoint
# itself appears in Mobility Database's published OpenAPI spec.
mdb_access_token <- function(refresh_token) {
  if (is.null(refresh_token) || !nzchar(refresh_token)) {
    stop("No Mobility Database refresh token configured (set the ",
         "MOBILITY_DATABASE_REFRESH_TOKEN environment variable).")
  }
  resp <- request(paste0(mdb_base_url, "/tokens")) |>
    req_headers(`Content-Type` = "application/json") |>
    req_body_json(list(refresh_token = refresh_token)) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200) {
    stop("Mobility Database token exchange failed (HTTP ", resp_status(resp), "): ",
         resp_body_string(resp))
  }
  token <- resp_body_json(resp)$access_token
  if (is.null(token) || !nzchar(token)) {
    stop("Mobility Database token response had no access_token field.")
  }
  token
}

# Lists every historical dataset snapshot Mobility Database has recorded
# for a feed (GET /v1/gtfs_feeds/{feed_id}/datasets, confirmed via the
# published OpenAPI spec: query params include downloaded_before/
# downloaded_after, response objects carry id/hosted_url/downloaded_at/
# service_date_range_start/service_date_range_end). Sorted newest-first by
# the API already; requests the max page size (500) since there's no
# dedicated "closest to a date" endpoint -- picking the right one from the
# full list is done client-side in mdb_resolve_feed_url().
mdb_list_datasets <- function(feed_id, access_token) {
  resp <- request(paste0(mdb_base_url, "/gtfs_feeds/", feed_id, "/datasets")) |>
    req_headers(Authorization = paste("Bearer", access_token)) |>
    req_url_query(limit = 500) |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) != 200) {
    stop("Mobility Database dataset list request failed (HTTP ", resp_status(resp), "): ",
         resp_body_string(resp))
  }
  resp_body_json(resp)
}

# Picks the dataset whose service_date_range brackets target_date; if none
# brackets it exactly (e.g. a date older than the earliest recorded
# snapshot, or a date past the end of the newest one's stated range),
# falls back to the dataset with the latest downloaded_at that is still
# <= target_date, and failing that, the single oldest dataset on record --
# on the reasoning that "the feed that was live as of that date" is a
# better approximation than refusing to answer at all. Returns NULL if the
# dataset list is empty (nothing recorded for this feed at all).
mdb_pick_dataset <- function(datasets, target_date) {
  if (length(datasets) == 0) return(NULL)

  starts <- as.Date(vapply(datasets, function(d) substr(d$service_date_range_start %||% NA, 1, 10), character(1)))
  ends <- as.Date(vapply(datasets, function(d) substr(d$service_date_range_end %||% NA, 1, 10), character(1)))
  downloaded <- as.Date(vapply(datasets, function(d) substr(d$downloaded_at %||% NA, 1, 10), character(1)))

  bracketing <- which(!is.na(starts) & !is.na(ends) & starts <= target_date & target_date <= ends)
  if (length(bracketing) > 0) return(datasets[[bracketing[1]]])

  before <- which(!is.na(downloaded) & downloaded <= target_date)
  if (length(before) > 0) return(datasets[[before[1]]])

  datasets[[length(datasets)]]
}

# Resolves target_date (a Date) to list(hosted_url, dataset_id,
# service_date_range_start, service_date_range_end) for UTA's feed, or
# stops with a clear error. This is the one function app.R calls -- token
# exchange and dataset listing are internal steps, not exposed separately,
# since every caller needs both together anyway.
mdb_resolve_feed_url <- function(target_date, refresh_token = Sys.getenv("MOBILITY_DATABASE_REFRESH_TOKEN")) {
  token <- mdb_access_token(refresh_token)
  datasets <- mdb_list_datasets(mdb_uta_feed_id, token)
  if (length(datasets) == 0) {
    stop("Mobility Database has no recorded datasets for feed ", mdb_uta_feed_id, ".")
  }
  chosen <- mdb_pick_dataset(datasets, target_date)
  list(
    hosted_url = chosen$hosted_url,
    dataset_id = chosen$id,
    service_date_range_start = as.Date(substr(chosen$service_date_range_start, 1, 10)),
    service_date_range_end = as.Date(substr(chosen$service_date_range_end, 1, 10))
  )
}

# Simple disk cache so re-picking a date already fetched this session (or
# in an earlier session) doesn't re-hit Mobility Database's API or
# re-download the same zip -- there is no cache anywhere else in the GTFS
# pipeline (by deliberate design, see gtfs_pipeline.R), but a live
# third-party API has a constraint a local file never does: an
# undocumented rate limit. Keyed by dataset_id (stable per historical
# snapshot), not by date, so two different dates that resolve to the same
# snapshot share one cached file. Lives outside the repo's tracked
# _data/gtfs/ on purpose -- these are fetched copies, not the
# hand-curated, committed snapshot set.
mdb_cache_dir <- "_data/gtfs_cache"

mdb_cached_download <- function(dataset_id, hosted_url) {
  dir.create(mdb_cache_dir, recursive = TRUE, showWarnings = FALSE)
  cached_path <- file.path(mdb_cache_dir, paste0(dataset_id, ".zip"))
  if (file.exists(cached_path)) return(cached_path)

  tmp <- tempfile(fileext = ".zip")
  download.file(hosted_url, tmp, mode = "wb", quiet = TRUE)
  file.copy(tmp, cached_path)
  cached_path
}
