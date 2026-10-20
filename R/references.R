## ==========================================================================
##  R/references.R   (Section 11: references)
##  The researcher keeps typing the table in Section 11 of the profile
##  (Title, URL, Description, Tag). DET's script then:
##    - groups it by Tag in a fixed order, sorts each group, numbers the list
##      continuously, and makes each title a link
##    - adds the data and map sources DET's own figures used (boundaries,
##      facilities, vector surfaces), written from the config files, so they
##      are always correct and the same in every country
##    - reference_checks() prints problems when the page is generated
## ==========================================================================

source(file.path("R", "theme.R"))

ref_tag_order <- c("Epidemiology", "Intervention", "Policy/Strategic Plan",
                   "Health System", "Vector Bionomics", "Resistance")

.ref_profile <- function(slug) {
  f <- list.files(file.path("submissions", slug), "^profile_.*\\.md$", full.names = TRUE)
  f <- f[!grepl("TEMPLATE", f, ignore.case = TRUE)]
  if (length(f) != 1) stop("Expected exactly one profile_*.md in submissions/", slug)
  f
}

read_references <- function(slug) {
  x <- readLines(.ref_profile(slug), encoding = "UTF-8", warn = FALSE)
  i <- grep("^#+\\s*11[.)]?\\s", x)
  if (!length(i)) stop("No '## 11. References' heading found in the profile.")
  y  <- x[(i[1] + 1):length(x)]
  tb <- y[grepl("^\\s*\\|", y)]
  tb <- tb[!grepl("^\\s*\\|\\s*:?-{2,}", tb)]
  if (length(tb) < 2) stop("No references table found under Section 11.")
  cells <- lapply(strsplit(sub("\\|\\s*$", "", sub("^\\s*\\|", "", tb)), "|", fixed = TRUE), trimws)
  hdr <- tolower(cells[[1]])
  need <- c("title", "url", "description", "tag")
  if (!all(need %in% hdr))
    stop("The references table needs columns: Title, URL, Description, Tag. Found: ", paste(cells[[1]], collapse = ", "))
  rows <- lapply(cells[-1], function(r) { length(r) <- length(hdr); r[is.na(r)] <- ""; r })
  df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(df) <- hdr
  df[nzchar(df$title), need]
}

## used = which DET-built figures are on the page: "boundaries", "facilities", "vectors"
render_references <- function(slug, used = character(0)) {
  r <- read_references(slug)
  r$tag[!nzchar(r$tag)] <- "Other"
  tags <- unique(r$tag)
  tags <- c(intersect(ref_tag_order, tags), sort(setdiff(tags, ref_tag_order)))
  out <- character(); n <- 0
  for (t in tags) {
    g <- r[r$tag == t, ]; g <- g[order(tolower(g$title)), ]
    out <- c(out, paste0("### ", t), "")
    for (k in seq_len(nrow(g))) {
      n <- n + 1
      ttl  <- if (nzchar(g$url[k])) sprintf("[%s](%s)", g$title[k], g$url[k]) else g$title[k]
      desc <- if (nzchar(g$description[k])) paste0(": ", sub("\\.$", "", g$description[k]), ".") else "."
      out <- c(out, sprintf("%d. %s%s", n, ttl, desc))
    }
    out <- c(out, "")
  }

  src <- character()
  if ("boundaries" %in% used) src <- c(src, paste0("Administrative boundaries: ", boundary_source(slug)))
  if ("facilities" %in% used) {
    source(file.path("R", "facilities.R"))
    src <- c(src, paste0("Health facilities: ", sub("\\. Province from.*$", "", facility_source(slug)), "."))
  }
  if ("vectors" %in% used) {
    m <- file.path("data", "vectors", slug, "vector_surfaces.csv")
    if (file.exists(m)) {
      mm <- utils::read.csv(m, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
      src <- c(src, paste0("Vector distribution surfaces: Malaria Atlas Project (https://data.malariaatlas.org), retrieved ",
                           mm$retrieved_date[1], "."))
    }
  }
  if (length(src)) out <- c(out, "### Data and map sources used for the figures on this page", "", paste0("- ", src), "")
  italicise_species(out)
}

## Console report, printed when the page is generated
reference_checks <- function(slug) {
  r <- tryCatch(read_references(slug), error = function(e) { cat("References: ", conditionMessage(e), "\n", sep = ""); NULL })
  if (is.null(r)) return(invisible(NULL))
  cat("References: ", nrow(r), " entries in ", length(unique(r$tag)), " groups.\n", sep = "")
  if (any(!nzchar(r$url))) cat("  No URL for: ", paste(r$title[!nzchar(r$url)], collapse = "; "), "\n", sep = "")
  dup <- r$url[nzchar(r$url) & duplicated(r$url)]
  if (length(dup)) cat("  Same URL used twice: ", paste(unique(dup), collapse = "; "), "\n", sep = "")
  if (any(!nzchar(r$tag))) cat("  Entries with no Tag go under 'Other'.\n")
  stale <- grepl("cod-ab|OCHA|mozambique-health-facilities|health facilit|administrative boundar", paste(r$title, r$url), ignore.case = TRUE)
  if (any(stale)) cat("  These describe a boundary or facility source. DET now adds the real sources automatically, ",
                      "so remove them if they are out of date: ", paste(r$title[stale], collapse = "; "), "\n", sep = "")

  ## in-text citations (Surname et al., 2025) with no matching reference
  txt <- paste(readLines(.ref_profile(slug), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  txt <- sub("(?s)##\\s*11[.)]?\\s.*$", "", txt, perl = TRUE)
  m <- unlist(regmatches(txt, gregexpr("[A-Z][A-Za-zÀ-ÿ'\\-]+(?= et al\\.?,? \\(?[0-9]{4})", txt, perl = TRUE)))
  m <- sort(unique(m))
  hay <- tolower(paste(r$title, r$description, r$url))
  miss <- m[!vapply(m, function(s) any(grepl(tolower(s), hay, fixed = TRUE)), logical(1))]
  if (length(miss)) cat("  Cited in the text but the reference list does not mention the first author: ",
                        paste(miss, collapse = ", "), ". Put the author and year in the reference title.\n", sep = "")
  invisible(r)
}
