## ==========================================================================
##  R/theme.R
##  Shared look for every DET figure, plus the country settings reader.
##  Source this at the top of each fig_*.R script.
## ==========================================================================

suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(sf) })
if (file.exists(file.path("R", "text_utils.R"))) source(file.path("R", "text_utils.R"))

## ---- colours ---------------------------------------------------------------
det_cols <- list(
  text      = "#222222",
  border1   = "#222222",   # admin 1 borders
  border2   = "#FFFFFF",   # admin 2 borders (thin white on coloured fill)
  context   = "#E6E6E6",   # neighbouring land in the inset
  highlight = "#B8860B",   # country in the inset
  capital   = "#B22222",
  ink       = "#1F2933",   # main text
  muted     = "#6B7280",   # years, secondary text
  spine     = "#9CA3AF",   # timeline spine
  intervention = "#009ADE",  # WHO blue
  policy       = "#D55E00"   # Okabe-Ito vermillion, colour-blind safe
)

## Flat qualitative palette, readable on white. Extended automatically if a
## country has more units than colours.
det_palette <- function(n) {
  base <- c("#E8B04A", "#8FB3A3", "#C9826B", "#7A9CC6", "#B5A642", "#A67BA8",
            "#6FA287", "#D99A9A", "#8D8D8D", "#5E8C9A", "#C4A27A", "#9AA86B")
  if (n <= length(base)) base[seq_len(n)] else grDevices::colorRampPalette(base)(n)
}

theme_det <- function(base_size = 11) {
  theme_void(base_size = base_size) +
    theme(
      plot.background  = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      legend.title     = element_text(face = "bold", colour = det_cols$text),
      legend.text      = element_text(colour = det_cols$text),
      plot.margin      = margin(6, 6, 6, 6)
    )
}

## ---- country settings --------------------------------------------------------
## One row per country in config/country_settings.csv.
## (Later this moves to the Country_settings tab of the epi workbook.)
get_country_settings <- function(slug, path = file.path("config", "country_settings.csv")) {
  if (!file.exists(path)) stop("Missing ", path)
  s <- utils::read.csv(path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  s <- s[s$slug == slug, , drop = FALSE]
  if (nrow(s) != 1) stop("Add one row for '", slug, "' in ", path)
  s$label_admin1 <- as.logical(s$label_admin1)
  as.list(s)
}

## ---- source line from the boundary registry ------------------------------------
boundary_source <- function(slug, path = file.path("config", "boundaries.csv")) {
  r <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  r <- r[r$country == slug, , drop = FALSE]
  if (nrow(r) == 0) return("Administrative boundaries: source not recorded.")
  ver <- r$release_version[1]
  paste0("Administrative boundaries: Malaria Atlas Project",
         if (!is.na(ver) && !ver %in% c("", "not pinned")) paste0(" (release ", ver, ")") else "",
         ", retrieved ", r$retrieved_date[1], ".")
}

## ---- saving, for previews and the optional figures/ folder ---------------------
save_fig <- function(p, file, width = 9, height = 6.5, dpi = 300) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(file, p, width = width, height = height, dpi = dpi, bg = "white")
  invisible(file)
}

## ---- helpers shared by the diagram scripts -----------------------------------
## Read one sheet of the researcher's epi workbook
read_epi_sheet <- function(slug, sheet, path = NULL) {
  if (!requireNamespace("readxl", quietly = TRUE)) stop("install.packages('readxl')")
  if (is.null(path)) path <- file.path("submissions", slug, paste0("epi_table_", slug, ".xlsx"))
  if (!file.exists(path)) stop("Missing ", path)
  if (!sheet %in% readxl::excel_sheets(path))
    stop("The epi table has no '", sheet, "' sheet. Copy it from the DET tab file.")
  as.data.frame(readxl::read_excel(path, sheet = sheet))
}

## Wrap text to a number of characters; count lines in wrapped text
wrap_to <- function(x, width) {
  vapply(strwrap(x, width = width, simplify = FALSE), paste, character(1), collapse = "\n")
}
nlines <- function(x) ifelse(x == "", 0L, lengths(regmatches(x, gregexpr("\n", x))) + 1L)

## White or dark text, whichever reads better on a fill colour
text_on <- function(fill) {
  rgb <- grDevices::col2rgb(fill)
  lum <- (0.299 * rgb[1, ] + 0.587 * rgb[2, ] + 0.114 * rgb[3, ]) / 255
  ifelse(lum > 0.6, det_cols$ink, "white")
}
