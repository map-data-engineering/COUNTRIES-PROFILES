# STEP 3 — Generate countries/mozambique_TEST.qmd from Edmund's real
# submission. Writes to a NEW test file, does NOT touch the live
# countries/mozambique.qmd, so you can review the output before replacing
# anything real.
#
# Builds on Step 1 (section splitting - confirmed 11/11 working) and
# Step 2 (image path fixing - confirmed working; KCI pull - confirmed
# working, with two data issues flagged back to Edmund separately).
#
# HOW TO RUN: adjust the paths below, run the whole script, then open
# countries/mozambique_TEST.qmd yourself to read it, and separately try
# rendering it with Quarto to see if it actually builds.

library(stringr)
library(dplyr)
library(openxlsx)
library(knitr)

# PATHS — matching the real repo structure at
# submissions/mozambique/ (confirmed after today's reorg: everything
# properly nested under mozambique/, not flat in submissions/).
# Run this script from the repo ROOT (COUNTRIES-PROFILES/), on the
# Mozambique-submission branch, so these relative paths resolve correctly.
profile_path   <- "submissions/mozambique/profile_Mozambique.md"
epi_table_path <- "submissions/mozambique/epi_table_TEMPLATE_v1.xlsx"
output_path    <- "countries/mozambique_TEST.qmd"
country_name   <- "Mozambique"
# Paths as seen from INSIDE countries/ (where the generated .qmd lives and
# executes), not as seen from the repo root where you're running this script.
images_rel_path <- "../submissions/mozambique/Images/"
epi_table_rel_path <- "../submissions/mozambique/epi_table_TEMPLATE_v1.xlsx"

# ---------- Re-run Step 1: split into sections ----------
raw <- paste(readLines(profile_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
raw <- str_replace_all(raw, "\r\n", "\n")

# ---------- Re-run Step 2a: fix image paths, across the WHOLE file this
# time (not just for display), so every section gets clean paths ----------
image_pattern <- "!\\[([^\\]]*)\\]\\(<?([^)>]+)>?\\)"
image_matches <- str_match_all(raw, image_pattern)[[1]]
fixed_raw <- raw
if (nrow(image_matches) > 0) {
  for (i in seq_len(nrow(image_matches))) {
    full_match <- image_matches[i, 1]
    alt_text   <- image_matches[i, 2]
    old_path   <- image_matches[i, 3]
    filename   <- basename(str_replace_all(old_path, "\\\\", "/"))
    new_path   <- paste0(images_rel_path, filename)
    new_ref    <- paste0("![", alt_text, "](", new_path, ")")
    fixed_raw  <- str_replace(fixed_raw, fixed(full_match), new_ref)
  }
}
cat("Fixed", nrow(image_matches), "image paths across the document\n")

# ---------- Split the FIXED text into sections ----------
header_pattern <- "(?m)^## (\\d+)\\.\\s*(.+)$"
matches <- str_locate_all(fixed_raw, header_pattern)[[1]]
headers <- str_match_all(fixed_raw, header_pattern)[[1]]

sections <- list()
for (i in seq_len(nrow(matches))) {
  n <- headers[i, 2]
  name <- str_trim(headers[i, 3])
  start <- matches[i, "end"] + 1
  end <- if (i < nrow(matches)) matches[i + 1, "start"] - 1 else nchar(fixed_raw)
  sections[[n]] <- list(name = name, content = str_trim(str_sub(fixed_raw, start, end)))
}
cat("Split into", length(sections), "sections\n\n")

# ---------- Build the Section 2 R chunk (live KCI pull, styled) ----------
# Unlike Step 2's version, this does NOT pre-compute the table here — it
# writes a live R chunk into the .qmd itself, so the table is pulled fresh
# from Excel every time the site rebuilds, not baked in once as static text.
kci_chunk <- paste0(
  "\n```{r}\n",
  "#| echo: false\n",
  "#| message: false\n",
  "library(dplyr); library(openxlsx); library(kableExtra)\n\n",
  "epi_data <- read.xlsx(\"", epi_table_rel_path, "\", sheet = \"Data\")\n\n",
  "kci_table <- epi_data %>%\n",
  "  filter(Types == \"KCI\", Country == \"", country_name, "\") %>%\n",
  "  select(Metric, Value, Unit, Year, Source) %>%\n",
  "  mutate(\n",
  "    Value = suppressWarnings(as.numeric(Value)),\n",
  "    Value = ifelse(is.na(Value), NA, round(Value, 1)),\n",
  "    Value = format(Value, big.mark = \",\", scientific = FALSE, trim = TRUE)\n",
  "  )\n\n",
  "kbl(kci_table, caption = \"Key demographic and malaria indicators\") %>%\n",
  "  kable_styling(bootstrap_options = c(\"striped\", \"hover\", \"condensed\"),\n",
  "                full_width = TRUE, font_size = 13) %>%\n",
  "  row_spec(0, bold = TRUE, background = \"#1F3A5F\", color = \"white\") %>%\n",
  "  column_spec(1, bold = TRUE) %>%\n",
  "  column_spec(2, width = \"12%\") %>%\n",
  "  column_spec(4, width = \"8%\")\n",
  "```\n\n"
)

# ---------- Assemble the final .qmd ----------
yaml_header <- paste0(
  "---\n",
  "title: \"", country_name, " Malaria Epidemiology Summary\"\n",
  "format: html\n",
  "---\n\n"
)

# For each section: Section 2 gets the LIVE Excel-pulled table instead of
# whatever was typed in the .md. Every other section passes through as-is
# (already has correct image paths from the fix above).
body_parts <- c()
for (n in as.character(1:11)) {
  sec <- sections[[n]]
  body_parts <- c(body_parts, paste0("## ", n, ". ", sec$name, "\n"))
  if (n == "2") {
    body_parts <- c(body_parts, kci_chunk)
  } else {
    body_parts <- c(body_parts, sec$content, "\n\n")
  }
}

final_qmd <- paste0(yaml_header, paste(body_parts, collapse = "\n"))
writeLines(final_qmd, output_path)

cat("Wrote", output_path, "\n")
cat("Length:", nchar(final_qmd), "characters\n")
cat("\nPath baked into the Section 2 chunk (should start with '../'):\n")
cat("  ", epi_table_rel_path, "\n")
cat("\nNext: open the file to read it, and try quarto::quarto_render('", output_path, "') to see if it actually renders.\n", sep = "")
