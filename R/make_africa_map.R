## ==========================================================================
##  R/make_africa_map.R
##  One-time helper, run by DET when the set of live/coming-soon countries
##  changes. Builds the homepage hero's Africa graphic as an inline SVG with
##  one <path> per country (real Natural Earth boundaries, not an
##  approximation), tagged by coverage status so styles.scss can color them.
##
##  Run from the repo root:
##    install.packages(c("rnaturalearth", "rnaturalearthdata"))  # one-time
##    source("R/make_africa_map.R")
##
##  Writes images/africa-map.svg, which index.qmd embeds inline (so its
##  paths can be styled/colored via CSS, unlike a plain <img>).
## ==========================================================================

for (p in c("sf", "rnaturalearth")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("Package '", p, "' is needed. install.packages('", p, "')")
}
suppressPackageStartupMessages({ library(sf) })

## Update these two lists when a country's status on the homepage changes.
live <- c(TZA = "tanzania", CMR = "cameroon", BEN = "benin", BFA = "burkina-faso",
          NGA = "nigeria", MOZ = "mozambique", AGO = "angola")
soon <- c("COD", "GHA", "KEN", "UGA", "ZMB", "MWI", "MLI", "NER", "RWA", "SEN", "SLE", "MDG")

africa <- rnaturalearth::ne_countries(scale = "small", continent = "Africa", returnclass = "sf")
africa <- sf::st_make_valid(africa)[, c("name", "iso_a3", "geometry")]

bbox <- sf::st_bbox(africa)
width <- 300
height <- width * (bbox["ymax"] - bbox["ymin"]) / (bbox["xmax"] - bbox["xmin"])

scale_x <- function(lon) (lon - bbox["xmin"]) / (bbox["xmax"] - bbox["xmin"]) * width
scale_y <- function(lat) height - (lat - bbox["ymin"]) / (bbox["ymax"] - bbox["ymin"]) * height

ring_to_path <- function(ring) {
  x <- scale_x(ring[, 1]); y <- scale_y(ring[, 2])
  paste0("M", paste(sprintf("%.2f,%.2f", x, y), collapse = "L"), "Z")
}

poly_to_path <- function(geom) {
  gtype <- sf::st_geometry_type(geom)
  parts <- character(0)
  if (gtype == "MULTIPOLYGON") {
    for (poly in sf::st_geometry(geom)[[1]]) for (ring in poly) parts <- c(parts, ring_to_path(ring))
  } else if (gtype == "POLYGON") {
    for (ring in sf::st_geometry(geom)[[1]]) parts <- c(parts, ring_to_path(ring))
  }
  paste(parts, collapse = " ")
}

lines <- character(0)
for (i in seq_len(nrow(africa))) {
  iso <- africa$iso_a3[i]
  d <- poly_to_path(africa[i, ])
  if (nchar(d) == 0) next
  cls <- "africa-country"
  slug_attr <- ""
  if (iso %in% names(live)) {
    cls <- paste0(cls, " africa-country--live")
    slug_attr <- paste0(' data-country="', live[[iso]], '"')
  } else if (iso %in% soon) {
    cls <- paste0(cls, " africa-country--soon")
  }
  lines <- c(lines, sprintf('<path class="%s" d="%s"%s></path>', cls, d, slug_attr))
}

svg <- paste0(
  '<svg viewBox="0 0 ', round(width, 1), ' ', round(height, 1),
  '" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" fill-rule="evenodd">\n',
  paste(lines, collapse = "\n"),
  '\n</svg>\n'
)

writeLines(svg, file.path("images", "africa-map.svg"))
message("Wrote images/africa-map.svg (", nrow(africa), " countries, viewBox ",
        round(width, 1), " x ", round(height, 1), ")")
