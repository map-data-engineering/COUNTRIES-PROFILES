COUNTRIES-PROFILES/
├── R/                          (shared, DET-owned)
│   ├── theme.R                 colours, fonts, white background, caption helper
│   ├── statcompiler.R          (already there)
│   ├── fig_admin_map.R
│   ├── fig_timeline.R
│   ├── fig_health_system.R
│   ├── fig_facility_map.R
│   ├── fig_survey_maps.R
│   ├── fig_climate.R
│   └── fig_vector_maps.R
├── config/                     (settings that don't change per run)
│   ├── display_dhis2.csv
│   ├── display_survey.csv
│   └── palette.csv or tier_names.csv
├── data/
│   └── boundaries/             (shared reference data, such as OCHA boundaries)
├── submissions/<country>/      (researcher inputs only)
├── figures/<country>/          (generated figures, if we save them)
├── countries/                  (generated .qmd pages)
└── step3_generate_qmd.R


This is the workflow for each new country:

Add its row to country_settings.csv, leaving zoom_admin1 blank.
Draw the map and read any console note.
If the capital is hard to see, put that unit’s name in zoom_admin1 and redraw.