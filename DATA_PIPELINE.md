# Power BI Housing Data Pipeline

This repository automates the retrieval, standardization, and export of housing market data from the **Canada Mortgage and Housing Corporation (CMHC)** for Power BI dashboards.

---

## Architecture Overview

The pipeline supports both **CMA level** (41 major Census Metropolitan Areas + Canada) and **Provincial level** (10 Provinces + 3 Territories), across all published frequencies:

```
PBI_Housing/
├── run_all_data.R             # Master runner with simple USER SETTINGS
├── R/
│   ├── cmhc_config.R          # Target CMAs, provinces, and survey filters
│   └── cmhc_helpers.R         # Core functions (fetch_rms, fetch_scss, retries, export)
└── PBI_Housing_Data/          # Outputs: Excel (.xlsx) and Stata (.dta)
    └── Provincial/
```

### Data Sources & Frequencies
1. **Rental Market Survey (RMS)**:
   * **Measures:** Average Rent (`avg_rent`) and Vacancy Rate (`vacancy_rate`).
   * **Frequency:** **Annual** (conducted once per year in October).
2. **Starts & Completions Survey (Scss)**:
   * **Measures:** Housing Starts and Housing Completions.
   * **Frequencies:** **Monthly**, **Quarterly**, and **Annual** (queried directly from CMHC or derived locally).

---

## How to Run a Data Refresh

### Option A: From RStudio (Recommended)
1. Open [`run_all_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/run_all_data.R) in RStudio.
2. Edit the `USER SETTINGS` section at the top:
   ```r
   run_cma_data        <- TRUE    # Refresh Canada + 41 CMAs
   run_provincial_data <- TRUE    # Refresh 10 Provinces + 3 Territories

   datasets_to_run <- c("rent", "vacancy", "starts", "completions")
   frequencies_to_run <- c("monthly", "quarterly", "annual")
   save_stata_files <- TRUE       # Saves .dta alongside .xlsx for CMAs
   ```
3. Click the **Source** button in the upper-right corner of the editor window.

### Option B: From Terminal
Run the entire pipeline:
```sh
Rscript run_all_data.R
```

---

## Output Files Inventory

### CMA / Canada Outputs (`PBI_Housing_Data/`)
* **Average Rent**: `avg_rent_41_CMA.xlsx` / `.dta` *(Annual)*
* **Vacancy Rate**: `vacancy_rate_41_CMA.xlsx` / `.dta` *(Annual)*
* **Housing Starts**:
  * Monthly: `housing_starts_41_CMA.xlsx` / `.dta`
  * Quarterly: `housing_starts_quarterly_41_CMA.xlsx` / `.dta`
  * Annual: `annual_housing_starts_41_CMA.xlsx` / `.dta`
* **Housing Completions**:
  * Monthly: `housing_completions_41_CMA.xlsx` / `.dta`
  * Quarterly: `housing_completions_quarterly_41_CMA.xlsx` / `.dta`
  * Annual: `annual_housing_completions_41_CMA.xlsx` / `.dta`

### Provincial & Territorial Outputs (`PBI_Housing_Data/Provincial/`)
* **Average Rent**: `avg_rent_province_territory.xlsx` *(Annual)*
* **Vacancy Rate**: `vacancy_rate_province_territory.xlsx` *(Annual)*
* **Housing Starts**:
  * Monthly: `housing_starts_monthly_province_territory.xlsx`
  * Quarterly: `housing_starts_quarterly_province_territory.xlsx`
  * Annual: `housing_starts_annual_province_territory.xlsx`
* **Housing Completions**:
  * Monthly: `housing_completions_monthly_province_territory.xlsx`
  * Quarterly: `housing_completions_quarterly_province_territory.xlsx`
  * Annual: `housing_completions_annual_province_territory.xlsx`
* **Audit Log**: `data_refresh_log.xlsx` *(Logs timestamps, row counts, and date coverage)*

---

## Important Rules for Dashboards & Analysis

1. **Double Counting Warning (Construction Data)**:
   * In Starts and Completions files, `market = "all"` and `dwelling = "all"` represent marginal totals. Do not sum across all rows without filtering by specific market or dwelling types.
2. **Current-Year Incomplete Data**:
   * For the current calendar year, annual construction figures reflect partial year-to-date totals. In the provincial annual files, check the `is_complete_year` column (`TRUE` only when all 12 months are present).
3. **Quarterly Completeness**:
   * When using quarterly series, verify whether the current quarter is completed or in progress before comparing with past full quarters.
