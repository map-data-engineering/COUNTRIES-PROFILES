## ==========================================================================
##  R/fig_timeline.R
##  Timeline of malaria control, built from the Timeline tab of the epi
##  workbook (Year, Category, Event, Source, Link).
##    source("R/fig_timeline.R")
##    p <- fig_timeline("mozambique")
##    save_fig(p, "figures/mozambique/timeline_preview.png",
##             width = 12, height = fig_timeline_height("mozambique"))
##  Interventions are drawn on the left (WHO blue), policy and health
##  systems on the right (vermillion). Sides, wrapping and spacing are automatic.
## ==========================================================================

source(file.path("R", "theme.R"))

timeline_categories <- c("Interventions", "Policy and health systems")
timeline_cols <- stats::setNames(c(det_cols$intervention, det_cols$policy), timeline_categories)

read_timeline <- function(slug, path = file.path("submissions", slug,
                                                 paste0("epi_table_", slug, ".xlsx"))) {
  if (!requireNamespace("readxl", quietly = TRUE)) stop("install.packages('readxl')")
  if (!file.exists(path)) stop("Missing ", path)
  x <- as.data.frame(readxl::read_excel(path, sheet = "Timeline"))
  need <- c("Year", "Category", "Event", "Source", "Link")
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("Timeline tab is missing column(s): ", paste(miss, collapse = ", "))
  x <- x[!is.na(x$Event) & nzchar(trimws(x$Event)), need, drop = FALSE]
  x$Year <- suppressWarnings(as.integer(x$Year))
  if (anyNA(x$Year)) stop("Timeline tab: every row needs a numeric Year.")
  x$Category <- trimws(x$Category)
  bad <- setdiff(unique(x$Category), timeline_categories)
  if (length(bad))
    stop("Timeline tab: unknown Category '", paste(bad, collapse = "', '"),
         "'. Use exactly: ", paste(timeline_categories, collapse = " | "))
  x[order(x$Year), ]
}

## One row per year, with the text for each side and the row height
timeline_layout <- function(slug, path = NULL, wrap = 40) {
  tl <- if (is.null(path)) read_timeline(slug) else read_timeline(slug, path)
  if (nrow(tl) > 16)
    warning("Timeline has ", nrow(tl), " events. More than about 16 will not fit one page. Ask the researcher to select.")
  wrap_txt <- function(x) vapply(strwrap(x, width = wrap, simplify = FALSE),
                                 paste, character(1), collapse = "\n")
  tl$label <- wrap_txt(tl$Event)
  ev <- do.call(rbind, lapply(sort(unique(tl$Year)), function(yr) {
    d <- tl[tl$Year == yr, ]
    data.frame(year  = yr,
               left  = paste(d$label[d$Category == "Interventions"], collapse = "\n\n"),
               right = paste(d$label[d$Category == "Policy and health systems"], collapse = "\n\n"),
               stringsAsFactors = FALSE)
  }))
  nlines <- function(x) ifelse(x == "", 0L, lengths(regmatches(x, gregexpr("\n", x))) + 1L)
  ev$h <- pmax(nlines(ev$left), nlines(ev$right), 1L) + 1.2     # row height, in text lines
  ev$y <- -(cumsum(ev$h) - ev$h / 2)
  list(ev = ev, total = sum(ev$h), tl = tl)
}

fig_timeline_height <- function(slug, path = NULL) {
  0.2 * (timeline_layout(slug, path)$total + 3)    # inches; pair with width = 12
}

fig_timeline <- function(slug, path = NULL) {
  lay <- timeline_layout(slug, path)
  ev <- lay$ev; total <- lay$total

  YEAR_X <- 0.45; TEXT_X <- 1.25

  ## diamonds: one per side that has an event in that year
  pts <- do.call(rbind, lapply(seq_len(nrow(ev)), function(i) {
    cats <- c(if (ev$left[i]  != "") timeline_categories[1],
              if (ev$right[i] != "") timeline_categories[2])
    data.frame(x = if (length(cats) == 2) c(-0.14, 0.14) else 0, y = ev$y[i],
               Category = cats, stringsAsFactors = FALSE)
  }))
  pts$Category <- factor(pts$Category, levels = timeline_categories)

  ## year label sits on the side of its event (left if both)
  on_right <- ev$left == "" & ev$right != ""
  yrs <- data.frame(x = ifelse(on_right, YEAR_X, -YEAR_X), y = ev$y,
                    label = ev$year, hj = ifelse(on_right, 0, 1))
  lft <- data.frame(y = ev$y, label = ev$left,  stringsAsFactors = FALSE)
  rgt <- data.frame(y = ev$y, label = ev$right, stringsAsFactors = FALSE)
  lft <- lft[lft$label != "", ]; rgt <- rgt[rgt$label != "", ]

  ggplot() +
    annotate("segment", x = 0, xend = 0, y = -0.3, yend = -(total + 0.3),
             colour = det_cols$spine, linewidth = 0.9, lineend = "round") +
    geom_point(data = pts, aes(x = x, y = y, fill = Category), shape = 23,
               size = 4, colour = "white", stroke = 0.5) +
    geom_text(data = yrs, aes(x = x, y = y, label = label, hjust = hj),
              size = 3.3, colour = det_cols$muted, fontface = "bold") +
    geom_text(data = lft, aes(x = -TEXT_X, y = y, label = label),
              hjust = 1, size = 3.5, colour = det_cols$ink, lineheight = 1.1) +
    geom_text(data = rgt, aes(x = TEXT_X, y = y, label = label),
              hjust = 0, size = 3.5, colour = det_cols$ink, lineheight = 1.1) +
    annotate("text", x = 0, y = -(total + 1.2), label = "NOW",
             size = 4.4, colour = det_cols$muted, fontface = "bold") +
    scale_fill_manual(values = timeline_cols, limits = timeline_categories,
                      name = NULL, drop = FALSE) +
    guides(fill = guide_legend(override.aes = list(size = 4))) +
    scale_x_continuous(limits = c(-7, 7), expand = c(0, 0)) +
    scale_y_continuous(limits = c(-(total + 2), 1), expand = c(0, 0)) +
    theme_det() +
    theme(legend.position = "top", legend.text = element_text(size = 10))
}

## Text for the profile: caption, source line, and a sources table
fig_timeline_text <- function(slug, path = NULL) {
  s  <- get_country_settings(slug)
  tl <- if (is.null(path)) read_timeline(slug) else read_timeline(slug, path)
  list(
    caption = paste0("Timeline of key malaria interventions and policy milestones in ",
                     s$country_name, ", ", min(tl$Year), " to ", max(tl$Year), "."),
    source  = "Compiled by the Data Engineering Team from the references listed in the table below."
  )
}

timeline_sources <- function(slug, path = NULL) {
  tl <- if (is.null(path)) read_timeline(slug) else read_timeline(slug, path)
  has_src  <- !is.na(tl$Source) & nzchar(trimws(tl$Source))
  has_link <- !is.na(tl$Link)   & nzchar(trimws(tl$Link))
  data.frame(Year = tl$Year, Event = tl$Event,
             Source = ifelse(!has_src, "Source needed",
                      ifelse(has_link, paste0("[", tl$Source, "](", tl$Link, ")"), tl$Source)),
             stringsAsFactors = FALSE)
}
