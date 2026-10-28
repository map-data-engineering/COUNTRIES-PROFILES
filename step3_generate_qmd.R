# STEP 3 (v2): generate countries/<slug>_TEST.qmd from a country submission.
#
# What is read from where:
#   Narrative, captions, images, other tables ... profile_<country>.md
#   Section 2 table (headline statistics) ...... epi table, Types = KCI
#   Section 6a table (DHIS2 indicators) ......... epi table, Types = DHIS2,
#                                                  arranged by config/display_dhis2.csv
#   Section 6b table (survey indicators) ........ raw StatCompiler export, read only,
#                                                  arranged by config/display_survey.csv
#   Script-built figures (admin map, timeline) .. config/figures.csv lists which
#                                                  figure replaces the Nth image in
#                                                  which section. The caption and
#                                                  source line come from the figure
#                                                  script. If a figure's inputs are
#                                                  missing, the researcher's own
#                                                  image is kept and a note is printed.
#
# Writes a *_TEST.qmd so you can review before replacing the live page.
#
# HOW TO RUN: open the repo folder (COUNTRIES-PROFILES) as the working
# directory, on your submission branch, then run this whole script.

library(stringr)
library(dplyr)
library(openxlsx)

# ---------- 1. Settings: the only lines to change for another country ----------
country_name <- "Benin"
slug         <- "benin"   # folder name under submissions/
dhis2_year   <- "2022"         # year shown in Section 6a. Must match the year in the .md caption.
survey_rounds <- 5             # most recent survey rounds shown in Section 6b

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
sc_file       <- pick_one("^STATcompilerExport.*\\.xlsx$", "StatCompiler export .xlsx file")
profile_path   <- file.path(sub_dir, profile_file)
epi_table_path <- file.path(sub_dir, epi_file)
sc_path        <- file.path(sub_dir, sc_file)

# Paths as seen from INSIDE countries/, where the generated .qmd lives and runs
images_rel_path    <- paste0("../submissions/", slug, "/Images/")
epi_table_rel_path <- paste0("../submissions/", slug, "/", epi_file)
sc_rel_path        <- paste0("../submissions/", slug, "/", sc_file)

cat("Profile:    ", profile_path, "\n")
cat("Epi table:  ", epi_table_path, "\n")
cat("StatCompiler:", sc_path, " (raw file, read only)\n\n")

# ---------- 3. Check the epi table before using it ----------
epi_check <- read.xlsx(epi_table_path, sheet = "Data")
need <- c("Types", "Country", "Metric", "Year", "Value", "Unit", "Source", "Link", "Retrieved_via")
miss <- setdiff(need, names(epi_check))
if (length(miss) > 0) {
  stop("The epi table is missing column(s): ", paste(miss, collapse = ", "),
       ". Copy the missing column(s) into the Data tab from epi_table_TEMPLATE.xlsx (researcher_pack), keeping the header names exactly.")
}
mine <- epi_check[!is.na(epi_check$Country) & epi_check$Country == country_name, ]
cat("Epi table rows for", country_name, "by Types:\n")
print(table(mine$Types))
cat("\n")

if (sum(mine$Types == "KCI", na.rm = TRUE) == 0) stop("No KCI rows for ", country_name, " in the epi table.")
use_dhis2 <- sum(mine$Types == "DHIS2" & as.character(mine$Year) == dhis2_year, na.rm = TRUE) > 0
if (!use_dhis2) {
  cat("NOTE: no DHIS2 rows for ", country_name, " with Year = ", dhis2_year,
      ". Section 6a keeps the researcher's own table. Ask the researcher for DHIS2 rows, or check dhis2_year.\n\n", sep = "")
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

# ---- The DET-owned display list for Section 6a ----
display_path <- file.path("config", "display_dhis2.csv")
if (!file.exists(display_path)) stop("Cannot find ", display_path, ". Run this script from the repo root.")
disp <- read.csv(display_path, stringsAsFactors = FALSE, na.strings = "")
if (!all(c("Group", "Metric") %in% names(disp))) stop(display_path, " must have columns Group and Metric.")
key <- function(x) tolower(trimws(x))
if (anyDuplicated(key(disp$Metric))) stop("Duplicate Metric names in ", display_path)

now <- mine[mine$Types == "DHIS2" & as.character(mine$Year) == dhis2_year, ]
in_list   <- key(now$Metric) %in% key(disp$Metric)
is_hidden <- key(now$Metric) %in% key(disp$Metric[disp$Group == "hidden"])
cat(sum(in_list & !is_hidden), "of", nrow(now), "DHIS2 rows will be shown in Section 6a;",
    sum(is_hidden), "are kept in the epi table but hidden by the display list.\n")
if (any(!in_list)) {
  cat("Not in the display list (they will appear under 'Other'):\n"); print(now$Metric[!in_list])
  warning("Some DHIS2 metrics are not in config/display_dhis2.csv. Add them, or fix the spelling in the epi table.")
}
if ("Unit" %in% names(disp)) {
  pos <- match(key(now$Metric), key(disp$Metric))
  bad <- !is.na(pos) & !is.na(disp$Unit[pos]) & trimws(now$Unit) != disp$Unit[pos]
  if (any(bad)) {
    print(data.frame(Metric = now$Metric[bad], Unit_in_epi_table = now$Unit[bad], Standard_unit = disp$Unit[pos][bad]))
    warning("Unit differs from the standard unit in the display list (listed above).")
  }
}
cat("\n")

# ---- The raw StatCompiler export (read only) ----
source(file.path("R", "statcompiler.R"))
check_statcompiler(sc_path, country_name, file.path("config", "display_survey.csv"), survey_rounds)

# ---------- 4. Read the profile, fix image paths ----------
raw <- paste(readLines(profile_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
raw <- str_replace_all(raw, "\r\n", "\n")

# A text line directly above '---' is read by markdown as a HEADING (big, bold text).
# Put a blank line before every '---' line so it stays a divider.
n_setext <- str_count(raw, "(?m)^[^\\n]*[^\\s\\n][^\\n]*\\n-{3,}[ \\t]*(?=\\n|$)")
if (n_setext > 0) {
  raw <- str_replace_all(raw, "(?m)([^\\s\\n][^\\n]*)\\n(-{3,}[ \\t]*)(?=\\n|$)", "\\1\n\n\\2")
  cat("NOTE: added a blank line before ", n_setext, " '---' divider(s) in the profile, ",
      "so the paragraph above is not turned into a heading. Ask the researcher to leave a blank line before '---'.\n\n", sep = "")
}

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

# Section 6a uses its own template: rows are grouped and ordered by the display
# list, hidden rows are left out, and when every row shares one source the
# source is written once under the table instead of on every row.
dhis2_template <- r"---(
```{r}
#| echo: false
#| message: false
suppressPackageStartupMessages({ library(dplyr); library(openxlsx); library(kableExtra) })

epi_data <- read.xlsx("@@EPI@@", sheet = "Data")
disp <- read.csv("@@DISPLAY@@", stringsAsFactors = FALSE, na.strings = "")

esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
fmt <- function(v) {
  n <- suppressWarnings(as.numeric(v))
  out <- as.character(v)
  whole <- !is.na(n) & abs(n - round(n)) < 1e-9
  dec <- !is.na(n) & !whole
  out[whole] <- formatC(n[whole], format = "f", digits = 0, big.mark = ",")
  out[dec] <- formatC(round(n[dec], 1), format = "f", digits = 1, big.mark = ",")
  out
}
key <- function(x) tolower(trimws(x))

d <- epi_data %>%
  filter(Types == "DHIS2", Country == "@@COUNTRY@@", as.character(Year) == "@@YEAR@@")

# Group, label and order come from the display list. Anything not on the
# list goes to the end under 'Other'; rows marked 'hidden' are left out.
pos <- match(key(d$Metric), key(disp$Metric))
d$Group <- ifelse(is.na(pos), "Other", disp$Group[pos])
d$Label <- ifelse(is.na(pos) | is.na(disp$Label[pos]), d$Metric, disp$Label[pos])
d$Order <- ifelse(is.na(pos), 1e6 + seq_len(nrow(d)), pos)
d <- d[d$Group != "hidden", ]
group_levels <- unique(c(disp$Group[disp$Group != "hidden"], "Other"))
d <- d[order(match(d$Group, group_levels), d$Order), ]

# One shared source? Then say it once under the table.
base <- trimws(sub(",?\\s*Table\\s+\\d+\\s*$", "", d$Source))
ref  <- ifelse(grepl("Table\\s+\\d+\\s*$", d$Source), sub("^.*(Table\\s+\\d+)\\s*$", "\\1", d$Source), "")
lnk  <- ifelse(is.na(d$Link), "", d$Link)
one_source <- length(unique(base)) == 1 && length(unique(lnk)) == 1 &&
  length(unique(d$Retrieved_via)) == 1

tbl <- data.frame(Indicator = esc(d$Label), Value = fmt(d$Value),
                  Unit = ifelse(d$Unit == "text", "", esc(d$Unit)),
                  stringsAsFactors = FALSE)
if (one_source) {
  if (any(ref != "")) tbl$Refer <- ref
} else {
  tbl$Source <- ifelse(lnk == "", esc(d$Source), paste0("<a href='", lnk, "'>", esc(d$Source), "</a>"))
  tbl$`Retrieved via` <- esc(d$Retrieved_via)
}
tbl[is.na(tbl)] <- ""

idx <- table(factor(d$Group, levels = unique(d$Group)))
k <- kbl(tbl, escape = FALSE) %>%
  kable_styling(bootstrap_options = c("hover", "condensed"), full_width = TRUE, font_size = 13) %>%
  row_spec(0, bold = TRUE, background = "#1F3A5F", color = "white") %>%
  pack_rows(index = setNames(as.integer(idx), names(idx)),
            label_row_css = "background-color: #EEF2F7; color: #1F3A5F; font-weight: 600;")

note <- ""
if (one_source) {
  src <- if (lnk[1] == "") esc(base[1]) else paste0("<a href='", lnk[1], "'>", esc(base[1]), "</a>")
  note <- paste0("<p class='det-source'><strong>Source:</strong> ", src, " (@@YEAR@@ data). Retrieved via: ",
                 esc(d$Retrieved_via[1]), ".",
                 if (any(ref != "")) " Refer gives the table number in the source document, not a table on this page." else "",
                 "</p>")
}
knitr::asis_output(paste0(as.character(k), note))
```
)---"

make_dhis2_chunk <- function() {
  out <- dhis2_template
  out <- gsub("@@EPI@@", epi_table_rel_path, out, fixed = TRUE)
  out <- gsub("@@DISPLAY@@", "../config/display_dhis2.csv", out, fixed = TRUE)
  out <- gsub("@@COUNTRY@@", country_name, out, fixed = TRUE)
  out <- gsub("@@YEAR@@", dhis2_year, out, fixed = TRUE)
  out
}

survey_template <- r"---(
```{r}
#| echo: false
#| message: false
source("../R/statcompiler.R")
survey_table("@@SC@@", "@@COUNTRY@@", "../config/display_survey.csv", n_rounds = @@ROUNDS@@)
```
)---"
make_survey_chunk <- function() {
  out <- survey_template
  out <- gsub("@@SC@@", sc_rel_path, out, fixed = TRUE)
  out <- gsub("@@COUNTRY@@", country_name, out, fixed = TRUE)
  out <- gsub("@@ROUNDS@@", as.character(survey_rounds), out, fixed = TRUE)
  out
}

kci_chunk    <- make_table_chunk("KCI")
dhis2_chunk  <- make_dhis2_chunk()
survey_chunk <- make_survey_chunk()

# ---------- 6a2. Which DET-built pieces can be used for this country ----------
sheets_present <- openxlsx::getSheetNames(epi_table_path)
use_res   <- "Insecticide_susceptibility" %in% sheets_present && file.exists(file.path("R", "sec10_vector_profile.R"))
use_mech  <- use_res && "Resistance_mechanisms" %in% sheets_present
use_refs  <- file.exists(file.path("R", "references.R"))
if (use_res)  cat("Section 10 tables 9a", if (use_mech) "and 9b", "will be built from the epi table tabs.\n")
if (!use_res) cat("No 'Insecticide_susceptibility' tab: the researcher's typed Section 10 tables are kept.\n")
if (use_refs) cat("Section 11 will be arranged by R/references.R.\n")

# ---------- 6b. Script-built figures ----------
# Each row of config/figures.csv replaces the next image block (image line,
# "Figure N" line, Source line) in its section with a live R chunk that draws
# the figure at build time. Quarto numbers these figures automatically.
figures_path <- file.path("config", "figures.csv")
fig_rows <- if (file.exists(figures_path)) {
  read.csv(figures_path, stringsAsFactors = FALSE, na.strings = "")
} else {
  cat("No", figures_path, "found: no script-built figures.\n"); NULL
}
fig_ok <- logical(0)
if (!is.null(fig_rows) && nrow(fig_rows) > 0) {
  need_cols <- c("section", "fig_id", "script", "plot_fn", "text_fn", "width", "height",
                 "height_fn", "extra_fn", "extra_title", "needs_sheet", "needs_path")
  if (!all(need_cols %in% names(fig_rows))) {
    stop(figures_path, " must have columns: ", paste(need_cols, collapse = ", "))
  }
  settings_path <- file.path("config", "country_settings.csv")
  settings_ok <- file.exists(settings_path) &&
    slug %in% read.csv(settings_path, stringsAsFactors = FALSE)$slug
  if (!settings_ok) cat("No row for '", slug, "' in ", settings_path,
                        ". Script-built figures are skipped.\n", sep = "")
  sheets_present <- openxlsx::getSheetNames(epi_table_path)

  fig_ok <- vapply(seq_len(nrow(fig_rows)), function(k) {
    r <- fig_rows[k, ]
    skip <- function(why) { cat("Skipping figure '", r$fig_id, "': ", why,
                                ". The researcher's own image is kept.\n", sep = ""); FALSE }
    if (!settings_ok) return(FALSE)
    if (!file.exists(file.path("R", r$script))) return(skip(paste0("R/", r$script, " not found")))
    if (!is.na(r$needs_sheet) && !(r$needs_sheet %in% sheets_present))
      return(skip(paste0("the epi table has no '", r$needs_sheet, "' sheet")))
    if (!is.na(r$needs_sheet)) {
      sh <- tryCatch(openxlsx::read.xlsx(epi_table_path, sheet = r$needs_sheet),
                     error = function(e) NULL)
      # a row counts only if its key column is filled (the template pre-fills other columns)
      key_col <- c(Timeline = "Event", Health_system = "Level_name", Facilities = "Facility_name")[r$needs_sheet]; key_col <- if (is.na(key_col)) NULL else unname(key_col)
      filled <- function(v) !is.na(v) & trimws(as.character(v)) != ""
      has_rows <- !is.null(sh) && nrow(sh) > 0 &&
        (if (!is.null(key_col) && key_col %in% names(sh)) any(filled(sh[[key_col]]))
         else any(apply(sh, 1, function(z) any(filled(z)))))
      if (!has_rows) return(skip(paste0("the '", r$needs_sheet, "' sheet has no rows")))
    }
    if (!is.na(r$needs_path)) {
      p <- gsub("{slug}", slug, r$needs_path, fixed = TRUE)
      if (!file.exists(p)) return(skip(paste0(p, " not found")))
    }
    TRUE
  }, logical(1))
  cat(sum(fig_ok), "of", nrow(fig_rows), "script-built figures will be used.\n\n")
}

# The page runs from inside countries/, but the figure scripts read paths
# from the repo root, so every call goes through with_root().
make_setup_chunk <- function(scripts) {
  paste(c("```{r}", "#| include: false",
          'with_root <- function(expr) { old <- setwd(".."); on.exit(setwd(old)); expr }',
          "with_root({", paste0('  source("R/', scripts, '")'), "})",
          "```", "", ""), collapse = "\n")
}

res_chunk <- function(fn) {
  paste(c("```{r}", "#| echo: false", "#| message: false",
          paste0('knitr::kable(with_root(', fn, '("', slug, '")), escape = FALSE, align = "l")'),
          "```"), collapse = "\n")
}

make_refs_chunk <- function(used) {
  u <- paste0("c(", paste0('"', used, '"', collapse = ", "), ")")
  if (length(used) == 0) u <- "character(0)"
  paste(c("```{r}", "#| echo: false", "#| results: asis",
          paste0('cat(with_root(render_references("', slug, '", ', u, ')), sep = "\\n")'),
          "```"), collapse = "\n")
}

make_lead_chunk <- function(fn) {
  paste(c("```{r}", "#| echo: false", "#| results: asis", "#| message: false", "#| warning: false",
          paste0('cat(with_root(', fn, '("', slug, '")))'), "```", "", ""), collapse = "\n")
}


# One look for every Source line, and italic scientific names throughout.
source(file.path("R", "text_utils.R"))

standardise_source_lines <- function(lines) {
  out <- character(0); in_code <- FALSE
  for (ln in lines) {
    if (grepl("^\\s*```", ln)) in_code <- !in_code
    if (!in_code) {
      ln <- sub("^\\*Source:?\\s*(.*?)\\*\\s*$", "**Source:** \\1", ln, perl = TRUE)   # *Source: ...*  ->  **Source:** ...
      if (grepl("^\\*\\*Source:?\\*\\*:?\\s*\\S", ln)) {
        ln <- sub("^\\*\\*Source:?\\*\\*:?\\s*", "**Source:** ", ln)
        out <- c(out, "", "::: {.det-source}", ln, ":::", ""); next
      }
    }
    out <- c(out, ln)
  }
  out
}

italicise_lines <- function(lines) {
  in_code <- FALSE
  for (i in seq_along(lines)) {
    if (grepl("^\\s*```", lines[i])) { in_code <- !in_code; next }
    if (in_code || grepl("^\\s*(#|<|!\\[|:::)", lines[i])) next
    lines[i] <- italicise_species(lines[i])
  }
  lines
}

# Researcher images: turn  ![..](path)  followed by  **Figure N** caption  into a
# Quarto figure, so typed and scripted figures share ONE automatic numbering.
typed_fig_n <- 0
number_typed_figures <- function(lines) {
  out <- character(0); i <- 1; in_code <- FALSE
  while (i <= length(lines)) {
    ln <- lines[i]
    if (grepl("^\\s*```", ln)) in_code <- !in_code
    m <- regmatches(ln, regexec("^!\\[[^]]*\\]\\((.+)\\)\\s*(\\{[^}]*\\})?\\s*$", ln))[[1]]
    if (!in_code && length(m) > 0) {
      k <- i + 1
      while (k <= length(lines) && !nzchar(trimws(lines[k])) && k - i < 3) k <- k + 1
      cm <- if (k <= length(lines)) regmatches(lines[k], regexec("^\\*\\*Figure\\s*[0-9]*\\s*[:.]?\\s*\\*\\*\\s*[:.]?\\s*(.*)$", lines[k]))[[1]] else character(0)
      if (length(cm) > 0 && nzchar(trimws(cm[2]))) {
        typed_fig_n <<- typed_fig_n + 1
        cap <- gsub("[][]", "", trimws(cm[2]))
        out <- c(out, paste0("![", cap, "](", m[2], "){#fig-r", typed_fig_n, "}"))
        i <- k + 1; next
      }
    }
    out <- c(out, ln); i <- i + 1
  }
  out
}

make_fig_chunk <- function(r) {
  id <- r$fig_id; v <- gsub("-", "_", id)
  q  <- function(x) paste0('"', x, '"')
  h  <- if (!is.na(r$height_fn)) paste0("!expr with_root(", r$height_fn, "(", q(slug), "))") else
          as.character(ifelse(is.na(r$height), 6.5, r$height))
  parts <- c(
    "```{r}", "#| include: false",
    paste0("txt_", v, " <- with_root(", r$text_fn, "(", q(slug), "))"),
    "```", "",
    "```{r}",
    paste0("#| label: fig-", id),
    "#| echo: false", "#| message: false", "#| warning: false",
    paste0("#| fig-cap: !expr txt_", v, "$caption"),
    paste0("#| fig-width: ", r$width),
    paste0("#| fig-height: ", h),
    paste0("with_root(", r$plot_fn, "(", q(slug), "))"),
    "```", "",
    paste0("**Source:** `r italicise_species(txt_", v, "$source)`"), "")
  if (!is.na(r$extra_fn)) {
    parts <- c(parts, "```{r}", "#| echo: false", "#| results: asis",
               paste0('cat("<details><summary>', r$extra_title, '</summary>\\n\\n")'),
               paste0("print(knitr::kable(with_root(", r$extra_fn, "(", q(slug), "))))"),
               'cat("\\n\\n</details>\\n")', "```", "")
  }
  paste(parts, collapse = "\n")
}

# Replace the first image block in a section: the image line plus any
# directly following "**Figure ...**" and "**Source:**" lines.
replace_figure_block <- function(lines, replacement, match = NA, drop_para = FALSE, id = NA) {
  ## A marker line "<!-- DET-FIGURE: <fig_id> -->" in the profile says exactly where a
  ## scripted figure goes. If there is one, it wins; otherwise fall back to the image lines.
  marker <- if (!is.na(id)) which(grepl(paste0("DET-FIGURE:\\s*", id, "\\b"), lines)) else integer(0)
  img <- if (length(marker)) marker else which(grepl("^\\s*!\\[", lines))
  ## Optional: only take the image whose line matches this text (figures.csv column img_match)
  if (!length(marker) && !is.na(match) && nzchar(match)) img <- img[grepl(match, lines[img], ignore.case = TRUE)]
  if (length(img) == 0) return(c(lines, "", replacement))
  i <- img[1]; j <- i
  ## When the text above the figure is generated from data, drop the researcher's own paragraph
  if (drop_para) {
    e <- i - 1
    while (e >= 1 && !nzchar(trimws(lines[e]))) e <- e - 1
    b <- e
    while (b >= 1 && nzchar(trimws(lines[b]))) b <- b - 1
    if (e >= 1 && !grepl("^\\s*(\\*\\*|#)", lines[b + 1]) &&
        !grepl("```|DET-FIGURE", paste(lines[(b + 1):e], collapse = "\n"))) {   # never drop a generated chunk or marker
      cat("  Replaced the researcher's paragraph with generated text: \"", substr(trimws(lines[b + 1]), 1, 60), "...\"\n", sep = "")
      lines <- lines[-((b + 1):e)]
      i <- i - (e - b); j <- i
    }
  }
  ## swallow the caption and Source lines that follow, allowing blank lines between them
  repeat {
    k <- j + 1
    while (k <= length(lines) && !nzchar(trimws(lines[k]))) k <- k + 1
    if (k <= length(lines) && grepl("^\\s*\\*\\*(Figure|Source)", lines[k]) && k - i < 8) j <- k else break
  }
  c(lines[seq_len(i - 1)], replacement, if (j < length(lines)) lines[(j + 1):length(lines)])
}

# ---------- 7. Assemble ----------
yaml_header <- paste0("---\n", "title: \"", country_name, " Malaria Epidemiology Summary\"\n",
                      "format: html\n", "---\n\n")
setup_scripts <- unique(c("text_utils.R", if (length(fig_ok)) fig_rows$script[fig_ok],
                          if (use_res) "sec10_vector_profile.R", if (use_refs) "references.R"))
if (length(setup_scripts)) yaml_header <- paste0(yaml_header, make_setup_chunk(setup_scripts))

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
    if (use_dhis2) lines <- replace_first_table(lines, dhis2_chunk, from = i6a, to = i6b - 1)
    i6b <- grep("^### 6b", lines)            # positions moved after the 6a swap
    lines <- replace_first_table(lines, survey_chunk, from = i6b, to = length(lines))
  }
  if (n == "10" && use_res) {
    i9a <- grep("^#+\\s*Table 9a", lines); i9b <- grep("^#+\\s*Table 9b", lines)
    if (length(i9a) == 1) {
      end <- if (length(i9b) == 1 && i9b > i9a) i9b - 1 else length(lines)
      lines <- replace_first_table(lines, res_chunk("tbl_susceptibility"), from = i9a, to = end)
    } else cat("Section 10: no single '### Table 9a' heading found, typed table kept.\n")
    i9b <- grep("^#+\\s*Table 9b", lines)
    if (use_mech && length(i9b) == 1) lines <- replace_first_table(lines, res_chunk("tbl_mechanisms"), from = i9b, to = length(lines))
  }
  if (n == "11" && use_refs) {
    used <- c(if (length(fig_ok) && any(fig_ok & fig_rows$fig_id == "admin-map")) "boundaries",
              if (length(fig_ok) && any(fig_ok & grepl("^facility", fig_rows$fig_id))) "facilities",
              if (length(fig_ok) && any(fig_ok & fig_rows$fig_id == "vectors")) "vectors")
    lines <- replace_first_table(lines, make_refs_chunk(used))
  }
  for (k in if (length(fig_ok)) which(fig_rows$section == as.integer(n) & fig_ok) else integer(0)) {
    lead <- if ("lead_fn" %in% names(fig_rows) && !is.na(fig_rows$lead_fn[k])) fig_rows$lead_fn[k] else NA
    lines <- replace_figure_block(lines,
                                  paste0(if (!is.na(lead)) make_lead_chunk(lead) else "", make_fig_chunk(fig_rows[k, ])),
                                  if ("img_match" %in% names(fig_rows)) fig_rows$img_match[k] else NA,
                                  drop_para = !is.na(lead),
                                  id = fig_rows$fig_id[k])
  }

  lines <- number_typed_figures(lines)
  lines <- standardise_source_lines(lines)
  lines <- italicise_lines(lines)

  body_parts <- c(body_parts, paste0("## ", n, ". ", sec$name, "\n"), paste(lines, collapse = "\n"), "\n\n")
}


# ---------- Abbreviations: the researcher's own 'Abbreviations' tab ----------
ab <- NULL
if ("Abbreviations" %in% openxlsx::getSheetNames(epi_table_path)) {
  ab <- tryCatch(openxlsx::read.xlsx(epi_table_path, "Abbreviations"), error = function(e) NULL)
  if (!is.null(ab) && all(c("Abbreviation", "Meaning") %in% names(ab))) {
    ab <- ab[!is.na(ab$Abbreviation) & nzchar(trimws(ab$Abbreviation)) &
             !is.na(ab$Meaning) & nzchar(trimws(ab$Meaning)), c("Abbreviation", "Meaning")]
    ab$Abbreviation <- trimws(ab$Abbreviation)
    ab <- ab[!duplicated(ab$Abbreviation), ]
    ab <- ab[order(toupper(ab$Abbreviation)), ]
  } else ab <- NULL
}
if (!is.null(ab) && nrow(ab) > 0) {
  tbl_md <- c("", "## Abbreviations", "",
              "| Abbreviation | Meaning |", "|---|---|",
              paste0("| ", ab$Abbreviation, " | ", ab$Meaning, " |"), "")
  body_parts <- c(body_parts, paste(tbl_md, collapse = "\n"))
} else {
  cat("\nNo 'Abbreviations' tab (or it is empty) in the epi table. Ask the researcher to list their abbreviations.\n")
}
## Check: capital-letter terms in the text that the researcher did not list
dat <- tryCatch(unlist(openxlsx::read.xlsx(epi_table_path, "Data")), error = function(e) "")
txt <- paste(c(unlist(body_parts), as.character(dat)), collapse = "\n")
txt <- gsub("(?s)```\\{r\\}.*?```", " ", txt, perl = TRUE)
txt <- gsub("https?://\\S+", " ", txt)
toks <- unique(unlist(regmatches(txt, gregexpr("\\b[A-Z][A-Z0-9]{1,7}\\b", txt))))
unknown <- setdiff(toks, if (is.null(ab)) character(0) else ab$Abbreviation)
if (length(unknown)) cat("\nCapital-letter terms not in the Abbreviations tab (add the real abbreviations, ignore the rest):\n  ",
                         paste(sort(unknown), collapse = ", "), "\n", sep = "")

final_qmd <- paste0(yaml_header, paste(body_parts, collapse = "\n"))
writeLines(final_qmd, output_path, useBytes = TRUE)

cat("Wrote", output_path, "\n")
cat("Section 2 table read from epi table: Types = KCI\n")
if (use_dhis2) cat("Section 6a table read from epi table: Types = DHIS2, Year =", dhis2_year, ", arranged by", display_path, "\n") else cat("Section 6a: researcher's own table kept (no DHIS2 rows).\n")
cat("Section 6b table read from the raw StatCompiler file:", sc_file, ", most recent", survey_rounds, "rounds\n")
cat("Path baked into the chunks (should start with '../'):", epi_table_rel_path, "\n")
if (any(fig_ok)) cat("Script-built figures in this page:", paste(fig_rows$fig_id[fig_ok], collapse = ", "), "\n")
if (use_res || use_refs) {
  cat("\nChecks:\n")
  with_root_here <- function(f) tryCatch(f(), error = function(e) cat("  ", conditionMessage(e), "\n"))
  if (use_res)  with_root_here(function() { source(file.path("R", "sec10_vector_profile.R")); resistance_checks(slug) })
  if (use_refs) with_root_here(function() { source(file.path("R", "references.R")); reference_checks(slug) })
}
cat("\nNext: quarto::quarto_render('", output_path, "')\n", sep = "")
