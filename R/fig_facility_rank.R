## ==========================================================================
##  R/fig_facility_rank.R   (Figure 5: health facilities by province, ranked)
##    source("R/fig_facility_rank.R")
##    p <- fig_facility_rank("mozambique")
##    save_fig(p, "figures/mozambique/facility_rank_preview.png", width = 9, height = 5.5)
##  Same input as the facility map (R/facilities.R).
## ==========================================================================

source(file.path("R", "facilities.R"))

fig_facility_rank_height <- function(slug) {
  n <- length(unique(sf::st_read(file.path("data", "boundaries", slug, "adm1.gpkg"), quiet = TRUE)$name_1))
  max(3.5, 1.2 + 0.38 * n)
}

fig_facility_rank <- function(slug) {
  library(ggplot2)
  adm1 <- sf::st_read(file.path("data", "boundaries", slug, "adm1.gpkg"), quiet = TRUE)
  f    <- sf::st_drop_geometry(read_facilities(slug, quiet = TRUE))
  f$name_1 <- gsub("\\b(De|Do|Da|Dos|Das)\\b", "\\L\\1", f$name_1, perl = TRUE)
  prov <- gsub("\\b(De|Do|Da|Dos|Das)\\b", "\\L\\1", adm1$name_1, perl = TRUE)

  tab <- as.data.frame(table(name_1 = factor(f$name_1, levels = prov), tier = f$tier),
                       stringsAsFactors = FALSE)
  tot <- stats::aggregate(Freq ~ name_1, tab, sum)
  tot <- tot[order(tot$Freq), ]                      # largest at the top after coord_flip
  tab$name_1 <- factor(tab$name_1, levels = tot$name_1)
  tab$tier   <- factor(tab$tier, levels = rev(fac_tier_levels))
  tot$name_1 <- factor(tot$name_1, levels = tot$name_1)

  ggplot(tab, aes(x = name_1, y = Freq, fill = tier)) +
    geom_col(width = 0.7) +
    geom_text(data = tot, aes(x = name_1, y = Freq, label = format(Freq, big.mark = ","), fill = NULL),
              hjust = -0.15, size = 3.3, colour = det_cols$ink) +
    coord_flip(clip = "off") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    scale_fill_manual(values = fac_tier_cols, labels = fac_tier_labels, name = NULL,
                      breaks = fac_tier_levels) +
    labs(x = NULL, y = "Number of health facilities") +
    theme_det() +
    theme(legend.position = "bottom", panel.grid.major.y = element_blank(),
          axis.text.y = element_text(colour = det_cols$ink, size = 10),
          axis.text.x = element_text(colour = det_cols$muted),
          axis.title.x = element_text(colour = det_cols$muted, margin = margin(t = 6)))
}

fig_facility_rank_text <- function(slug) {
  s <- get_country_settings(slug)
  f <- sf::st_drop_geometry(read_facilities(slug, quiet = TRUE))
  top <- names(sort(table(f$name_1), decreasing = TRUE))[1]
  list(
    caption = paste0("Number of health facilities by ", tolower(s$admin1_label), " and level of care, ",
                     s$country_name, " (total ", format(nrow(f), big.mark = ","), ")."),
    source  = paste0(facility_source(slug), " ", boundary_source(slug))
  )
}
