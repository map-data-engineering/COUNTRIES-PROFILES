# STEP 3 (v2): generate countries/<slug>_TEST.qmd from a country submission.
#
# What is read from where:
#   Narrative, captions, images, other tables ... profile_<country>.md
#   Section 2 table (headline statistics) ...... epi table, Types = KCI
#   Section 6a table (DHIS2 indicators) ......... epi table, Types = DHIS2
#   Section 6b table (survey indicators) ........ still the table in the .md
#
# Writes a *_TEST.qmd so you can review before replacing the live page.
#
# HOW TO RUN: open the repo folder (COUNTRIES-PROFILES) as the working
# directory, on your submission branch, then run this whole script.

library(stringr)
library(dplyr)
library(openxlsx)

# ---------- 1. Settings: the only lines to change for another country ----------
country_name <- "Mozambique"
slug         <- "mozambique"   # folder name under submissions/
dhis2_year   <- "2022"         # year shown in Section 6a. Must match the year in the .md caption.

sub_dir     <- file.path("submissions", slug)
output_path <- file.path("countries", paste0(slug, "_TEST.qmd"))

# ---------- 2. Find the two submission files (ignoring blank templates) ----------
pick_one <- function(pattern, what) {
  f <- list.files(sub_dir, pattern = pattern, ignore.case = TRUE)
  f <- f[!grepl("TEMPLATE", f, ignore.case = TRUE)]
  if (length(f) != 1) {
    stop("Expected exactly one ", what, " in ", sub_dir, " (blank TEMPLATE files are ignored) but found ",
         length(f), ": ", paste(f, collapse = ", "))
  }
  f
}
profile_file <- pick_one("^profile_.*\\.md$", "profile .md file")
epi_file     <- pick_one("^epi_table_.*\\.xlsx$", "epi table .xlsx file")
profile_path   <- file.path(sub_dir, profile_file)
epi_table_path <- file.path(sub_dir, epi_file)

# Paths as seen from INSIDE countries/, where the generated .qmd lives and runs
images_rel_path    <- paste0("../submissions/", slug, "/Images/")
epi_table_rel_path <- paste0("../submissions/", slug, "/", epi_file)

cat("Profile:    ", profile_path, "\n")
cat("Epi table:  ", epi_table_path, "\n\n")

# ---------- 3. Check the epi table before using it ----------
epi_check <- read.xlsx(epi_table_path, sheet = "Data")
need <- c("Types", "Country", "Metric", "Year", "Value", "Unit", "Source", "Link", "Retrieved_via")
miss <- setdiff(need, names(epi_check))
if (length(miss) > 0) {
  stop("The epi table is missing column(s): ", paste(miss, collapse = ", "),
       ". Please use epi_table_TEMPLATE_v2.xlsx.")
}
mine <- epi_check[!is.na(epi_check$Country) & epi_check$Country == country_name, ]
cat("Epi table rows for", country_name, "by Types:\n")
print(table(mine$Types))
cat("\n")

if (sum(mine$Types == "KCI", na.rm = TRUE) == 0) stop("No KCI rows for ", country_name, " in the epi table.")
if (sum(mine$Types == "DHIS2" & as.character(mine$Year) == dhis2_year, na.rm = TRUE) == 0) {
  stop("No DHIS2 rows for ", country_name, " with Year = ", dhis2_year, ". Section 6a would be empty.")
}

dups <- mine %>%
  filter(Types %in% c("KCI", "DHIS2")) %>%
  count(Types, Metric, Year) %>%
  filter(n > 1)
if (nrow(dups) > 0) { print(dups); warning("Duplicate Metric and Year rows in the epi table (listed above).") }

no_source <- mine %>% filter(Types %in% c("KCI", "DHIS2"), is.na(Source) | Source == "")
if (nrow(no_source) > 0) { print(no_source$Metric); warning("Rows with no Source (listed above).") }

no_via <- mine %>% filter(Types == "DHIS2", is.na(Retrieved_via) | Retrieved_via == "")
if (nrow(no_via) > 0) { print(no_via$Metric); warning("DHIS2 rows with no Retrieved_via (listed above).") }

# ---------- 4. Read the profile, fix image paths ----------
raw <- paste(readLines(profile_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
raw <- str_replace_all(raw, "\r\n", "\n")

image_pattern <- "!\\[([^\\]]*)\\]\\(<?([^)>]+)>?\\)"
image_matches <- str_match_all(raw, image_pattern)[[1]]
fixed_raw <- raw
if (nrow(image_matches) > 0) {
  for (i in seq_len(nrow(image_matches))) {
    alt_text <- image_matches[i, 2]
    filename <- basename(str_replace_all(image_matches[i, 3], "\\\\", "/"))
    new_ref  <- paste0("![", alt_text, "](", images_rel_path, filename, ")")
    fixed_raw <- str_replace(fixed_raw, fixed(image_matches[i, 1]), new_ref)
  }
}
cat("Fixed", nrow(image_matches), "image paths\n")

# ---------- 5. Split into the 11 sections ----------
header_pattern <- "(?m)^## (\\d+)\\.\\s*(.+)$"
matches <- str_locate_all(fixed_raw, header_pattern)[[1]]
headers <- str_match_all(fixed_raw, header_pattern)[[1]]
sections <- list()
for (i in seq_len(nrow(matches))) {
  n     <- headers[i, 2]
  start <- matches[i, "end"] + 1
  end   <- if (i < nrow(matches)) matches[i + 1, "start"] - 1 else nchar(fixed_raw)
  sections[[n]] <- list(name = str_trim(headers[i, 3]), content = str_trim(str_sub(fixed_raw, start, end)))
}
if (length(sections) != 11) stop("Expected 11 sections but found ", length(sections))
cat("Split into", length(sections), "sections\n\n")

# ---------- 6. Table chunk builder ----------
# Writes a live R chunk into the .qmd, so the table is rebuilt from the epi
# table every time the site is built. One template serves every table.
chunk_template <- r"---(
```{r}
#| echo: false
#| message: false
suppressPackageStartupMessages({ library(dplyr); library(openxlsx); library(kableExtra) })

epi_data <- read.xlsx("@@EPI@@", sheet = "Data")

esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

# Whole numbers get thousands separators; decimals get one decimal place;
# words (for example a city) are left as they are.
fmt <- function(v) {
  n <- suppressWarnings(as.numeric(v))
  out <- as.character(v)
  whole <- !is.na(n) & abs(n - round(n)) < 1e-9
  dec <- !is.na(n) & !whole
  out[whole] <- formatC(n[whole], format = "f", digits = 0, big.mark = ",")
  out[dec] <- formatC(round(n[dec], 1), format = "f", digits = 1, big.mark = ",")
  out
}

tbl <- epi_data %>%
  filter(Types == "@@TYPE@@", Country == "@@COUNTRY@@")
@@YEAR_FILTER@@
tbl <- tbl %>%
  transmute(
    Indicator = esc(Metric),
    Value = fmt(Value),
    Unit = ifelse(Unit == "text", "", esc(Unit)),
    Year = as.character(Year),
    Source = ifelse(is.na(Link) | Link == "", esc(Source),
                    paste0("<a href='", Link, "'>", esc(Source), "</a>")),
    `Retrieved via` = esc(Retrieved_via)
  ) %>%
  mutate(across(everything(), ~ ifelse(is.na(.x), "", .x)))
@@DROP_VIA@@
kbl(tbl, escape = FALSE) %>%
  kable_styling(bootstrap_options = c("striped", "hover", "condensed"),
                full_width = TRUE, font_size = 13) %>%
  row_spec(0, bold = TRUE, background = "#1F3A5F", color = "white") %>%
  column_spec(1, bold = TRUE)
```
)---"

make_table_chunk <- function(type, year = NULL, show_via = FALSE) {
  out <- chunk_template
  year_filter <- if (is.null(year)) "" else
    paste0('tbl <- tbl %>% filter(as.character(Year) == "', year, '")')
  drop_via <- if (show_via) "" else 'tbl <- tbl %>% select(-`Retrieved via`)'
  out <- gsub("@@EPI@@", epi_table_rel_path, out, fixed = TRUE)
  out <- gsub("@@TYPE@@", type, out, fixed = TRUE)
  out <- gsub("@@COUNTRY@@", country_name, out, fixed = TRUE)
  out <- gsub("@@YEAR_FILTER@@", year_filter, out, fixed = TRUE)
  out <- gsub("@@DROP_VIA@@", drop_via, out, fixed = TRUE)
  out
}

# Replace the first markdown table found between lines `from` and `to`
# with `chunk`, keeping every other line (captions, text) untouched.
# If there is no typed table there, insert `chunk` at the end of the block.
replace_first_table <- function(lines, chunk, from = 1, to = length(lines)) {
  idx <- from:to
  tbl_idx <- idx[grepl("^\\s*\\|", lines[idx])]
  if (length(tbl_idx) == 0) {
    # No typed table in this block (the new rule: numbers live in the epi table).
    # Put the chunk at the end of the block instead.
    return(c(lines[seq_len(to)], "", chunk, lines[seq_len(length(lines) - to) + to]))
  }
  first <- tbl_idx[1]
  last <- first
  while ((last + 1) %in% tbl_idx) last <- last + 1
  c(lines[seq_len(first - 1)], chunk, lines[seq_len(length(lines) - last) + last])
}

kci_chunk   <- make_table_chunk("KCI")
dhis2_chunk <- make_table_chunk("DHIS2", year = dhis2_year, show_via = TRUE)

# ---------- 7. Assemble ----------
yaml_header <- paste0("---\n", "title: \"", country_name, " Malaria Epidemiology Summary\"\n",
                      "format: html\n", "---\n\n")

body_parts <- c()
for (n in as.character(1:11)) {
  sec <- sections[[n]]
  lines <- strsplit(sec$content, "\n", fixed = TRUE)[[1]]

  if (n == "2") {
    lines <- replace_first_table(lines, kci_chunk)
  }
  if (n == "6") {
    i6a <- grep("^### 6a", lines)
    i6b <- grep("^### 6b", lines)
    if (length(i6a) != 1 || length(i6b) != 1 || i6a > i6b) {
      stop("Section 6 must contain exactly one '### 6a' heading followed by one '### 6b' heading.")
    }
    lines <- replace_first_table(lines, dhis2_chunk, from = i6a, to = i6b - 1)
  }

  body_parts <- c(body_parts, paste0("## ", n, ". ", sec$name, "\n"), paste(lines, collapse = "\n"), "\n\n")
}

final_qmd <- paste0(yaml_header, paste(body_parts, collapse = "\n"))
writeLines(final_qmd, output_path, useBytes = TRUE)

cat("Wrote", output_path, "\n")
cat("Section 2 table read from epi table: Types = KCI\n")
cat("Section 6a table read from epi table: Types = DHIS2, Year =", dhis2_year, "\n")
cat("Path baked into the chunks (should start with '../'):", epi_table_rel_path, "\n")
cat("\nNext: quarto::quarto_render('", output_path, "')\n", sep = "")
