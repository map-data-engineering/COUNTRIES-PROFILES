# Country Submissions

This folder is the drop-off point for completed country profile content.
If you're a country team handing off a filled-in profile, this is for
you — no git experience required.

## What to submit

Use the starter kit in [`country-submission-template (2).zip`](../country-submission-template%20%282%29.zip)
(in the repo root) if you haven't already. A complete submission is one
folder per country containing:

- `profile_<yourcountry>.md` — the filled-in content file (renamed from
  `profile_TEMPLATE_v2.md`, every `[ ]` placeholder filled in)
- `epi_table_<yourcountry>.xlsx` — the filled-in epi table
- Your DHS StatCompiler export (`STATcompilerExport...xlsx`), kept under
  its original filename
- Any figures/maps referenced in your profile (images)

Put all of it in a new folder here named after your country, e.g.:

```
submissions/
  kenya/
    profile_kenya.md
    epi_table_kenya.xlsx
    STATcompilerExport2026_1234.xlsx
    figures/
      admin-boundaries-map.png
      stratification-map.png
```

## How to submit it (no git needed)

1. Open this repo on GitHub in your browser and navigate into `submissions/`.
2. Click **Add file → Upload files**.
3. Drag in your whole country folder (or all its files).
4. Scroll down, add a short commit message (e.g. "Kenya profile
   submission"), and click **Propose changes**.
5. GitHub will open a pull request for you automatically — that's it.
   You don't need write access to this repo for this to work; if you
   don't have it, GitHub creates a fork behind the scenes and proposes
   the change from there.

## What happens next

The MAP Data Engineering Team reviews the pull request, checks that
every statistic/table/figure has a year and a source, and converts the
content into the live site page under `countries/`. We'll comment on
the PR if anything's missing or unclear before merging.
