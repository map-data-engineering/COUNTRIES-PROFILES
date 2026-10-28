## ==========================================================================
##  ADMINSTARTIVE BOUNDARIES STUDY AREA MAP
##  Admin1 (Provinces) + Admin2 (Districts) choropleth, capital city,
##  north arrow, scale bar, graticule frame, and an Africa-location inset
##  (OpenStreetMap tile basemap) — all composed as ONE bordered layout,
##  mirroring the reference figure.
##
##  Folder expected to contain shapefiles for Admin1, Admin2 (Admin3 is
##  read but not plotted here).
## ==========================================================================

## ---- 0. PACKAGES ---------------------------------------------------------
## `rosm` + `prettymapr` are needed by ggspatial::annotation_map_tile() to
## fetch OpenStreetMap tiles for the locator inset (requires internet access).
required_pkgs <- c("sf", "dplyr", "ggplot2", "ggspatial", "cowplot",
                   "rnaturalearth", "rnaturalearthdata", "stringr",
                   "rosm", "prettymapr")
#prettymapr: Makes maps looks polished
#cowplot: Lets you arrange multiple ggplot2 plots into one figure, align them, and add labels or shared legends.#z
#rosm: Adds OpenStreetMap backgrounds

new_pkgs <- required_pkgs[!(required_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs) > 0) install.packages(new_pkgs, dependencies = TRUE)

library(sf)
library(dplyr)
library(ggplot2)
library(ggspatial)
library(cowplot)
library(rnaturalearth)
library(rnaturalearthdata)
library(stringr)

## ---- 1. WORKING DIRECTORY & FILE DISCOVERY --------------------------------
wd <- "C:/Users/HP/Desktop/Map's_Project/Country_Profile/Mozambique/Data/shapefiles"
setwd(wd)

all_shp <- list.files(wd, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)
if (length(all_shp) == 0) stop("No .shp files found in: ", wd)

cat("Shapefiles found:\n"); print(all_shp)

find_shp <- function(level) {
  patt <- paste0("(_", level, "\\.shp$)|(adm", level, ")|(admin", level, ")|(level", level, ")")
  hit  <- all_shp[str_detect(str_to_lower(all_shp), patt)]
  if (length(hit) == 0) stop("Could not auto-detect Admin", level, " shapefile. ",
                             "Edit `find_shp()` or set the path manually.")
  hit[1]
}

adm1_path <- find_shp(1)
adm2_path <- find_shp(2)
adm3_path <- tryCatch(find_shp(3), error = function(e) NA)

cat("\nUsing:\n Admin1 ->", adm1_path,
    "\n Admin2 ->", adm2_path,
    "\n Admin3 ->", ifelse(is.na(adm3_path), "(not found / not used)", adm3_path), "\n")

## ---- 2. READ SHAPEFILES ---------------------------------------------------
adm1 <- st_read(adm1_path, quiet = TRUE) %>% st_make_valid()
adm2 <- st_read(adm2_path, quiet = TRUE) %>% st_make_valid()
if (!is.na(adm3_path)) adm3 <- st_read(adm3_path, quiet = TRUE) %>% st_make_valid()

adm1 <- st_transform(adm1, 4326)
adm2 <- st_transform(adm2, 4326)

## ---- 3. IDENTIFY NAME & CODE FIELDS ---------------------------------------
name1_field <- intersect(c("adm1_name", "NAME_1", "ADM1_PT", "ADM1_EN", "PROVINCE", "Province"), names(adm1))[1]
name2_field <- intersect(c("adm2_name", "NAME_2", "ADM2_PT", "ADM2_EN", "DISTRICT", "District"), names(adm2))[1]
code1_field <- intersect(c("adm1_pcode", "ADM1_PCODE", "GID_1", "ID_1"), names(adm1))[1]
code_link_field <- intersect(c("adm1_pcode", "ADM1_PCODE", "GID_1", "ID_1"), names(adm2))[1]

if (is.na(name1_field)) stop("Could not find a province-name column in Admin1.")
if (is.na(name2_field)) stop("Could not find a district-name column in Admin2.")
if (is.na(code1_field)) stop("Could not find a province CODE column in Admin1.")
if (is.na(code_link_field)) stop("Could not find the parent-province CODE column inside Admin2.")

adm1 <- adm1 %>% rename(PROVINCE = all_of(name1_field), PROVINCE_CODE = all_of(code1_field))
adm2 <- adm2 %>% rename(DISTRICT = all_of(name2_field), PROVINCE_CODE = all_of(code_link_field))

province_lookup <- adm1 %>% st_drop_geometry() %>% select(PROVINCE_CODE, PROVINCE)

## ---- 4. DISTRICT COUNT PER PROVINCE & COLOUR PALETTE ----------------------
province_counts <- adm2 %>%
  st_drop_geometry() %>%
  count(PROVINCE_CODE, name = "n_districts") %>%
  left_join(province_lookup, by = "PROVINCE_CODE") %>%
  arrange(PROVINCE)

n_prov <- nrow(province_counts)

## Gold -> grey -> black ramp (light to dark), one shade per province
gold_ramp <- colorRampPalette(c("#FBEBB5", "#D4AF37", "#8C8C8C", "#1A1A1A"))(n_prov)
province_counts$fill_color <- gold_ramp

province_counts <- province_counts %>%
  mutate(district_word = ifelse(n_districts == 1, "District", "Districts"),
         legend_label  = paste0(PROVINCE, " (", n_districts, " ", district_word, ")"))

adm2 <- adm2 %>%
  left_join(province_counts %>% select(PROVINCE_CODE, fill_color, legend_label),
            by = "PROVINCE_CODE")

adm2$legend_label <- factor(adm2$legend_label, levels = province_counts$legend_label)
fill_values <- setNames(province_counts$fill_color, province_counts$legend_label)

## ---- 5. PROVINCE LABEL POSITIONS ------------------------------------------
adm1_labels <- adm1 %>%
  st_point_on_surface() %>%
  mutate(lon = st_coordinates(.)[, 1],
         lat = st_coordinates(.)[, 2])

## ---- 6. CAPITAL CITY -------------------------------------------------------
capital <- st_as_sf(
  data.frame(name = "Cidade de Maputo", lon = 32.5732, lat = -25.9692),
  coords = c("lon", "lat"), crs = 4326
)

## ---- 7. MAIN MAP -----------------------------------------------------------
## Colours -- gold / black / grey theme
bg_col     <- "#C9C6BD"   # neutral warm-grey background (replaces the old green)
admin1_col <- "#D4AF37"   # gold province boundaries
admin2_col <- "#2B2B2B"   # near-black district boundaries

bbox <- st_bbox(adm1)

## Widen the plotted extent WEST of Mozambique's own bounding box. This is
## the key fix so the inset + legend sit truly *inside* the main map's own
## panel (and therefore inside its single black neatline/frame), instead of
## floating as separate boxes outside it. Padding amounts are tuned to match
## the reference figure's proportions.
xlim_main <- c(bbox["xmin"] - 18, bbox["xmax"] + 1.7)
ylim_main <- c(bbox["ymin"] - 1.6, bbox["ymax"] + 1.7)

## Small helper: draws province names in a translucent white label box so
## they stay legible whether they land on light-gold or near-black fills.
main_map <- ggplot() +
  geom_sf(data = adm2, aes(fill = legend_label), color = admin2_col, linewidth = 0.12) +
  geom_sf(data = adm1, fill = NA, color = admin1_col, linewidth = 1.1) +
  geom_label(data = adm1_labels, aes(x = lon, y = lat, label = PROVINCE),
             color = "white", fill = "grey", alpha = 0.6,
             fontface = "bold", size = 3.5, label.size = 0,
             label.padding = unit(0.15, "lines"), label.r = unit(0.05, "lines")) +
  geom_sf(data = capital, color = "red", size = 3) +
  scale_fill_manual(name = "Admin2", values = fill_values, drop = FALSE) +
  scale_x_continuous(sec.axis = dup_axis(name = NULL)) +
  scale_y_continuous(sec.axis = dup_axis(name = NULL)) +
  coord_sf(xlim = xlim_main, ylim = ylim_main, expand = FALSE) +
  annotation_scale(location = "bl", width_hint = 0.22,
                   bar_cols = c("black", "white"),
                   pad_x = unit(0.35, "npc"), pad_y = unit(0.04, "npc")) +
  annotation_north_arrow(location = "tr", which_north = "true",
                         style = north_arrow_fancy_orienteering(),
                         height = unit(1.4, "cm"), width = unit(1.4, "cm")) +
  labs(x = NULL, y = NULL) +
  theme_bw(base_size = 12) +
  theme(
    ## The BLACK "neatline" is drawn only around the panel (not around the
    ## axis-label margin) so degree labels sit OUTSIDE the frame, exactly
    ## like the reference figure. Because xlim_main/ylim_main above now
    ## extend well west of Mozambique itself, this SAME border and SAME
    ## panel also encloses the inset + legend overlaid on top of it.
    panel.background = element_rect(fill = bg_col, color = NA),
    panel.border     = element_rect(color = "black", fill = NA, linewidth = 1.3),
    panel.grid.major = element_line(color = "grey55", linewidth = 0.3),
    plot.background  = element_rect(fill = bg_col, color = NA),
    plot.margin      = margin(6, 10, 6, 6),
    legend.position  = "none"
  )

## ---- 8. AFRICA LOCATOR INSET (OpenStreetMap tile basemap) -----------------
moz_outline <- st_union(adm1)   # dissolved national boundary, used to highlight Mozambique

## annotation_map_tile() only works reliably in Web Mercator (EPSG:3857) --
## passing plain lon/lat limits to coord_sf() makes it mis-read the extent
## as if it were already in metres, so it zooms in on a tiny near-(0,0)
## square instead of the whole continent. We therefore compute our desired
## Africa bounding box (lon -20/55, lat -36/38) in EPSG:3857 metres first.
africa_bbox_3857 <- st_as_sf(
  data.frame(lon = c(-20, 55), lat = c(-36, 38)),
  coords = c("lon", "lat"), crs = 4326
) %>% st_transform(3857) %>% st_coordinates()

build_inset <- function() {
  ggplot() +
    annotation_map_tile(type = "osm", zoomin = -1, progress = "none") +
    geom_sf(data = moz_outline, fill = NA, color = "black", linewidth = 1.2) +
    coord_sf(crs = 3857,
             xlim = africa_bbox_3857[, "X"], ylim = africa_bbox_3857[, "Y"],
             expand = FALSE) +
    labs(x = NULL, y = NULL) +
    theme_bw(base_size = 7) +
    theme(
      panel.background = element_rect(fill = "aliceblue"),
      panel.border     = element_rect(color = "black", fill = NA, linewidth = 1),
      plot.background  = element_rect(fill = "white", color = "black", linewidth = 1),
      plot.margin      = margin(3, 3, 3, 3)
    )
}

inset_map <- tryCatch(
  {
    p <- build_inset()
    ggsave(tempfile(fileext = ".png"), p, width = 2, height = 2, dpi = 50)  # force full render now
    p
  },
  error = function(e) {
    message("OSM tiles unavailable (", conditionMessage(e), ") - falling back to vector basemap.")
    africa <- ne_countries(continent = "Africa", scale = "medium", returnclass = "sf")
    ggplot() +
      geom_sf(data = africa, fill = "#EDE7D9", color = "grey40", linewidth = 0.2) +
      geom_sf(data = moz_outline, fill = NA, color = "black", linewidth = 1.2) +
      coord_sf(xlim = c(-20, 55), ylim = c(-36, 38), expand = FALSE) +
      labs(x = NULL, y = NULL) +
      theme_bw(base_size = 7) +
      theme(panel.background = element_rect(fill = "aliceblue"),
            panel.border     = element_rect(color = "black", fill = NA, linewidth = 1),
            plot.background  = element_rect(color = "black", linewidth = 1),
            plot.margin      = margin(3, 3, 3, 3))
  }
)

## ---- 9. STAND-ALONE LEGEND (mimics the reference figure's legend box) -----
y0        <- 7
row_gap   <- 0.6
legend_plot <- ggplot() +
  annotate("text",  x = -0.15, y = 11.4, label = "Legend", hjust = 0, size = 6) +
  annotate("point", x = 0, y = 10.4, color = "red", size = 3) +
  annotate("text",  x = 0.35, y = 10.4, label = "Capital City", hjust = 0, size = 4) +
  annotate("segment", x = -0.12, xend = 0.12, y = 9.6, yend = 9.6, color = "black", linewidth = 1.1) +
  annotate("text",  x = 0.35, y = 9.6, label = "Admin1", hjust = 0, size = 4) +
  annotate("text",  x = -0.15, y = 8.6, label = "Admin2", hjust = 0, size = 4.4, fontface = "bold") +
  geom_tile(data = province_counts,
            aes(x = 0, y = y0 - (row_number(PROVINCE) - 1) * row_gap,
                fill = legend_label), width = 0.32, height = 0.4, show.legend = FALSE) +
  geom_text(data = province_counts,
            aes(x = 0.35, y = y0 - (row_number(PROVINCE) - 1) * row_gap, label = legend_label),
            hjust = 0, size = 3.5) +
  scale_fill_manual(values = fill_values) +
  coord_cartesian(xlim = c(-0.3, 3.6),
                  ylim = c(y0 - (n_prov - 1) * row_gap - 0.6, 12.2), expand = FALSE) +
  theme_void() +
  theme(plot.background = element_rect(color = "black", linewidth = 0.5),
        plot.margin     = margin(6, 6, 6, 6))

## ---- 10. COMBINE MAIN MAP + INSET + LEGEND --------------------------------
## The main map fills the WHOLE canvas edge-to-edge. Because Mozambique's
## boomerang shape leaves its own NW corner empty (just background colour +
## graticule), the inset and legend are simply overlaid on top of that empty
## space -- exactly as in the reference figure -- instead of being boxed
## into a separate column. This avoids any duplicate/offset frame.
final_map <- ggdraw() + 
  draw_plot(main_map,   x = 0,     y = 0,    width = 1,    height = 1) +
  draw_plot(inset_map,  x = 0.045, y = 0.6, width = 0.285, height = 0.345) +
  draw_plot(legend_plot, x = 0.075, y = 0.0575, width = 0.285, height = 0.50) +
  theme(plot.background = element_rect(fill = bg_col, color = NA))

print(final_map)

## ---- 11. EXPORT -------------------------------------------------------------
out_dir <- file.path(wd, "..", "..", "Outputs")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ggsave(file.path(out_dir, "Mozambique_StudyArea_Map.png"),
       plot = final_map, width = 13, height = 9.3, dpi = 300, bg = bg_col)

ggsave(file.path(out_dir, "Mozambique_StudyArea_Map.pdf"),
       plot = final_map, width = 13, height = 9.3, bg = bg_col)

cat("\nMap exported to:", normalizePath(out_dir), "\n")