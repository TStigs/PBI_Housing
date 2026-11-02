# CMHC Data Refresh Walkthrough

**How the R scripts retrieve, transform, validate, and export housing data for Power BI**  
*Author: Tyler Stigall*  
*Last Updated: November 2, 2026 (Refactored unified architecture, quarterly frequency support, and rate-limiting protections)*

---

### Guide Details

| Guide Detail | Value |
| :--- | :--- |
| **Project** | `PBI_Housing` |
| **Primary Runner** | `run_all_data.R` |
| **Data Source** | Canada Mortgage and Housing Corporation (CMHC) via the R `cmhc` package |
| **Pipelines** | Unified CMA/Canada and Province/Territory architecture |
| **Original Date** | August 19, 2026 |
| **Last Updated** | November 2, 2026 |

> **Purpose:** This guide is intended for future dashboard maintainers. It explains what to run, what each script requests from CMHC, where outputs are written, how rate-limiting and server retries are handled, and what must be checked before Power BI is refreshed.

---

### At a Glance

1. **Confirm Prerequisites:** Verify that R and the required packages (`cmhc`, `dplyr`, `stringr`, `openxlsx`, `haven`) are installed.
2. **Configure Settings:** Open `run_all_data.R` and choose which geographies (`run_cma_data`, `run_provincial_data`), datasets (`rent`, `vacancy`, `starts`, `completions`), and frequencies (`monthly`, `quarterly`, `annual`) to refresh.
3. **Run the Master Script:** Click **Source** in RStudio or execute `Rscript run_all_data.R` in the terminal.
4. **Review Outputs:** Review console messages, row counts, and date coverage in `data_refresh_log.xlsx`.
5. **Publish / Refresh Power BI:** Refresh Power BI only after output checks pass. Upload files to SharePoint as required:  
   `https://uvic.sharepoint.com/sites/CPIMO/Shared%20Documents/Forms/AllItems.aspx?id=%2Fsites%2FCPIMO%2FShared%20Documents%2FPBI%5Fdata`

---

### 1. Project Components

The project uses a unified, modular architecture. Shared configuration and helpers handle both CMA and Provincial requests with standardized error handling and retry logic.

| File | Role | What It Controls |
| :--- | :--- | :--- |
| [`run_all_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/run_all_data.R) | Master runner | Top-level execution, user settings (geographies, datasets, frequencies, pacing delay), and run summary log. |
| [`get_cmhc_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/get_cmhc_data.R) | CMA pipeline | Standalone runner for Canada + 41 CMAs (Excel and Stata exports). |
| [`get_cmhc_provincial_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/get_cmhc_provincial_data.R) | Provincial pipeline | Standalone runner for 10 Provinces + 3 Territories (Excel exports). |
| [`R/cmhc_config.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/R/cmhc_config.R) | Configuration | Target CMA lists, province codes, market tenure filters, and dwelling filters. |
| [`R/cmhc_helpers.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/R/cmhc_helpers.R) | Unified helpers | Pacing, automatic retries, rate-limit interception, `fetch_rms`, `fetch_scss`, local rollups, and file exporters. |

#### Output Locations
* `PBI_Housing_Data/` — CMA Excel and Stata files (Monthly, Quarterly, Annual).
* `PBI_Housing_Data/Provincial/` — Provincial and territorial Excel files (Monthly, Quarterly, Annual) and `data_refresh_log.xlsx`.

---

### 2. Prerequisites & Path Handling

The scripts require an active internet connection and the following CRAN packages:
* **`cmhc`**: Direct API interface to CMHC's Housing Market Information Portal (HMIP).
* **`dplyr` & `stringr`**: Data cleaning, reshaping, label standardization, and hierarchical sorting.
* **`openxlsx`**: Excel table generation.
* **`haven`**: Stata `.dta` export support.

Install missing dependencies with:
```r
install.packages(c("cmhc", "dplyr", "stringr", "openxlsx", "haven"))
```

> **Dynamic Path Resolution:** All scripts locate the project root dynamically using `sys.frame(1)$ofile` and `commandArgs()`. You can move or clone the project folder anywhere without needing to edit hardcoded file paths.

---

### 3. How to Run a Refresh

#### Option A — RStudio (Recommended)
1. Open [`run_all_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/run_all_data.R).
2. Edit the `USER SETTINGS` section at the top:
   ```r
   run_cma_data        <- TRUE    # Canada + 41 CMAs
   run_provincial_data <- TRUE    # 10 Provinces + 3 Territories

   datasets_to_run <- c("rent", "vacancy", "starts", "completions")
   frequencies_to_run <- c("monthly", "quarterly", "annual")
   save_stata_files <- TRUE
   pause_seconds <- 0.5           # Proactive delay between requests
   ```
3. Click the **Source** button in the upper-right corner of the script editor.

#### Option B — Command Line (Terminal)
Run the master runner directly:
```sh
Rscript run_all_data.R
```
Or run individual pipelines standalone:
```sh
Rscript get_cmhc_data.R
Rscript get_cmhc_provincial_data.R
```

---

### 4. Rate Limiting, Pacing, and Server Protections

CMHC’s portal uses web application firewalls (F5 BIG-IP / Akamai) that monitor request rates. If bombarded with dozens of back-to-back requests, the server may drop connections or respond with `429 Too Many Requests` or `403 Forbidden`.

The unified helper [`get_cmhc_with_retry()`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/R/cmhc_helpers.R#L30-L93) incorporates three layers of protection:

1. **Proactive Pacing (`pause_seconds = 0.5`)**:
   * Pauses for 0.5 seconds before every HTTP request.
   * Keeps request traffic polite (~2 requests/second), preventing firewall alarms from triggering.
2. **Intelligent Status Code Interception**:
   * The `cmhc` package normally suppresses server errors and issues a `warning("Invalid response, status ...")` while returning `NULL`.
   * `get_cmhc_with_retry()` captures these warnings. If a status `429`, `403`, or `500` is detected, it flags the request as a server error and initiates an exponential backoff.
   * On rate-limiting errors (`429` / `403`), it enforces a cooldown pause (5 to 10 seconds) before retrying (up to 3 attempts).
3. **Handling Missing Observations (`NA`) vs. Server Errors (`NULL`)**:
   * **Missing data points (`NA`):** Suppressed numbers or low sample sizes in specific years/bedrooms return inside a normal data frame with `NA` in the value column. These are valid data responses and **never** trigger retries.
   * **Unsurveyed regions (Nunavut):** Legitimate empty survey tables return `NULL` without server errors and are skipped gracefully without wasting time on retries.

---

### 5. CMA and Canada Pipeline

[`get_cmhc_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/get_cmhc_data.R) retrieves data for **Canada plus 41 named CMAs** (42 total geographic areas).

#### 5.1 Rental Market Survey (Average Rent & Vacancy Rate)
* **Survey:** CMHC RMS
* **Frequency:** **Annual only** (conducted each year in October; represented as `YYYY October`).
* **Dimension:** `Bedroom Type` (`studio`, `1 bedroom`, `2 bedroom`, `3 bedroom +`, `total`).
* **Dwelling Filters:** `Apartment`, `Row`, `Row / Apartment` (relabeled `total`).
* **Output Fields:** `year`, `date`, `geography`, `dwelling`, `bedroom`, and the metric (`avg_rent` or `vacancy_rate`).

#### 5.2 Starts & Completions Survey (Starts & Completions)
* **Survey:** CMHC Scss
* **Frequencies:** **Monthly**, **Quarterly**, and **Annual**.
* **Dimension:** `Dwelling Type` (`all`, `apartment`, `row`, `semi-detached`, `single`).
* **Market Filters:** `All`, `Condo`, `Co-op`, `Homeowner`, `Rental`.
* **Output Tables & Schemas:**
  * **Monthly** (`housing_starts_41_CMA.xlsx` / `.dta`):  
    `geography, year, period, market, dwelling, monthly_units, yearly_units`  
    *(Note: `yearly_units` is repeated on monthly rows for legacy compatibility; never sum across months).*
  * **Quarterly** (`housing_starts_quarterly_41_CMA.xlsx` / `.dta`):  
    `geography, year, quarter, period, market, dwelling, quarterly_units`
  * **Annual** (`annual_housing_starts_41_CMA.xlsx` / `.dta`):  
    `geography, year, market, dwelling, yearly_units`

---

### 6. Provincial and Territorial Pipeline

[`get_cmhc_provincial_data.R`](file:///Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing/get_cmhc_provincial_data.R) retrieves data for **10 Provinces and 3 Territories** (12 jurisdictions currently return data; Nunavut has no records published by CMHC).

#### 6.1 Provincial Rent & Vacancy
* Includes standard Statistics Canada province codes (`10` through `62`) and CMHC reliability ratings (`quality`: Excellent, Very good, Good, Fair).
* **Output Fields:** `province_code, province, date, year, dwelling, bedroom, quality, <measure>`.

#### 6.2 Provincial Starts & Completions
* **Monthly** (`housing_starts_monthly_province_territory.xlsx`):  
  `province_code, province, date, year, market, dwelling, monthly_units`
* **Quarterly** (`housing_starts_quarterly_province_territory.xlsx`):  
  `province_code, province, date, year, quarter, market, dwelling, quarterly_units`
* **Annual** (`housing_starts_annual_province_territory.xlsx`):  
  `province_code, province, year, market, dwelling, yearly_units, months_observed, is_complete_year`  
  *(Note: `is_complete_year` is `TRUE` only when all 12 monthly periods are present. Partial current-year totals are flagged `FALSE`).*

---

### 7. Output Files Inventory & Benchmarks

The following baseline metrics reflect typical row counts and time coverage:

| Dataset | Geographic Level | Frequency | Benchmark Rows | Time Coverage | File Name |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Average Rent** | CMA | Annual | 21,087 | 1990–2025 (Oct) | `avg_rent_41_CMA.xlsx` / `.dta` |
| **Vacancy Rate** | CMA | Annual | 21,087 | 1990–2025 (Oct) | `vacancy_rate_41_CMA.xlsx` / `.dta` |
| **Housing Starts** | CMA | Monthly | 433,950 | 1990-01 to 2026-05 | `housing_starts_41_CMA.xlsx` / `.dta` |
| **Housing Starts** | CMA | Quarterly | ~145,000 | 1990 Q1 to 2026 Q2 | `housing_starts_quarterly_41_CMA.xlsx` / `.dta` |
| **Housing Starts** | CMA | Annual | 36,775 | 1990–2026 (YTD) | `annual_housing_starts_41_CMA.xlsx` / `.dta` |
| **Housing Completions**| CMA | Monthly | 433,950 | 1990-01 to 2026-05 | `housing_completions_41_CMA.xlsx` / `.dta` |
| **Housing Completions**| CMA | Quarterly | ~145,000 | 1990 Q1 to 2026 Q2 | `housing_completions_quarterly_41_CMA.xlsx` / `.dta` |
| **Housing Completions**| CMA | Annual | 36,775 | 1990–2026 (YTD) | `annual_housing_completions_41_CMA.xlsx` / `.dta` |
| **Average Rent** | Provincial | Annual | 5,923 | 1990–2025 (Oct) | `avg_rent_province_territory.xlsx` |
| **Vacancy Rate** | Provincial | Annual | 5,923 | 1990–2025 (Oct) | `vacancy_rate_province_territory.xlsx` |
| **Housing Starts** | Provincial | Monthly | 116,800 | 1990-01 to 2026-06 | `housing_starts_monthly_province_territory.xlsx` |
| **Housing Starts** | Provincial | Quarterly | ~39,000 | 1990 Q1 to 2026 Q2 | `housing_starts_quarterly_province_territory.xlsx` |
| **Housing Starts** | Provincial | Annual | 11,100 | 1990–2026 (YTD) | `housing_starts_annual_province_territory.xlsx` |
| **Housing Completions**| Provincial | Monthly | 116,800 | 1990-01 to 2026-06 | `housing_completions_monthly_province_territory.xlsx` |
| **Housing Completions**| Provincial | Quarterly | ~39,000 | 1990 Q1 to 2026 Q2 | `housing_completions_quarterly_province_territory.xlsx` |
| **Housing Completions**| Provincial | Annual | 11,100 | 1990–2026 (YTD) | `housing_completions_annual_province_territory.xlsx` |

---

### 8. Required Post-Refresh Checks

Before updating Power BI or transferring files to SharePoint:
1. **Check the Refresh Log:** Open `PBI_Housing_Data/Provincial/data_refresh_log.xlsx` to confirm row counts, coverage dates, and execution timestamps.
2. **Review Warnings:** Check that no critical CMHC error 500 or 429 warnings persisted through all three retry attempts.
3. **Verify Geography Counts:** Confirm that CMA datasets contain 42 distinct geographies and provincial datasets contain 12 jurisdictions.
4. **Spot Check Power BI:**
   * Verify that visuals do not accidentally sum the `"all"` category with its subcomponents (e.g. summing `market = "all"` with `rental` and `condo`).
   * For annual construction figures, filter out incomplete current-year observations (`is_complete_year == FALSE`) when comparing calendar year totals.

---

### 9. Maintenance Status & Priorities

* ✅ **Priority 1 (Hardcoded Paths):** Resolved. All scripts use dynamic project path discovery.
* ✅ **Priority 2 (CMA Error Handling & Retries):** Resolved. CMA requests now share the retry and backoff engine.
* ✅ **Priority 3 (Quarterly Time Series):** Resolved. Quarterly starts and completions are now standard outputs.
* ✅ **Priority 4 (Rate Limiting & Throttling):** Resolved. Added 0.5s proactive delay and status 429/403 backoff logic.
* 🟡 **Priority 5 (Nunavut Coverage):** Monitor future CMHC releases to see if Nunavut data becomes available.

---

### 10. Troubleshooting

#### Rate Limiting (Status 429 or 403 Forbidden)
* If CMHC blocks your IP, wait **15 to 30 minutes** for the temporary block to clear.
* Increase `pause_seconds` from `0.5` to `1.0` in the script's `USER SETTINGS`.
* Avoid running multiple full pipeline refreshes concurrently.

#### Excel File Permission Error ("Permission denied" on export)
* Close the target workbook in Microsoft Excel before running the script. Excel locks open `.xlsx` files on macOS/Windows, preventing R from overwriting them.

#### CMHC Source Acknowledgement
When redistributing or publishing CMHC data, retain the required statutory notice:
> *Adapted from Canada Mortgage and Housing Corporation, Housing Market Information Portal. This does not constitute an endorsement by Canada Mortgage and Housing Corporation of this product.*
