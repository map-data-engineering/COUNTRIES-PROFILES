# Shared StatCompiler tools for the country profiles.
#
# RULE: the raw StatCompiler export is only ever READ. It is never edited,
# renamed, re-saved or reshaped.
#
# Two functions:
#   check_statcompiler()  used when a page is generated: reports problems in plain words
#   survey_table()        used when the page is built: returns the Section 6b table
#
# Layout supported: the current StatCompiler layout (indicator names in row 1,
# a 'Country | Survey | Total ...' header lower down, a blank row, then a
# glossary and a citation row). The older single-header layout is read too.

suppressPackageStartupMessages(library(openxlsx))

.key <- function(x) tolower(trimws(x))

# ---- Read the raw export into tidy long form -------------------------------------
read_statcompiler <- function(path) {
  x <- read.xlsx(path, colNames = FALSE, skipEmptyRows = FALSE, skipEmptyCols = FALSE)
  x[] <- lapply(x, as.character)

  hdr <- which(x[[1]] == "Country" & x[[2]] == "Survey")[1]
  if (is.na(hdr)) {
    stop("No 'Country | Survey' header row found in ", basename(path),
         ". Is this an unedited StatCompiler export?")
  }
  hdr_cells <- as.character(unlist(x[hdr, ]))
  top_cells <- as.character(unlist(x[1, ]))

  # In the current layout the header row says 'Total' for every indicator.
  # Anything else (Urban, Rural, a wealth group) means a breakdown, not national figures.
  if (hdr > 1) {
    other <- setdiff(na.omit(hdr_cells[-(1:2)]), c("Total", ""))
    if (length(other) > 0) {
      stop("This export is broken down by '", paste(other, collapse = ", "),
           "' instead of 'Total'. Please export national totals only.")
    }
  }
  generic   <- is.na(hdr_cells) | hdr_cells %in% c("Total", "")
  ind_names <- trimws(ifelse(generic, top_cells, hdr_cells))
  cols <- which(!is.na(ind_names) & ind_names != "" & seq_along(ind_names) >= 3)

  blank <- which((is.na(x[[1]]) | x[[1]] == "") & seq_along(x[[1]]) > hdr)
  last  <- if (length(blank) > 0) blank[1] - 1 else nrow(x)
  d <- x[(hdr + 1):last, , drop = FALSE]

  # "43 (CI: 38 - 49)" becomes value 43, low 38, high 49. A blank stays blank.
  parse_cell <- function(v) {
    if (is.na(v) || trimws(v) == "") return(c(NA_real_, NA_real_, NA_real_))
    m <- regmatches(v, regexec("^\\s*([0-9.]+)\\s*(?:\\(CI:\\s*([0-9.]+)\\D+([0-9.]+)\\))?\\s*$",
                               v, perl = TRUE))[[1]]
    if (length(m) == 0) return(c(NA_real_, NA_real_, NA_real_))
    suppressWarnings(as.numeric(c(m[2], m[3], m[4])))
  }

  out <- list(); unread <- character(0)
  for (j in cols) {
    p <- t(vapply(d[[j]], parse_cell, numeric(3)))
    bad <- !is.na(d[[j]]) & trimws(d[[j]]) != "" & is.na(p[, 1])
    if (any(bad)) unread <- c(unread, paste0(ind_names[j], " / ", d[[2]][bad], ": '", d[[j]][bad], "'"))
    out[[length(out) + 1]] <- data.frame(
      Country = d[[1]], Survey = d[[2]], Indicator = ind_names[j],
      Value = p[, 1], Lo = p[, 2], Hi = p[, 3], Row = seq_len(nrow(d)), stringsAsFactors = FALSE)
  }
  long <- do.call(rbind, out)
  long$Year <- suppressWarnings(as.integer(substr(long$Survey, 1, 4)))
  long$Type <- sub("^.* ", "", long$Survey)
  rownames(long) <- NULL

  if (length(unread) > 0) {
    warning("Some cells could not be read as numbers and are left blank:\n  ",
            paste(head(unread, 8), collapse = "\n  "))
  }
  cite <- x[[1]][grepl("^ICF", x[[1]])]
  attr(long, "citation") <- if (length(cite) > 0) tail(cite, 1) else NA_character_
  attr(long, "file") <- basename(path)
  long
}

.read_display <- function(display_csv) {
  disp <- read.csv(display_csv, stringsAsFactors = FALSE, na.strings = "")
  need <- c("Group", "Indicator", "Label", "Unit", "ShowCI")
  if (!all(need %in% names(disp))) stop(display_csv, " must have columns: ", paste(need, collapse = ", "))
  if (!("Show" %in% names(disp))) disp$Show <- "yes"
  disp$Show <- tolower(trimws(ifelse(is.na(disp$Show), "yes", disp$Show)))
  disp
}

# Rows of the same Group must sit together, or the headings would be wrong.
.check_groups <- function(disp) {
  g <- disp$Group
  if (length(unique(g)) != length(rle(g)$values)) {
    stop("In display_survey.csv, rows of the same Group must sit together. ",
         "Please move the rows so each Group is one block.")
  }
}

# Rounds to show: the most recent `n`, counting only rounds that have at least
# one value for a listed indicator. Newest first, as StatCompiler lists them.
.pick_rounds <- function(sc, disp, n) {
  s <- sc[.key(sc$Indicator) %in% .key(disp$Indicator) & !is.na(sc$Value), ]
  r <- unique(s[, c("Survey", "Year", "Row")])
  r <- r[order(-r$Year, r$Row), ]
  head(r$Survey, n)
}

# ---- Plain-words report used when the page is generated --------------------------
check_statcompiler <- function(path, country, display_csv, n_rounds = 5) {
  sc <- read_statcompiler(path)
  cat("StatCompiler file:", basename(path), "\n")
  cat("Citation in file: ", if (is.na(attr(sc, "citation"))) "NOT FOUND" else attr(sc, "citation"), "\n")
  if (is.na(attr(sc, "citation"))) warning("No citation row found. The source line will be generic.")
  if (any(is.na(sc$Year))) warning("Some survey labels do not start with a year: ",
                                   paste(unique(sc$Survey[is.na(sc$Year)]), collapse = ", "))
  countries <- unique(sc$Country)
  if (!(country %in% countries)) {
    stop("'", country, "' is not in this export. It contains: ", paste(countries, collapse = ", "))
  }
  sc <- sc[sc$Country == country, ]
  disp <- .read_display(display_csv)

  present <- unique(sc$Indicator)
  on   <- disp[disp$Show != "no", ]
  off  <- disp[disp$Show == "no", ]
  unlisted <- present[!(.key(present) %in% .key(disp$Indicator))]
  cat("Indicators in the file:", length(present),
      "| shown on the page:", sum(.key(on$Indicator) %in% .key(present)),
      "| switched off in the list:", sum(.key(off$Indicator) %in% .key(present)),
      "| not on the list at all:", length(unlisted), "\n")
  if (sum(.key(on$Indicator) %in% .key(present)) == 0) stop("None of the indicators to be shown are in this export.")
  if (length(unlisted) > 0) { cat("Not on the display list (not shown):\n"); print(unlisted) }
  absent <- on$Indicator[!(.key(on$Indicator) %in% .key(present))]
  if (length(absent) > 0) {
    cat("To be shown, but missing from this export:\n"); print(absent)
    warning(length(absent), " indicator(s) to be shown are missing from the export. ",
            "Please ask for a new export made with the full indicator checklist.")
  }
  .check_groups(on)
  rounds <- .pick_rounds(sc, on, n_rounds)
  cat("Rounds available:", length(unique(sc$Survey)), "| shown (most recent", n_rounds, "with data):",
      paste(rounds, collapse = ", "), "\n\n")
  invisible(TRUE)
}

# ---- The Section 6b table ---------------------------------------------------------
survey_table <- function(path, country, display_csv, n_rounds = 5) {
  suppressPackageStartupMessages(library(kableExtra))
  esc <- function(x) { x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); gsub(">", "&gt;", x, fixed = TRUE) }

  sc <- read_statcompiler(path)
  cite <- attr(sc, "citation")
  sc <- sc[sc$Country == country, ]
  if (nrow(sc) == 0) stop("'", country, "' not found in ", basename(path))
  disp <- .read_display(display_csv)
  disp <- disp[disp$Show != "no", ]
  rounds <- .pick_rounds(sc, disp, n_rounds)

  # keep indicators to be shown that are in the file, in the DET list's order
  disp <- disp[.key(disp$Indicator) %in% .key(sc$Indicator), ]
  if (nrow(disp) == 0) stop("No indicators to show for ", country, " in ", basename(path))
  .check_groups(disp)

  fmt1 <- function(v, unit) if (unit == "%") sprintf("%.1f", v) else format(round(v, 1), nsmall = 0, trim = TRUE)
  cell <- function(i, r) {
    s <- sc[.key(sc$Indicator) == .key(disp$Indicator[i]) & sc$Survey == r, ]
    if (nrow(s) == 0 || is.na(s$Value[1])) return("-")
    txt <- fmt1(s$Value[1], disp$Unit[i])
    if (isTRUE(tolower(disp$ShowCI[i]) == "yes") && !is.na(s$Lo[1])) {
      txt <- paste0(txt, "<br><span style='font-size:0.85em;color:#6B6B6B'>(", fmt1(s$Lo[1], disp$Unit[i]), " to ",
                    fmt1(s$Hi[1], disp$Unit[i]), ")</span>")
    }
    txt
  }
  label <- ifelse(disp$Unit == "%", esc(disp$Label), paste0(esc(disp$Label), " (", esc(disp$Unit), ")"))
  tbl <- data.frame(Indicator = label, stringsAsFactors = FALSE)
  for (r in rounds) tbl[[r]] <- vapply(seq_len(nrow(disp)), function(i) cell(i, r), "")

  idx <- table(factor(disp$Group, levels = unique(disp$Group)))
  k <- kbl(tbl, escape = FALSE, align = paste0("l", strrep("c", length(rounds)))) %>%
    kable_styling(bootstrap_options = c("hover", "condensed"), full_width = TRUE, font_size = 13) %>%
    row_spec(0, bold = TRUE, background = "#1F3A5F", color = "white") %>%
    pack_rows(index = setNames(as.integer(idx), names(idx)),
              label_row_css = "background-color: #EEF2F7; color: #1F3A5F; font-weight: 600;")

  src <- if (is.na(cite)) "The DHS Program STATcompiler" else esc(cite)
  src <- sub("http://www.statcompiler.com", "<a href='http://www.statcompiler.com'>www.statcompiler.com</a>", src, fixed = TRUE)
  note <- paste0("<p><em>Source: ", src, " (export file: ", esc(attr(sc, "file")), "). ",
                 "Confidence intervals are shown for prevalence and mortality. ",
                 "A dash means the indicator was not measured in that survey.</em></p>")
  knitr::asis_output(paste0(as.character(k), note))
}
