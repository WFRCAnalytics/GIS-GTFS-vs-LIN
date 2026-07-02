# Reads the TDM transit network out of the zipped file geodatabase, layer
# names discovered dynamically from CITILABS_TRANSITGROUPS so this keeps
# working as more transit groups (e.g. local bus) are added to the gdb.
# The gdb currently only has rail_2023/wfrc_brt_2023 -- that's a placeholder
# subset, not the final network, so nothing here assumes a fixed route count.
#
# Run from the repo root: Rscript R/prepare_tdm.R

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
})

gdb <- "/vsizip/_data/tdm/WFv1000_MasterNet_20260430.gdb.zip"
out_dir <- "_data/tdm"

groups <- st_read(gdb, layer = "CITILABS_TRANSITGROUPS", quiet = TRUE)

read_group <- function(group_name) {
  line_layer <- paste0(group_name, "_PTLine")
  node_layer <- paste0(group_name, "_PTNode")

  routes <- st_read(gdb, layer = line_layer, quiet = TRUE) %>%
    mutate(tdm_group = group_name) %>%
    select(tdm_group, NAME, LONGNAME, MODE, OPERATOR,
           HEADWAY_1, HEADWAY_2, HEADWAY_3, HEADWAY_4, HEADWAY_5)

  stops <- st_read(gdb, layer = node_layer, quiet = TRUE) %>%
    filter(STOPNODE == 1) %>%
    mutate(tdm_group = group_name) %>%
    select(tdm_group, LINEID, SEQNO, NODES)

  list(routes = routes, stops = stops)
}

results <- lapply(groups$TRANSITGROUP_NAME, read_group)

tdm_routes_sf <- do.call(rbind, lapply(results, `[[`, "routes")) %>% st_transform(4326)
tdm_stops_sf  <- do.call(rbind, lapply(results, `[[`, "stops"))  %>% st_transform(4326)

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
st_write(tdm_routes_sf, file.path(out_dir, "tdm_routes.geojson"), delete_dsn = TRUE, quiet = TRUE)
st_write(tdm_stops_sf, file.path(out_dir, "tdm_stops.geojson"), delete_dsn = TRUE, quiet = TRUE)

message("Loaded ", nrow(tdm_routes_sf), " TDM route(s) across group(s): ",
        paste(groups$TRANSITGROUP_NAME, collapse = ", "))
