# Country Submissions

This folder is the drop-off point for completed country profile content.
If you're a country team handing off a filled-in profile, this is for
you — no git experience required, just a GitHub account.

**Before you start:** ask the MAP Data Engineering Team to add you as a
collaborator on this repo (they just need your GitHub username or the
email tied to your account). You'll get an email invite from GitHub —
accept it, then follow the steps below.

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

1. Accept the collaborator invite from GitHub (check your email, or
   look under github.com's notifications bell).
2. Open this repo in your browser and navigate into `submissions/`.
3. Click **Add file → Upload files**.
4. Drag in your whole country folder (or all its files).
5. Scroll down — you'll see an option to **"Create a new branch for
   this commit and start a pull request."** Choose that (it should be
   selected by default), give the branch/PR a short name (e.g.
   "kenya-submission"), and click **Propose changes**.
6. GitHub opens a pull request for you — that's it, you're done.

## What happens next

The MAP Data Engineering Team reviews the pull request, checks that
every statistic/table/figure has a year and a source, and converts the
content into the live site page under `countries/`. We'll comment on
the PR if anything's missing or unclear before merging.
