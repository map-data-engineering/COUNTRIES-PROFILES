## ==========================================================================
##  R/facilities.R
##  Shared reader for the health facility list (used by fig_facility_map.R,
##  fig_facility_rank.R and the generated paragraphs).
##
##  INPUT: the "Facilities" tab of the country's epi workbook
##    (submissions/<slug>/epi_table_<slug>.xlsx). One row per facility.
##    Column names are fixed, researchers do not rename them:
##      Facility_name   text                                   (required)
##      Tier            Tertiary, Secondary or Primary          (required)
##      Longitude       decimal degrees                         (required)
##      Latitude        decimal degrees                         (required)
##      Facility_type   original wording, for reference only    (optional)
##  Province and district are NOT asked for: they are worked out from the
##  coordinates and the same boundaries as the admin map.
##  Source text for the caption: column facility_source in
##  config/country_settings.csv (for example "HealthScope, extracted October 2026").
## ==========================================================================

source(file.path("R", "theme.R"))

fac_tier_levels <- c("Tertiary", "Secondary", "Primary")
## Three clearly different colours (Okabe-Ito, safe for colour-blind readers)
fac_tier_cols   <- c(Tertiary = "#D55E00", Secondary = "#0072B2", Primary = "#009E73")
fac_tier_shapes <- c(Tertiary = 23, Secondary = 22, Primary = 21)
fac_tier_sizes  <- c(Tertiary = 3.6, Secondary = 2.6, Primary = 1.3)
fac_tier_labels <- c(Tertiary  = "Tertiary hospital",
                     Secondary = "Secondary hospital",
                     Primary   = "Primary (health centre, post)")

read_facilities <- function(slug, path = NULL, quiet = FALSE) {
  d <- read_epi_sheet(slug, "Facilities", path)
  d <- as.data.frame(d, stringsAsFactors = FALSE)
  names(d) <- trimws(names(d))
  need <- c("Facility_name", "Tier", "Longitude", "Latitude")
  miss <- setdiff(need, names(d))
  if (length(miss))
    stop("The Facilities tab is missing column(s): ", paste(miss, collapse = ", "),
         ". Columns found: ", paste(names(d), collapse = ", "),
         ". Use the exact names from the DET tab file.")

  f <- data.frame(name = as.character(d$Facility_name), tier = trimws(as.character(d$Tier)),
                  lon = suppressWarnings(as.numeric(d$Longitude)),
                  lat = suppressWarnings(as.numeric(d$Latitude)), stringsAsFactors = FALSE)
  f <- f[!(is.na(f$name) & is.na(f$lon) & is.na(f$lat)), ]            # empty rows

  ## Tier must be one of the three words (case ignored)
  f$tier <- fac_tier_levels[match(tolower(f$tier), tolower(fac_tier_levels))]
  if (anyNA(f$tier)) {
    message(sum(is.na(f$tier)), " facilities have a Tier that is not Tertiary, Secondary or Primary and are left out.")
    f <- f[!is.na(f$tier), ]
  }
  bad <- is.na(f$lon) | is.na(f$lat) | f$lon == 0 | f$lat == 0
  if (any(bad)) { message(sum(bad), " facilities have no usable coordinates and are left out."); f <- f[!bad, ] }
  if (!nrow(f)) stop("No usable facilities in the Facilities tab.")
  dup <- duplicated(f[, c("name", "lon", "lat")])
  if (any(dup)) { message(sum(dup), " duplicate rows (same name and location) removed."); f <- f[!dup, ] }

  ## Province from the coordinates; points outside the country are dropped
  adm1 <- sf::st_read(file.path("data", "boundaries", slug, "adm1.gpkg"), quiet = TRUE)
  pts  <- sf::st_as_sf(f, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
  suppressMessages(sf::sf_use_s2(FALSE)); on.exit(suppressMessages(sf::sf_use_s2(TRUE)), add = TRUE)
  pts  <- sf::st_transform(pts, sf::st_crs(adm1))
  pts$.id <- seq_len(nrow(pts))
  j <- suppressMessages(sf::st_join(pts, adm1["name_1"]))
  j <- j[!duplicated(j$.id), ]            # a point on a shared border can match twice
  j$.id <- NULL
  ## Boundaries are simplified, so coastal and border points can fall just outside.
  ## Keep points within about 5 km (0.05 degrees) of a province and give them the nearest one.
  out <- is.na(j$name_1)
  if (any(out)) {
    near <- suppressMessages(sf::st_nearest_feature(j[out, ], adm1))
    dist <- suppressMessages(as.numeric(sf::st_distance(j[out, ], adm1[near, ], by_element = TRUE)))
    close <- dist < 0.05
    tmp <- j$name_1[out]; tmp[close] <- adm1$name_1[near][close]; j$name_1[out] <- tmp
    if (any(close)) message(sum(close), " facilities were just outside the simplified boundary (under 5 km) and were given the nearest ", tolower(get_country_settings(slug)$admin1_label), ".")
    far <- is.na(j$name_1)
    if (any(far)) {
      message(sum(far), " facilities are well outside the country boundary and are left out",
              if (sum(far) <= 5) paste0(": ", paste(j$name[far], collapse = "; ")) else "", ".")
      j <- j[!far, ]
    }
  }
  j$tier <- factor(j$tier, levels = fac_tier_levels)
  if (!quiet) message(nrow(j), " facilities: ", paste(names(table(j$tier)), table(j$tier), collapse = ", "))
  j
}

## Source line for the caption
facility_source <- function(slug) {
  s   <- get_country_settings(slug)
  src <- if ("facility_source" %in% names(s) && !is.na(s$facility_source) && nzchar(s$facility_source))
           s$facility_source else "Health facility list supplied by the country team (source to be confirmed)"
  paste0(src, ". Province from facility coordinates and MAP boundaries.")
}

## --------------------------------------------------------------------------
##  Narrative sentences built from the data (so numbers can never go stale)
## --------------------------------------------------------------------------
.fac_pct <- function(x) paste0(round(100 * x), "%")
.fac_list <- function(x) if (length(x) <= 1) x else paste0(paste(x[-length(x)], collapse = ", "), " and ", x[length(x)])

facility_facts <- function(slug) {
  s    <- get_country_settings(slug)
  f    <- sf::st_drop_geometry(read_facilities(slug, quiet = TRUE))
  adm1 <- sf::st_read(file.path("data", "boundaries", slug, "adm1.gpkg"), quiet = TRUE)
  tidy <- function(x) gsub("\\b(De|Do|Da|Dos|Das)\\b", "\\L\\1", x, perl = TRUE)
  f$name_1 <- tidy(f$name_1); adm1$name_1 <- tidy(adm1$name_1)
  area <- as.numeric(sf::st_area(sf::st_make_valid(adm1))) / 1e6
  cnt  <- as.integer(table(factor(f$name_1, levels = adm1$name_1)))
  by   <- data.frame(province = adm1$name_1, n = cnt, area_km2 = area, dens = 10000 * cnt / area,
                     stringsAsFactors = FALSE)
  hosp <- f[f$tier %in% c("Tertiary", "Secondary"), ]
  list(s = s, n = nrow(f), by = by[order(-by$n), ], n_hosp = nrow(hosp),
       hosp_by = sort(table(factor(hosp$name_1, levels = adm1$name_1)), decreasing = TRUE),
       n_prov = nrow(by))
}

facility_text_rank <- function(slug) {
  x <- facility_facts(slug); b <- x$by; L <- tolower(x$s$admin1_label)
  top3 <- head(b, 3); low <- b[which.min(b$n), ]
  dhi <- b[which.max(b$dens), ]; dlo <- b[which.min(b$dens), ]
  paste0(
    "The ", format(x$n, big.mark = ","), " geolocated facilities are unevenly distributed across the ",
    x$n_prov, " ", L, "s, with ", .fac_list(paste0(top3$province, " (", top3$n, ")")),
    " together holding ", .fac_pct(sum(top3$n) / x$n), " of the national total, while ",
    low$province, " accounts for just ", low$n, ". Density tells a different story from counts: ",
    dhi$province, " has ", format(round(dhi$dens), big.mark = ","), " facilities per 10,000 km\u00b2 against ",
    format(round(dlo$dens, 1), nsmall = 1), " in ", dlo$province, ".")
}

facility_text_map <- function(slug) {
  x <- facility_facts(slug); L <- tolower(x$s$admin1_label)
  hb <- x$hosp_by[x$hosp_by > 0]; top <- head(hb, 2)
  paste0(
    "Of the facilities mapped, ", x$n_hosp, " are hospitals (secondary or tertiary level). The largest numbers are in ",
    .fac_list(paste0(names(top), " (", as.integer(top), ")")), "; ",
    sum(x$hosp_by == 0), " of ", x$n_prov, " ", L, "s have none recorded in this dataset.")
}
