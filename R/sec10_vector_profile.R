## ==========================================================================
##  R/sec10_vector_profile.R   (Section 10: vector profile)
##  Everything DET owns in Section 10, in one file:
##    1. fetch_vector_distribution(): one-time download of MAP vector surfaces,
##       averaged by district, saved to data/vectors/<slug>/ (needs internet)
##    2. fig_vectors(): Figure 15, distribution of the major vectors by district
##    3. tbl_susceptibility(), tbl_vector_summary(): the insecticide susceptibility
##       table and the vector and parasite summary table, built from the
##       researcher's tabs "Insecticide_susceptibility" and the Data tab (Types = Vectors)
##       in the epi workbook (template: insecticide_resistance_*.xlsx)
##    4. resistance_checks(): console report on the tabs, run by the generator
##
##  One time per country (DET):
##    source("R/sec10_vector_profile.R")
##    fetch_vector_distribution("mozambique")
##  Preview:
##    save_fig(fig_vectors("mozambique"), "figures/mozambique/vectors_preview.png", width = 9, height = 9)
## ==========================================================================

source(file.path("R", "theme.R"))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

## Search words used to find each species in the MAP raster list.
## Label on the figure = name; value = words to look for in the surface title.
vec_species <- c("An. funestus"     = "funestus",
                 "An. arabiensis"   = "arabiensis",
                 "An. gambiae s.s." = "gambiae",
                 "An. merus"        = "merus")

## --------------------------------------------------------------------------
##  1. One-time download (DET)
## --------------------------------------------------------------------------
fetch_vector_distribution <- function(slug, species = vec_species, surfaces = NULL) {
  for (p in c("malariaAtlas", "terra", "sf"))
    if (!requireNamespace(p, quietly = TRUE)) stop("Package '", p, "' is needed. install.packages('", p, "')")
  dir  <- file.path("data", "boundaries", slug)
  adm2 <- vec_adm2(slug)
  adm0 <- sf::st_union(sf::st_read(file.path(dir, "adm1.gpkg"), quiet = TRUE))

  lr  <- as.data.frame(malariaAtlas::listRaster(printed = FALSE))
  ## Match on the surface id and title only (descriptions mention other species)
  idt <- tolower(paste(lr$dataset_id, if ("title" %in% names(lr)) lr$title else ""))
  is_vector <- grepl("anophele", idt)

  ## surfaces = c("An. funestus" = "dataset_id", ...) forces a choice; otherwise search.
  ## Preference: An. arabiensis from Sinka 2010; the others from Wiebe 2017;
  ## species level before group, subgroup or complex surfaces.
  chosen <- list()
  for (lab in names(species)) {
    id <- surfaces[[lab]]
    if (is.null(id)) {
      hit <- which(is_vector & grepl(species[[lab]], idt))
      if (length(hit)) {
        coarse <- grepl("group|subgroup|complex", idt[hit])
        yr     <- if (grepl("arabiensis", species[[lab]])) "2010" else "2017"
        score  <- (!coarse) * 2 + grepl(paste0("__", yr, "_"), lr$dataset_id[hit])
        hit    <- hit[order(-score)]
      }
      message("\n", lab, ": ", length(hit), " matching surface(s)",
              if (length(hit)) paste0(", using ", lr$dataset_id[hit[1]]) else ", none found, skipped")
      if (length(hit) > 1) message("  other matches: ", paste(lr$dataset_id[hit[-1]], collapse = ", "))
      if (!length(hit)) next
      id <- lr$dataset_id[hit[1]]
    }
    chosen[[lab]] <- lr[lr$dataset_id == id, , drop = FALSE][1, ]
  }
  if (!length(chosen)) stop("No vector surfaces found in malariaAtlas::listRaster().")

  ## Download one surface for the country. Tries the country outline first, then its bounding box.
  to_spat <- function(r) {
    if (is.list(r) && !inherits(r, c("SpatRaster", "RasterLayer", "RasterStack", "RasterBrick"))) r <- r[[1]]
    if (inherits(r, "SpatRaster")) r else terra::rast(r)
  }
  has_data <- function(r) {
    ok <- tryCatch(is.finite(terra::global(r[[1]], "max", na.rm = TRUE)[1, 1]), error = function(e) FALSE)
    isTRUE(ok)
  }
  bb <- sf::st_bbox(adm0)
  ext <- matrix(c(bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]), nrow = 2,
                dimnames = list(c("x", "y"), c("min", "max")))
  get_r <- function(row) {
    f <- names(formals(malariaAtlas::getRaster))
    tries <- list(
      outline = function() if ("dataset_id" %in% f) malariaAtlas::getRaster(dataset_id = row$dataset_id, shp = sf::st_sf(geometry = adm0))
                           else malariaAtlas::getRaster(surface = row$title, shp = sf::st_sf(geometry = adm0)),
      box     = function() if ("dataset_id" %in% f) malariaAtlas::getRaster(dataset_id = row$dataset_id, extent = ext)
                           else malariaAtlas::getRaster(surface = row$title, extent = ext))
    for (nm in names(tries)) {
      r <- tryCatch(to_spat(tries[[nm]]()), error = function(e) { message("  ", nm, " request failed: ", conditionMessage(e)); NULL })
      if (!is.null(r) && has_data(r)) return(r)
      if (!is.null(r)) message("  ", nm, " request returned a raster with no values: ", paste(utils::capture.output(print(r)), collapse = " | "))
    }
    stop("no values returned by MAP for this surface")
  }

  out <- data.frame(name_1 = adm2$name_1, name_2 = adm2$name_2, stringsAsFactors = FALSE)
  meta <- data.frame()
  v <- terra::vect(adm2)
  for (lab in names(chosen)) {
    row <- chosen[[lab]]
    message("Downloading ", lab, ": ", row$dataset_id)
    vals <- tryCatch({
      r <- get_r(row)
      as.numeric(terra::extract(r, v, fun = mean, na.rm = TRUE)[[2]])
    }, error = function(e) { message("  skipped ", lab, ": ", conditionMessage(e)); NULL })
    if (is.null(vals)) next
    out[[lab]] <- vals
    meta <- rbind(meta, data.frame(species = lab, dataset_id = row$dataset_id,
                                   title = as.character(row$title %||% ""),
                                   retrieved_date = as.character(Sys.Date()),
                                   malariaAtlas_version = as.character(utils::packageVersion("malariaAtlas")),
                                   stringsAsFactors = FALSE))
  }
  if (nrow(meta) == 0) stop("No surface could be downloaded. See the messages above.")
  od <- file.path("data", "vectors", slug); dir.create(od, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out,  file.path(od, "vector_by_district.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(meta, file.path(od, "vector_surfaces.csv"),    row.names = FALSE, fileEncoding = "UTF-8")
  message("\nSaved ", nrow(out), " districts x ", nrow(meta), " species to ", od,
          ". CHECK the surface titles printed above are the species and source you intend (see Source line).")
  invisible(out)
}

## admin 2 with province names
vec_adm2 <- function(slug) {
  dir  <- file.path("data", "boundaries", slug)
  adm1 <- sf::st_read(file.path(dir, "adm1.gpkg"), quiet = TRUE)
  adm2 <- sf::st_read(file.path(dir, "adm2.gpkg"), quiet = TRUE)
  if (!"name_1" %in% names(adm2)) {
    suppressMessages(sf::sf_use_s2(FALSE)); on.exit(suppressMessages(sf::sf_use_s2(TRUE)), add = TRUE)
    adm2$name_1 <- adm1$name_1[sf::st_nearest_feature(sf::st_point_on_surface(adm2), adm1)]
  }
  adm2
}

## --------------------------------------------------------------------------
##  2. Figure 15
## --------------------------------------------------------------------------
read_vectors <- function(slug) {
  f <- file.path("data", "vectors", slug, "vector_by_district.csv")
  if (!file.exists(f)) stop("Missing ", f, ". Run fetch_vector_distribution('", slug, "') first.")
  utils::read.csv(f, check.names = FALSE, fileEncoding = "UTF-8", stringsAsFactors = FALSE)
}

fig_vectors_height <- function(slug) {
  n <- ncol(read_vectors(slug)) - 2
  ceiling(n / 4) * 4.6 + 1.4
}

fig_vectors <- function(slug) {
  library(ggplot2)
  d    <- read_vectors(slug)
  sp   <- setdiff(names(d), c("name_1", "name_2"))
  adm2 <- vec_adm2(slug)
  adm1 <- sf::st_read(file.path("data", "boundaries", slug, "adm1.gpkg"), quiet = TRUE)
  key  <- function(a, b) paste(a, b, sep = "||")
  long <- do.call(rbind, lapply(sp, function(s) {
    x <- adm2
    x$value   <- d[[s]][match(key(adm2$name_1, adm2$name_2), key(d$name_1, d$name_2))]
    x$species <- s
    x[, c("value", "species")]
  }))
  long$species <- factor(long$species, levels = sp)
  if (anyNA(long$value)) message(sum(is.na(long$value)), " district values are missing (shown grey).")

  ggplot() +
    geom_sf(data = long, aes(fill = value), colour = NA) +
    geom_sf(data = adm1, fill = NA, colour = det_cols$border1, linewidth = 0.25) +
    facet_wrap(~species, ncol = min(length(sp), 4)) +
    scale_fill_viridis_c(option = "mako", direction = -1, end = 0.85, limits = c(0, 1), na.value = "grey85",
                         name = "Relative probability\nof occurrence",
                         guide = guide_colourbar(barwidth = 12, barheight = 0.6, title.position = "top")) +
    theme_det() +
    theme(legend.position = "bottom",
          strip.background = element_blank(),
          strip.text = element_text(face = "italic", hjust = 0.5, size = 11, margin = margin(t = 4, b = 8)),
          panel.spacing = grid::unit(0.8, "lines"))
}

fix_utf8 <- function(x) {          # repairs "DÃ¶nitz" style text
  bad <- !is.na(x) & grepl("\u00c3|\u00c2", x)
  if (any(bad)) { y <- iconv(x[bad], "UTF-8", "latin1"); Encoding(y) <- "UTF-8"; x[bad] <- ifelse(is.na(y), x[bad], y) }
  x
}

fig_vectors_text <- function(slug) {
  s <- get_country_settings(slug)
  d <- read_vectors(slug); n <- ncol(d) - 2
  m <- utils::read.csv(file.path("data", "vectors", slug, "vector_surfaces.csv"),
                       stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  list(
    caption = paste0("Modelled relative probability of occurrence of ", n, " dominant malaria vector species by ",
                     tolower(s$admin2_label), ", ", s$country_name, ".",
                     if (anyNA(d[, setdiff(names(d), c("name_1", "name_2")), drop = FALSE])) " Grey areas have no data in the surface." else ""),
    source  = paste0("Malaria Atlas Project (malariaAtlas package, retrieved ", m$retrieved_date[1], "): ",
                     paste(unique(fix_utf8(m$title[nzchar(m$title)])), collapse = "; "),
                     ". Each ", tolower(s$admin2_label), " shows the mean of the surface within it. ",
                     boundary_source(slug))
  )
}

## --------------------------------------------------------------------------
##  3. Insecticide susceptibility table and vector summary table, from the researcher's tabs
## --------------------------------------------------------------------------
res_cols <- c(Susceptible = "#009E73", "Possible resistance" = "#B8860B",
              Resistant = "#D55E00", Mixed = "#6B7280")

res_esc <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
res_year <- function(a, b) {
  a <- suppressWarnings(as.integer(a)); b <- suppressWarnings(as.integer(b))
  ifelse(is.na(b) | a == b, as.character(a), paste0(a, "–", b))
}
## WHO thresholds: 98% or more susceptible, 90 to 97% possible resistance, below 90% resistant
res_status <- function(mort, fallback) {
  ifelse(!is.na(mort),
         ifelse(mort >= 98, "Susceptible", ifelse(mort >= 90, "Possible resistance", "Resistant")),
         as.character(fallback))
}
res_source_cell <- function(src, doi) {
  src <- res_esc(src); doi <- trimws(as.character(doi)); doi[is.na(doi)] <- ""
  ifelse(nzchar(doi), paste0('<a href="', doi, '">', src, "</a>"), src)
}
.res_need <- function(d, cols, sheet) {
  miss <- setdiff(cols, names(d))
  if (length(miss)) stop("The ", sheet, " tab is missing column(s): ", paste(miss, collapse = ", "),
                         ". Copy the tab again from the DET template.")
}

read_susceptibility <- function(slug) {
  d <- read_epi_sheet(slug, "Insecticide_susceptibility")
  .res_need(d, c("Year_start", "Species", "Insecticide", "Class", "Mortality_pct",
                 "Status_if_no_mortality", "Sites", "Source"), "Insecticide_susceptibility")
  if (!"Year_end" %in% names(d)) d$Year_end <- d$Year_start
  if (!"DOI" %in% names(d)) d$DOI <- ""
  d <- d[!is.na(d$Species) | !is.na(d$Insecticide), ]
  d$Mortality_pct <- suppressWarnings(as.numeric(d$Mortality_pct))
  d$Status <- res_status(d$Mortality_pct, d$Status_if_no_mortality)
  d[order(d$Year_start, d$Species, d$Insecticide), ]
}

tbl_susceptibility <- function(slug) {
  d <- read_susceptibility(slug)
  col <- res_cols[d$Status]; col[is.na(col)] <- "#6B7280"
  res <- paste0('<span style="color:', col, ';font-weight:600">', res_esc(d$Status), "</span>",
                ifelse(is.na(d$Mortality_pct), "", paste0(" (", format(d$Mortality_pct, trim = TRUE, drop0trailing = TRUE), "% mortality)")))
  data.frame(
    Year        = res_year(d$Year_start, d$Year_end),
    Species     = paste0("<em>", res_esc(d$Species), "</em>"),
    Insecticide = paste0(res_esc(d$Insecticide), ifelse(is.na(d$Class), "", paste0(" (", tolower(res_esc(d$Class)), ")"))),
    Result      = res,
    Sites       = res_esc(d$Sites),
    Source      = res_source_cell(d$Source, d$DOI),
    stringsAsFactors = FALSE, check.names = FALSE)
}

## Table of vector and parasite species facts, from the Data tab (Types = Vectors).
## Only the metrics in config/display_vectors.csv are shown, in that order. Other
## 'Vectors' rows are ignored here. Columns used: Metric, Value; Source, Link if present.
vector_summary_rows <- function(slug) {
  d <- read_epi_sheet(slug, "Data")
  .res_need(d, c("Types", "Country", "Metric", "Value"), "Data")
  cn <- get_country_settings(slug)$country_name
  disp <- utils::read.csv(file.path("config", "display_vectors.csv"), stringsAsFactors = FALSE,
                          na.strings = "", fileEncoding = "UTF-8")
  key <- function(x) tolower(trimws(as.character(x)))
  d <- d[!is.na(d$Types) & d$Types == "Vectors" & !is.na(d$Country) & d$Country == cn &
         !is.na(d$Value) & nzchar(trimws(as.character(d$Value))), , drop = FALSE]
  shown <- key(d$Metric) %in% key(disp$Metric)
  list(shown = d[shown, , drop = FALSE][order(match(key(d$Metric[shown]), key(disp$Metric))), , drop = FALSE],
       ignored = d$Metric[!shown], display = disp$Metric)
}

tbl_vector_summary <- function(slug) {
  r <- vector_summary_rows(slug); d <- r$shown
  if (!"Source" %in% names(d)) d$Source <- NA_character_
  if (!"Link"   %in% names(d)) d$Link   <- NA_character_
  ital <- function(x) {                       # species names in italics, in HTML
    x <- res_esc(x)
    if (exists("italicise_species")) x <- italicise_species(x)
    unname(gsub("\\*([^*]+)\\*", "<em>\\1</em>", x))
  }
  out <- data.frame(Metric = res_esc(d$Metric), Value = ital(d$Value), stringsAsFactors = FALSE)
  has_src <- !is.na(d$Source) & nzchar(trimws(as.character(d$Source)))
  if (any(has_src)) out$Source <- ifelse(has_src, res_source_cell(d$Source, d$Link), "")
  out
}

## --------------------------------------------------------------------------
##  4. Checks, printed when the page is generated
## --------------------------------------------------------------------------
resistance_checks <- function(slug) {
  d <- tryCatch(read_susceptibility(slug), error = function(e) { message("  ", conditionMessage(e)); NULL })
  if (is.null(d)) return(invisible(NULL))
  cat("Resistance tab: ", nrow(d), " susceptibility rows (", sum(d$Status == "Resistant", na.rm = TRUE), " resistant).\n", sep = "")
  if ("Needs_review" %in% names(d) && any(toupper(d$Needs_review) == "Y", na.rm = TRUE))
    cat("  Marked Needs_review = Y: ", paste(d$ID[toupper(d$Needs_review) == "Y" & !is.na(d$Needs_review)], collapse = ", "),
        ". Confirm with the researcher before publishing.\n", sep = "")
  if (any(is.na(d$Status))) cat("  ", sum(is.na(d$Status)), " rows have no mortality and no status.\n", sep = "")
  if (any(!is.na(d$Mortality_pct) & (d$Mortality_pct < 0 | d$Mortality_pct > 100))) cat("  Mortality outside 0 to 100 in some rows.\n")
  if (any(is.na(d$Source) | !nzchar(as.character(d$Source)))) cat("  Some rows have no Source.\n")
  invisible(d)
}
