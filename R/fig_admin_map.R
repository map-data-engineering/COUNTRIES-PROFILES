## ==========================================================================
##  R/fig_admin_map.R
##  Administrative boundary map for any country.
##    source("R/fig_admin_map.R")
##    p <- fig_admin_map("mozambique")
##    save_fig(p, "figures/mozambique/admin_map_preview.png")   # preview
##  Needs: data/boundaries/<slug>/adm1.gpkg and adm2.gpkg (fetch_boundaries.R)
##         config/country_settings.csv (one row per country)
##  The Source line for the profile comes from boundary_source(slug).
## ==========================================================================

source(file.path("R", "theme.R"))

## "Cidade De Maputo" -> "Cidade de Maputo"
tidy_names <- function(x) {
  gsub("\\b(De|Do|Da|Dos|Das)\\b", "\\L\\1", x, perl = TRUE)
}

## Panel positions are c(x, y, width, height) as fractions of the whole figure,
## measured from the bottom left. Defaults: Africa inset top left,
## zoom panel bottom left. Move them here if a country needs it.
fig_admin_map <- function(slug, label_min_share = 0.015,
                          inset_pos = c(0.02, 0.72, 0.18, 0.25),
                          zoom_pos  = c(0.02, 0.03, 0.20, 0.25)) {
  for (p in c("cowplot", "rnaturalearth", "rnaturalearthdata")) {
    if (!requireNamespace(p, quietly = TRUE))
      stop("Package '", p, "' is needed. install.packages('", p, "')")
  }
  s    <- get_country_settings(slug)
  dir  <- file.path("data", "boundaries", slug)
  adm1 <- sf::st_read(file.path(dir, "adm1.gpkg"), quiet = TRUE)
  adm2 <- sf::st_read(file.path(dir, "adm2.gpkg"), quiet = TRUE)

  ## Province names on admin 2 (use name_1 if present, else nearest admin 1)
  if (!"name_1" %in% names(adm2)) {
    pts  <- sf::st_point_on_surface(adm2)
    adm2$name_1 <- adm1$name_1[sf::st_nearest_feature(pts, adm1)]
  }
  adm1$name_1 <- tidy_names(adm1$name_1)
  adm2$name_1 <- tidy_names(adm2$name_1)
  adm1 <- adm1[order(adm1$name_1), ]
  cols <- stats::setNames(det_palette(nrow(adm1)), adm1$name_1)
  adm2$name_1 <- factor(adm2$name_1, levels = names(cols))

  cap <- sf::st_as_sf(data.frame(lon = s$capital_lon, lat = s$capital_lat,
                                 key = "Capital city"),
                      coords = c("lon", "lat"), crs = sf::st_crs(adm1))

  main <- ggplot() +
    geom_sf(data = adm2, aes(fill = name_1), colour = det_cols$border2, linewidth = 0.12) +
    geom_sf(data = adm1, fill = NA, colour = det_cols$border1, linewidth = 0.45) +
    geom_sf(data = cap, aes(shape = key), size = 3.2, stroke = 0.9,
            fill = "white", colour = det_cols$capital) +
    scale_fill_manual(values = cols, name = s$admin1_label, drop = FALSE) +
    scale_shape_manual(values = 21, name = NULL) +
    guides(fill  = guide_legend(order = 1),
           shape = guide_legend(order = 2,
                                override.aes = list(fill = "white", colour = det_cols$capital))) +
    theme_det() +
    det_map_grid()

  ## Names on the map only for units big enough to hold a label; the legend
  ## names every unit.
  if (isTRUE(s$label_admin1)) {
    a    <- as.numeric(sf::st_area(adm1))
    big  <- adm1[a / sum(a) >= label_min_share, ]
    lab  <- sf::st_point_on_surface(big)
    main <- main + geom_sf_text(data = lab, aes(label = name_1), size = 2.6,
                                colour = det_cols$text, fontface = "bold",
                                check_overlap = TRUE)
  }

  ## Optional zoom panel for a unit too small to see (for example a capital
  ## city province). Set zoom_admin1 in config/country_settings.csv.
  zoom_name <- if (is.null(s$zoom_admin1) || is.na(s$zoom_admin1)) "" else trimws(s$zoom_admin1)
  zoom <- NULL
  ## Hint: tell DET when the capital sits in a unit too small to read
  hit <- suppressWarnings(sf::st_intersects(cap, adm1)[[1]])
  if (length(hit) == 1 && !nzchar(zoom_name)) {
    share <- as.numeric(sf::st_area(adm1[hit, ])) / sum(as.numeric(sf::st_area(adm1)))
    if (share < label_min_share)
      message("Note: the capital sits in '", adm1$name_1[hit], "' (", round(100 * share, 1),
              "% of the country), too small to read. Consider setting zoom_admin1 for ", slug, ".")
  }
  if (nzchar(zoom_name)) {
    unit <- adm1[adm1$name_1 == tidy_names(zoom_name), ]
    if (nrow(unit) == 0) {
      warning("zoom_admin1 '", zoom_name, "' not found in admin 1 names. No zoom panel drawn.")
    } else {
      bb  <- sf::st_bbox(unit)
      pad <- 0.5 * max(bb["xmax"] - bb["xmin"], bb["ymax"] - bb["ymin"])
      xl  <- c(bb["xmin"] - pad, bb["xmax"] + pad)
      yl  <- c(bb["ymin"] - pad, bb["ymax"] + pad)
      box <- data.frame(xmin = xl[1], xmax = xl[2], ymin = yl[1], ymax = yl[2])
      main <- main + geom_rect(data = box, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
                               inherit.aes = FALSE, fill = NA,
                               colour = det_cols$text, linewidth = 0.5)
      zoom <- ggplot() +
        geom_sf(data = adm2, aes(fill = name_1), colour = det_cols$border2, linewidth = 0.2) +
        geom_sf(data = adm1, fill = NA, colour = det_cols$border1, linewidth = 0.6) +
        geom_sf(data = cap, shape = 21, size = 3, stroke = 0.9,
                fill = "white", colour = det_cols$capital) +
        geom_sf_text(data = sf::st_point_on_surface(unit), aes(label = name_1),
                     size = 2.4, fontface = "bold", colour = det_cols$text,
                     nudge_y = -0.35 * diff(yl) / 2) +
        scale_fill_manual(values = cols, guide = "none") +
        coord_sf(xlim = xl, ylim = yl, expand = FALSE) +
        theme_void() +
        theme(panel.border = element_rect(colour = det_cols$text, fill = NA, linewidth = 0.5),
              plot.background = element_rect(fill = "white", colour = NA))
    }
  }

  ## Scale bar and north arrow when ggspatial is installed
  if (requireNamespace("ggspatial", quietly = TRUE)) {
    main <- main +
      ggspatial::annotation_scale(location = "br", width_hint = 0.25, text_cex = 0.7) +
      ggspatial::annotation_north_arrow(location = "tr", which_north = "true",
                                        height = grid::unit(0.9, "cm"),
                                        width  = grid::unit(0.9, "cm"),
                                        style  = ggspatial::north_arrow_minimal())
  }

  ## Africa inset (Natural Earth), country highlighted
  africa  <- rnaturalearth::ne_countries(continent = "Africa", returnclass = "sf", scale = "medium")
  iso_col <- if ("iso_a3_eh" %in% names(africa)) "iso_a3_eh" else "iso_a3"
  inset <- ggplot() +
    geom_sf(data = africa, fill = det_cols$context, colour = "white", linewidth = 0.1) +
    geom_sf(data = africa[africa[[iso_col]] == s$iso3, ],
            fill = det_cols$highlight, colour = "white", linewidth = 0.1) +
    theme_void() +
    theme(panel.border = element_rect(colour = det_cols$text, fill = NA, linewidth = 0.4),
          plot.background = element_rect(fill = "white", colour = NA))

  out <- cowplot::ggdraw(main) +
    cowplot::draw_plot(inset, x = inset_pos[1], y = inset_pos[2], width = inset_pos[3], height = inset_pos[4])
  if (!is.null(zoom))
    out <- out + cowplot::draw_plot(zoom, x = zoom_pos[1], y = zoom_pos[2], width = zoom_pos[3], height = zoom_pos[4])
  out
}

## Text for the profile: caption and source line
fig_admin_map_text <- function(slug) {
  s    <- get_country_settings(slug)
  dir  <- file.path("data", "boundaries", slug)
  n1   <- nrow(sf::st_read(file.path(dir, "adm1.gpkg"), quiet = TRUE))
  n2   <- nrow(sf::st_read(file.path(dir, "adm2.gpkg"), quiet = TRUE))
  list(
    caption = paste0("Administrative geography of ", s$country_name, ": ",
                     n1, " ", tolower(s$admin1_label), "s and ",
                     n2, " ", tolower(s$admin2_label), "s."),
    source  = boundary_source(slug)
  )
}
