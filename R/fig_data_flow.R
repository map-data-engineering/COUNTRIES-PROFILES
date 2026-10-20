## ==========================================================================
##  R/fig_data_flow.R
##  Health data and information flow, drawn from the Data_flow tab of the
##  epi workbook.
##    source("R/fig_data_flow.R")
##    p <- fig_data_flow("mozambique")
##    save_fig(p, "figures/mozambique/data_flow_preview.png", width = 12.4,
##             height = fig_data_flow_height("mozambique"))
##  Data_flow tab columns:
##    Step (1 = lowest level), Level, Actor, Action, Tool, Frequency, Source
##  Tool and Frequency may be left blank; the line is then left out.
## ==========================================================================

source(file.path("R", "theme.R"))

read_data_flow <- function(slug, path = NULL) {
  x <- read_epi_sheet(slug, "Data_flow", path)
  need <- c("Step", "Level", "Actor", "Action", "Tool", "Frequency", "Source")
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("Data_flow tab is missing column(s): ", paste(miss, collapse = ", "))
  x <- x[!is.na(x$Level) & nzchar(trimws(x$Level)), need, drop = FALSE]
  x$Step <- suppressWarnings(as.numeric(x$Step))
  if (anyNA(x$Step)) stop("Data_flow tab: every row needs a numeric Step (1 = lowest level).")
  x <- x[order(x$Step), ]
  x[] <- lapply(x, function(v) { v <- as.character(v); v[is.na(v)] <- ""; trimws(v) })
  if (nrow(x) > 6) warning("Data_flow has ", nrow(x), " steps. More than 6 will not fit across one page.")
  x
}

df_layout <- function(slug, path = NULL) {
  x <- read_data_flow(slug, path); n <- nrow(x)
  LINE_H <- 1.9; SEC_GAP <- 1.4; TITLE_H <- 9; W <- 124; M <- 2; GAP <- 6
  bw <- (W - 2 * M - (n - 1) * GAP) / n
  cw <- floor((bw - 3) / 0.8)
  x$x0 <- M + (seq_len(n) - 1) * (bw + GAP)
  x$title_txt  <- wrap_to(x$Level, floor((bw - 2) / 0.85))
  x$actor_txt  <- wrap_to(x$Actor, cw)
  x$action_txt <- wrap_to(x$Action, cw)
  x$tool_txt   <- ifelse(x$Tool == "", "", wrap_to(paste0("Tool: ", x$Tool), cw))
  x$freq_txt   <- ifelse(x$Frequency == "", "", wrap_to(paste0("Frequency: ", x$Frequency), cw))
  sec <- function(txt) { l <- nlines(txt); ifelse(l == 0, 0, l * LINE_H + SEC_GAP) }
  x$y_actor  <- -TITLE_H - 2
  x$y_action <- x$y_actor  - sec(x$actor_txt)
  x$y_tool   <- x$y_action - sec(x$action_txt)
  x$y_freq   <- x$y_tool   - sec(x$tool_txt)
  body_h <- max(2 + sec(x$actor_txt) + sec(x$action_txt) + sec(x$tool_txt) + sec(x$freq_txt) + 1)
  list(x = x, n = n, bw = bw, title_h = TITLE_H, total = TITLE_H + body_h)
}

fig_data_flow_height <- function(slug, path = NULL) (df_layout(slug, path)$total + 16) / 10 + 0.2

fig_data_flow <- function(slug, path = NULL) {
  L <- df_layout(slug, path); x <- L$x; n <- L$n; bw <- L$bw
  fills <- grDevices::colorRampPalette(c("#9ED7F2", "#0B4F7C"))(n)
  bars  <- data.frame(xmin = x$x0, xmax = x$x0 + bw, ymin = -L$title_h, ymax = 0, fill = fills, stringsAsFactors = FALSE)
  bodies <- data.frame(xmin = x$x0, xmax = x$x0 + bw, ymin = -L$total, ymax = -L$title_h, stringsAsFactors = FALSE)
  titles <- data.frame(x = x$x0 + bw / 2, y = -L$title_h / 2, label = x$title_txt, col = text_on(fills), stringsAsFactors = FALSE)
  lay <- function(col, y) { d <- data.frame(x = x$x0 + 1.5, y = y, label = x[[col]], stringsAsFactors = FALSE); d[d$label != "", ] }
  yfb <- -L$total - 5

  p <- ggplot() +
    geom_rect(data = bodies, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
              fill = "#F3F6F9", colour = "#C9D3DC", linewidth = 0.3) +
    geom_rect(data = bars, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = fill),
              colour = "#C9D3DC", linewidth = 0.3) +
    scale_fill_identity() + scale_colour_identity() +
    geom_text(data = titles, aes(x = x, y = y, label = label, colour = col),
              fontface = "bold", size = 3.5, lineheight = 1.05) +
    geom_text(data = lay("actor_txt", x$y_actor), aes(x = x, y = y, label = label),
              hjust = 0, vjust = 1, fontface = "bold", size = 3.3, colour = det_cols$ink, lineheight = 1.1) +
    geom_text(data = lay("action_txt", x$y_action), aes(x = x, y = y, label = label),
              hjust = 0, vjust = 1, size = 3.3, colour = det_cols$ink, lineheight = 1.1) +
    geom_text(data = lay("tool_txt", x$y_tool), aes(x = x, y = y, label = label),
              hjust = 0, vjust = 1, size = 3.1, colour = det_cols$muted, lineheight = 1.1) +
    geom_text(data = lay("freq_txt", x$y_freq), aes(x = x, y = y, label = label),
              hjust = 0, vjust = 1, size = 3.1, colour = det_cols$muted, lineheight = 1.1)

  if (n >= 2) {
    ya <- -L$title_h / 2
    p <- p +
      annotate("segment", x = x$x0[-n] + bw + 0.6, xend = x$x0[-1] - 0.6, y = ya, yend = ya,
               colour = det_cols$ink, linewidth = 0.7,
               arrow = arrow(length = unit(0.13, "in"), type = "closed")) +
      annotate("segment", x = x$x0[n] + bw / 2, xend = x$x0[n] + bw / 2, y = -L$total, yend = yfb,
               colour = det_cols$muted, linewidth = 0.6, linetype = "dashed") +
      annotate("segment", x = x$x0[n] + bw / 2, xend = x$x0[1] + bw / 2, y = yfb, yend = yfb,
               colour = det_cols$muted, linewidth = 0.6, linetype = "dashed") +
      annotate("segment", x = x$x0[1] + bw / 2, xend = x$x0[1] + bw / 2, y = yfb, yend = -L$total - 0.4,
               colour = det_cols$muted, linewidth = 0.6, linetype = "dashed",
               arrow = arrow(length = unit(0.13, "in"), type = "closed")) +
      annotate("text", x = 62, y = yfb - 2.4, label = "Feedback, supervision and reports",
               size = 3.1, fontface = "italic", colour = det_cols$muted)
  }
  p + coord_fixed(xlim = c(0, 124), ylim = c(yfb - 5, 2), expand = FALSE) +
    theme_det() + theme(legend.position = "none")
}

fig_data_flow_text <- function(slug, path = NULL) {
  s <- get_country_settings(slug)
  x <- read_data_flow(slug, path)
  src <- unique(x$Source[x$Source != ""])
  list(caption = paste0("Health data and information flow, ", s$country_name, "."),
       source  = if (length(src)) paste(src, collapse = "; ") else "Source needed (Data_flow tab).")
}
