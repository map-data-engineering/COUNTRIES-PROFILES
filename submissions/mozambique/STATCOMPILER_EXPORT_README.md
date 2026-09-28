# StatCompiler Export — What Goes Here

This folder should contain your actual DHS StatCompiler export file
(e.g. `STATcompilerExport2026_XXXX.xlsx`) alongside this note — **do not
retype StatCompiler numbers into `epi_table_TEMPLATE.xlsx`.**

## How to produce it

1. Go to https://www.statcompiler.com
2. Select your country and the survey(s) you want (most recent DHS/MIS is
   usually right, but include prior rounds too if you're populating trend
   data)
3. Select the malaria indicators you need — at minimum:
   - Malaria prevalence according to RDT
   - Malaria prevalence according to microscopy
   - ITN ownership / access / usage indicators
   - IRS coverage
   - IPTp coverage (2+ and 3+ doses)
   - Care-seeking behavior for fever in children under 5
   - ACT treatment among children with fever
4. Export as Excel (`.xlsx`)
5. Save the exported file directly into this folder, keeping its
   original StatCompiler filename — don't rename it, the filename is
   part of how we trace it back to that specific export.

## Why this matters

StatCompiler exports are traceable and re-fetchable — anyone can regenerate
the same numbers from the same query later. A number retyped into a shared
spreadsheet loses that traceability the moment it's copied. Keeping the
export as its own file means DET can always verify a number against its
original source without asking you to redo the lookup.

## If StatCompiler doesn't cover something

Some indicators (National Strategic Plan targets, World Bank figures,
values from other reports) genuinely aren't in StatCompiler. Those are
exactly what `epi_table_TEMPLATE.xlsx` in this folder is for — use it for
non-StatCompiler numbers only.
