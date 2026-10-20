## ==========================================================================
##  R/fig_facility_map.R   (Figure 6: geographic location of health facilities)
##    source("R/fig_facility_map.R")
##    p <- fig_facility_map("mozambique")
##    save_fig(p, "figures/mozambique/facility_map_preview.png")
##  Needs: submissions/<slug>/facilities_<slug>.csv  (see R/facilities.R)
##         data/boundaries/<slug>/adm1.gpkg, adm2.gpkg
## ==========================================================================

source(file.path("R", "facilities.R"))

fig_facility_map <- function(slug) {
  library(ggplot2)
  s    <- get_country_settings(slug)
  dir  <- file.path("data", "boundaries", slug)
  adm1 <- sf::st_read(file.path(dir, "adm1.gpkg"), quiet = TRUE)
  adm2 <- sf::st_read(file.path(dir, "adm2.gpkg"), quiet = TRUE)
  f    <- read_facilities(slug, quiet = TRUE)
  f    <- f[order(f$tier, decreasing = TRUE), ]   # hospitals drawn on top of small facilities

  ggplot() +
    geom_sf(data = adm2, fill = "#F7F8FA", colour = det_cols$border2, linewidth = 0.1) +
    geom_sf(data = adm1, fill = NA, colour = det_cols$border1, linewidth = 0.4) +
    geom_sf(data = f, aes(fill = tier, shape = tier, size = tier),
            colour = "white", stroke = 0.25, alpha = 0.95) +
    scale_fill_manual(values = fac_tier_cols, labels = fac_tier_labels, name = NULL, drop = FALSE) +
    scale_shape_manual(values = fac_tier_shapes, labels = fac_tier_labels, name = NULL, drop = FALSE) +
    scale_size_manual(values = fac_tier_sizes, labels = fac_tier_labels, name = NULL, drop = FALSE) +
    guides(fill  = guide_legend(override.aes = list(size = unname(fac_tier_sizes + 1.2))),
           shape = guide_legend(), size = guide_legend()) +
    theme_det() +
    theme(legend.position = "bottom")
}

fig_facility_map_text <- function(slug) {
  s <- get_country_settings(slug)
  f <- read_facilities(slug, quiet = TRUE)
  n <- table(f$tier)
  list(
    caption = paste0("Geographic location of ", format(nrow(f), big.mark = ","),
                     " health facilities in ", s$country_name, " (",
                     n[["Tertiary"]], " tertiary, ", n[["Secondary"]], " secondary, ",
                     format(n[["Primary"]], big.mark = ","), " primary)."),
    source  = paste0(facility_source(slug), " Boundaries: ", boundary_source(slug))
  )
}
