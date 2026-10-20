## ==========================================================================
##  R/fetch_boundaries.R
##  One-time helper, run by DET when a country is added (or boundaries are
##  refreshed). It downloads admin 1 and admin 2 boundaries from MAP via the
##  malariaAtlas package, removes water bodies you name, simplifies the
##  shapes, saves them for the site build, and logs the source in
##  config/boundaries.csv.
##
##  Run from the repo root:
##    source("R/fetch_boundaries.R")
##    fetch_boundaries("MOZ", "mozambique", drop_names = "Lake Malawi", version = "202403")
##
##  STATUS: tested on Mozambique (11 admin1, 161 admin2). Install rmapshaper
##  first so borders stay aligned: install.packages("rmapshaper")
## ==========================================================================

fetch_boundaries <- function(iso, slug, drop_names = character(0),
                             version = NULL, keep = 0.05, licence = "") {
  for (p in c("sf", "dplyr", "malariaAtlas")) {
    if (!requireNamespace(p, quietly = TRUE))
      stop("Package '", p, "' is needed. install.packages('", p, "')")
  }
  library(sf); library(dplyr)

  out_dir <- file.path("data", "boundaries", slug)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  ## ---- helper: one admin level -------------------------------------------
  get_level <- function(level_num) {
    args <- list(ISO = iso, admin_level = paste0("admin", level_num))
    if (!is.null(version)) args$version <- version   # pin it: see malariaAtlas::listShpVersions()
    x <- do.call(malariaAtlas::getShp, args)
    x <- sf::st_make_valid(sf::st_as_sf(x))
    ## Repair can leave mixed geometry types (polygon + line); keep polygons only
    n_before <- nrow(x)
    if (any(sf::st_geometry_type(x) == "GEOMETRYCOLLECTION")) {
      ## extract() can split one unit into several rows, so merge back by row id
      x$.row <- seq_len(nrow(x))
      attrs  <- sf::st_drop_geometry(x)
      geom   <- sf::st_collection_extract(x[, ".row"], "POLYGON")
      geom   <- dplyr::summarise(dplyr::group_by(geom, .row), .groups = "drop")
      x      <- dplyr::left_join(geom, attrs, by = ".row")
      x$.row <- NULL
    }
    x <- sf::st_cast(x, "MULTIPOLYGON")
    if (nrow(x) != n_before)
      stop("Row count changed during geometry repair (", n_before, " to ", nrow(x), "). Stopping.")
    name_col <- paste0("name_", level_num)
    if (!name_col %in% names(x)) stop("Column '", name_col, "' not found. Columns: ",
                                      paste(names(x), collapse = ", "))

    ## Water bodies: never dropped silently, never dropped by pattern.
    ## (Lago is a real district in Niassa, so a pattern would remove it.)
    looks_like_water <- grepl("^lake |lagoon|\\bwater\\b", x[[name_col]], ignore.case = TRUE)
    if (any(looks_like_water & !x[[name_col]] %in% drop_names)) {
      warning("Possible water bodies in admin", level_num, ": ",
              paste(x[[name_col]][looks_like_water & !x[[name_col]] %in% drop_names], collapse = ", "),
              ". Review, then pass them in drop_names if they are not real units.")
    }
    dropped <- x[[name_col]] %in% drop_names
    if (any(dropped)) message("admin", level_num, ": dropped ", paste(x[[name_col]][dropped], collapse = ", "))
    x <- x[!dropped, ]

    ## Name key for joins: lower case, no accents or punctuation
    x$name_key <- tolower(gsub("[^A-Za-z0-9]+", " ",
                               iconv(x[[name_col]], to = "ASCII//TRANSLIT")))
    x$name_key <- trimws(x$name_key)

    ## Simplify (keeps shared borders aligned) so the repo and builds stay small
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
      x <- rmapshaper::ms_simplify(x, keep = keep, keep_shapes = TRUE)
    } else {
      message("rmapshaper not installed: using sf::st_simplify (neighbouring borders may not align exactly).")
      x <- sf::st_simplify(x, preserveTopology = TRUE, dTolerance = 0.002)
    }
    x
  }

  adm1 <- get_level(1)
  adm2 <- get_level(2)

  sf::st_write(adm1, file.path(out_dir, "adm1.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  sf::st_write(adm2, file.path(out_dir, "adm2.gpkg"), delete_dsn = TRUE, quiet = TRUE)

  ## ---- log the source ----------------------------------------------------
  row <- data.frame(
    country        = slug,
    source         = "MAP admin boundaries via malariaAtlas",
    package_version = as.character(utils::packageVersion("malariaAtlas")),
    release_version = if (is.null(version)) "not pinned" else as.character(version),  # for example 202403
    retrieved_date = as.character(Sys.Date()),
    licence        = licence,                # fill in
    n_admin1       = nrow(adm1),
    n_admin2       = nrow(adm2),
    dropped        = paste(drop_names, collapse = "; "),
    stringsAsFactors = FALSE
  )
  reg <- file.path("config", "boundaries.csv")
  if (file.exists(reg)) {
    old <- utils::read.csv(reg, stringsAsFactors = FALSE, colClasses = "character")
    old <- old[old$country != slug, , drop = FALSE]
    row[] <- lapply(row, as.character)
    out <- dplyr::bind_rows(old, row)   # tolerates columns added since the file was created
  } else {
    dir.create("config", showWarnings = FALSE)
    out <- row
  }
  utils::write.csv(out, reg, row.names = FALSE)

  message("Saved ", nrow(adm1), " admin1 and ", nrow(adm2), " admin2 units to ", out_dir,
          ". Registry updated: ", reg)
  invisible(list(adm1 = adm1, adm2 = adm2))
}
