## ==========================================================================
##  R/fig_health_system.R
##  Organisation of health administration and service delivery, drawn as a
##  pyramid from the Health_system tab of the epi workbook.
##    source("R/fig_health_system.R")
##    p <- fig_health_system("mozambique")
##    save_fig(p, "figures/mozambique/health_system_preview.png", width = 12.4,
##             height = fig_health_system_height("mozambique"))
##  Health_system tab columns:
##    Order (1 = top), Tier (Tertiary | Secondary | Primary | Community),
##    Level_name, Admin_body, Facility_types, Role_in_malaria, Source
##  Required: Order, Tier, Level_name. Facility_types and Role_in_malaria
##  may be blank: DET then uses config/health_system_defaults.csv, lists every
##  cell it filled in the console, and says so in the Source line.
##  Admin_body is never defaulted (names are country-specific).
## ==========================================================================

source(file.path("R", "theme.R"))

hs_tiers      <- c("Tertiary", "Secondary", "Primary", "Community")
hs_tier_label <- c(Tertiary = "Tertiary", Secondary = "Secondary",
                   Primary = "Primary health care (PHC)", Community = "Community")
hs_tier_fill  <- c(Tertiary = "#0B4F7C", Secondary = "#2E7DAF",
                   Primary = "#009ADE", Community = "#9ED7F2")

read_health_system <- function(slug, path = NULL,
                               defaults_path = file.path("config", "health_system_defaults.csv")) {
  x <- read_epi_sheet(slug, "Health_system", path)
  for (cn in c("Facility_types", "Role_in_malaria", "Admin_body", "Source"))
    if (!cn %in% names(x)) x[[cn]] <- NA_character_      # optional columns
  need <- c("Order", "Tier", "Level_name")
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("Health_system tab is missing column(s): ", paste(miss, collapse = ", "))
  x <- x[!is.na(x$Level_name) & nzchar(trimws(x$Level_name)),
         c(need, "Admin_body", "Facility_types", "Role_in_malaria", "Source"), drop = FALSE]
  x$Order <- suppressWarnings(as.numeric(x$Order))
  if (anyNA(x$Order)) stop("Health_system tab: every row needs a numeric Order (1 = top).")
  x <- x[order(x$Order), ]
  x[] <- lapply(x, function(v) { v <- as.character(v); v[is.na(v)] <- ""; trimws(v) })
  bad <- setdiff(unique(x$Tier), hs_tiers)
  if (length(bad)) stop("Health_system tab: unknown Tier '", paste(bad, collapse = "', '"),
                        "'. Use exactly: ", paste(hs_tiers, collapse = " | "))
  if (nrow(x) > 6) warning("Health_system has ", nrow(x), " levels. More than 6 will not fit well. Ask the researcher to combine levels.")

  ## Standard descriptions where the country tab is blank
  d <- utils::read.csv(defaults_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  x$defaulted <- ""
  for (cn in c("Facility_types", "Role_in_malaria")) {
    blank <- x[[cn]] == ""
    x[[cn]][blank] <- d[[cn]][match(x$Tier[blank], d$Tier)]
    x$defaulted[blank] <- paste0(x$defaulted[blank], cn, " ")
  }
  x
}

hs_layout <- function(slug, path = NULL) {
  x <- read_health_system(slug, path)
  n <- nrow(x)
  LINE_H <- 1.9; PAD <- 3.5; GAP <- 2.5; HEAD_H <- 6
  cols <- data.frame(head = c("Who manages", "Where care is delivered", "Role in malaria"),
                     x0 = c(10, 73, 100), w = c(24, 25, 24), stringsAsFactors = FALSE)
  cx <- 53; pw_bot <- 34; pw_top <- 8
  cw <- function(w) floor((w - 3) / 0.8)

  ## text inside each slice: width estimated from its position in the pyramid
  slice_chars <- pmax(8, floor((pw_top + (pw_bot - pw_top) * (seq_len(n) - 0.5) / n - 2) / 0.9))
  tier_txt <- unname(hs_tier_label[x$Tier])
  x$level_txt <- vapply(seq_len(n), function(i) {
    nm <- wrap_to(x$Level_name[i], slice_chars[i])
    if (tolower(tier_txt[i]) == tolower(x$Level_name[i])) nm
    else paste0(nm, "\n", wrap_to(tier_txt[i], slice_chars[i]))
  }, character(1))
  x$admin_txt <- wrap_to(x$Admin_body, cw(cols$w[1]))
  x$fac_txt   <- wrap_to(x$Facility_types, cw(cols$w[2]))
  x$role_txt  <- wrap_to(x$Role_in_malaria, cw(cols$w[3]))
  n_l <- pmax(nlines(x$level_txt), nlines(x$admin_txt), nlines(x$fac_txt), nlines(x$role_txt))
  x$h    <- pmax(10, n_l * LINE_H + PAD)
  x$ymax <- -HEAD_H - GAP - c(0, cumsum(x$h + GAP))[seq_len(n)]
  x$ymin <- x$ymax - x$h
  x$yc   <- (x$ymax + x$ymin) / 2
  y_t <- x$ymax[1]; y_b <- min(x$ymin)
  wid <- function(y) pw_top + (pw_bot - pw_top) * (y_t - y) / (y_t - y_b)
  list(x = x, cols = cols, cx = cx, wid = wid, total = -y_b, head_h = HEAD_H)
}

fig_health_system_height <- function(slug, path = NULL) (hs_layout(slug, path)$total + 4) / 10 + 0.3

fig_health_system <- function(slug, path = NULL) {
  L <- hs_layout(slug, path); x <- L$x; cols <- L$cols; cx <- L$cx; wid <- L$wid
  n <- nrow(x)
  fills <- unname(hs_tier_fill[x$Tier])

  used <- x$defaulted != ""
  if (any(used)) message("Standard descriptions used from config/health_system_defaults.csv for: ",
                         paste0(x$Level_name[used], " (", trimws(x$defaulted[used]), ")", collapse = "; "))

  poly <- do.call(rbind, lapply(seq_len(n), function(i) data.frame(
    id = i, fill = fills[i],
    x = c(cx - wid(x$ymax[i]) / 2, cx + wid(x$ymax[i]) / 2, cx + wid(x$ymin[i]) / 2, cx - wid(x$ymin[i]) / 2),
    y = c(x$ymax[i], x$ymax[i], x$ymin[i], x$ymin[i]), stringsAsFactors = FALSE)))
  bands <- data.frame(xmin = 10, xmax = 124, ymin = x$ymin - 1.2, ymax = x$ymax + 1.2,
                      fill = ifelse(seq_len(n) %% 2 == 1, "#F3F6F9", "#FFFFFF"), stringsAsFactors = FALSE)
  txt_level <- data.frame(x = cx, y = x$yc, label = x$level_txt, col = text_on(fills), stringsAsFactors = FALSE)
  txt_admin <- data.frame(x = cols$x0[1] + cols$w[1] - 1, y = x$yc, label = x$admin_txt, stringsAsFactors = FALSE)
  txt_right <- rbind(data.frame(x = cols$x0[2] + 0.5, y = x$yc, label = x$fac_txt, stringsAsFactors = FALSE),
                     data.frame(x = cols$x0[3] + 0.5, y = x$yc, label = x$role_txt, stringsAsFactors = FALSE))
  heads <- data.frame(x = c(cols$x0[1] + cols$w[1] - 1, cx, cols$x0[2] + 0.5, cols$x0[3] + 0.5),
                      y = -L$head_h / 2,
                      label = c("Who manages", "Level", "Where care is delivered", "Role in malaria"),
                      hj = c(1, 0.5, 0, 0), stringsAsFactors = FALSE)
  ## dotted guide lines from each slice to its text, so rows read across
  guides <- data.frame(
    xl = cols$x0[1] + cols$w[1] + 0.3, xl_end = cx - wid(x$yc) / 2 - 0.4,
    xr = cx + wid(x$yc) / 2 + 0.4,     xr_end = cols$x0[2] - 0.5, y = x$yc)
  yc1 <- x$yc[1]; ycn <- x$yc[n]; mid <- (yc1 + ycn) / 2

  p <- ggplot() +
    geom_rect(data = bands, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = fill)) +
    geom_polygon(data = poly, aes(x = x, y = y, group = id, fill = fill), colour = "white", linewidth = 0.9) +
    scale_fill_identity() + scale_colour_identity() +
    geom_segment(data = guides, aes(x = xl, xend = xl_end, y = y, yend = y), colour = det_cols$spine, linetype = "dotted") +
    geom_segment(data = guides, aes(x = xr, xend = xr_end, y = y, yend = y), colour = det_cols$spine, linetype = "dotted") +
    geom_text(data = txt_level, aes(x = x, y = y, label = label, colour = col),
              fontface = "bold", size = 3.3, lineheight = 1.05) +
    geom_text(data = txt_admin, aes(x = x, y = y, label = label),
              hjust = 1, size = 3.3, colour = det_cols$ink, lineheight = 1.1) +
    geom_text(data = txt_right, aes(x = x, y = y, label = label),
              hjust = 0, size = 3.3, colour = det_cols$ink, lineheight = 1.1) +
    geom_text(data = heads, aes(x = x, y = y, label = label, hjust = hj),
              fontface = "bold", size = 3.5, colour = det_cols$ink) +
    annotate("segment", x = 10, xend = 124, y = -L$head_h, yend = -L$head_h,
             colour = det_cols$ink, linewidth = 0.4)

  if (n >= 2) {
    p <- p +
      annotate("segment", x = 2.5, xend = 2.5, y = ycn, yend = yc1, colour = det_cols$policy,
               linewidth = 0.8, arrow = arrow(length = unit(0.16, "in"), type = "closed")) +
      annotate("text", x = 0.7, y = mid, label = "Referral", angle = 90, size = 3.2, colour = det_cols$policy) +
      annotate("segment", x = 6.5, xend = 6.5, y = yc1, yend = ycn, colour = det_cols$muted,
               linewidth = 0.8, linetype = "dashed",
               arrow = arrow(length = unit(0.16, "in"), type = "closed")) +
      annotate("text", x = 8.3, y = mid, label = "Supervision and support", angle = 270,
               size = 3.2, colour = det_cols$muted)
  }
  p + coord_fixed(xlim = c(0, 124), ylim = c(-L$total - 2, 2), expand = FALSE) +
    theme_det() + theme(legend.position = "none")
}

fig_health_system_text <- function(slug, path = NULL) {
  s <- get_country_settings(slug)
  x <- read_health_system(slug, path)
  src <- unique(x$Source[x$Source != ""])
  src_txt <- if (length(src)) paste(src, collapse = "; ") else "Source needed (Health_system tab)."
  if (any(x$defaulted != ""))
    src_txt <- paste0(src_txt, " Where the country tab was blank, facility types and roles in malaria control are standard descriptions based on WHO guidance.")
  list(caption = paste0("Organisation of health administration and service delivery, ", s$country_name, "."),
       source  = src_txt)
}
