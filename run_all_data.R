###############################################################################
# File: run_all_data.R
# Purpose: Master runner to refresh CMHC housing data for Power BI dashboards.
#
# HOW TO RUN IN RSTUDIO:
# 1. Edit the USER SETTINGS section below to choose what to download.
# 2. Click the "Source" button in the upper-right corner of this script window.
#
# HOW TO RUN IN TERMINAL (Optional):
#   Rscript run_all_data.R
###############################################################################


# =============================================================================
# USER SETTINGS: Choose What to Refresh
# =============================================================================

# 1. Choose which geographic levels to refresh:
run_cma_data        <- TRUE    # Canada + 41 Census Metropolitan Areas (CMAs)
run_provincial_data <- TRUE    # 10 Provinces + 3 Territories

# 2. Choose which datasets to refresh:
# Options: "rent", "vacancy", "starts", "completions"
# (Remove any dataset from this list that you do NOT want to refresh)
# "rent",
#  "vacancy",
#  "starts",
#  "completions"

datasets_to_run <- c(
  "rent",
  "vacancy",
  "starts"
)

# 3. Choose which frequencies to download for Starts & Completions:
# Options: "monthly", "quarterly", "annual"
# By default, all three frequencies are downloaded directly from CMHC!
# "monthly",
# "quarterly",
# "annual"
frequencies_to_run <- c(
  "monthly",
  "quarterly",
  "annual"
)

# 4. Save Stata (.dta) files for CMA data? (Excel is always saved)
save_stata_files <- FALSE

# 5. Proactive pacing delay (seconds) between requests to prevent CMHC rate-limiting
# (0.5 seconds is polite and prevents triggering CMHC firewall blocks)
pause_seconds <- 0.5


# =============================================================================
# PROJECT SETUP & DEPENDENCIES
# =============================================================================

# Check that required R packages are installed
required_packages <- c("cmhc", "dplyr", "stringr", "openxlsx", "haven")
missing_pkgs <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0L) {
  stop("Please install missing R packages first: ", paste(missing_pkgs, collapse = ", "))
}

suppressPackageStartupMessages({
  library(cmhc)
  library(dplyr)
  library(stringr)
  library(openxlsx)
  library(haven)
})

# Dynamically locate the project root directory
# (Works whether run via RStudio Source button or Rscript terminal)
script_arg  <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)

if (length(script_arg) > 0L) {
  project_root <- normalizePath(dirname(sub("^--file=", "", script_arg[[1]])), mustWork = TRUE)
} else if (!is.null(source_path) && nzchar(source_path)) {
  project_root <- normalizePath(dirname(source_path), mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), mustWork = TRUE)
}

# Output directories
cma_dir  <- file.path(project_root, "PBI_Housing_Data", "CMA")
prov_dir <- file.path(project_root, "PBI_Housing_Data", "Provincial")

# Load configuration and helper functions
source(file.path(project_root, "R", "cmhc_config.R"))
source(file.path(project_root, "R", "cmhc_helpers.R"))

# Keep track of refreshed files for a run summary log
refresh_log <- list()

record_log <- function(dataset_name, geo_level, frequency, df, output_file) {
  date_col <- intersect(c("date", "period", "year"), names(df))
  min_date <- if (length(date_col) > 0) as.character(min(df[[date_col[1]]], na.rm = TRUE)) else NA_character_
  max_date <- if (length(date_col) > 0) as.character(max(df[[date_col[1]]], na.rm = TRUE)) else NA_character_
  
  refresh_log[[length(refresh_log) + 1]] <<- data.frame(
    dataset      = dataset_name,
    geo_level    = geo_level,
    frequency    = frequency,
    refreshed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    rows         = nrow(df),
    earliest     = min_date,
    latest       = max_date,
    file_saved   = basename(output_file),
    stringsAsFactors = FALSE
  )
}


# =============================================================================
# PART 1: CMA & CANADA PIPELINE (41 CMAs + Canada)
# =============================================================================

if (isTRUE(run_cma_data)) {
  message("\n=======================================================")
  message(">>> STARTING CMA PIPELINE (41 CMAs + Canada) <<<")
  message("=======================================================")
  
  # --- 1.1 Average Rent ($) ---
  if ("rent" %in% datasets_to_run) {
    message("\n--- Fetching CMA Average Rent ---")
    cma_rent <- fetch_rms(target_cmas, cma_name_map, series_name = "Average Rent",
                          geo_level = "cma", pause_seconds = pause_seconds)
    
    xlsx_path <- file.path(cma_dir, "avg_rent_41_CMA.xlsx")
    write_dataset_xlsx(cma_rent, xlsx_path)
    if (isTRUE(save_stata_files)) {
      write_dataset_dta(cma_rent, file.path(cma_dir, "avg_rent_41_CMA.dta"))
    }
    record_log("Average Rent", "CMA", "Annual", cma_rent, xlsx_path)
  }
  
  # --- 1.2 Vacancy Rate (%) ---
  if ("vacancy" %in% datasets_to_run) {
    message("\n--- Fetching CMA Vacancy Rate ---")
    cma_vacancy <- fetch_rms(target_cmas, cma_name_map, series_name = "Vacancy Rate",
                             geo_level = "cma", pause_seconds = pause_seconds)
    
    xlsx_path <- file.path(cma_dir, "vacancy_rate_41_CMA.xlsx")
    write_dataset_xlsx(cma_vacancy, xlsx_path)
    if (isTRUE(save_stata_files)) {
      write_dataset_dta(cma_vacancy, file.path(cma_dir, "vacancy_rate_41_CMA.dta"))
    }
    record_log("Vacancy Rate", "CMA", "Annual", cma_vacancy, xlsx_path)
  }
  
  # --- 1.3 Housing Starts ---
  if ("starts" %in% datasets_to_run) {
    message("\n--- Fetching CMA Housing Starts ---")
    
    for (freq in frequencies_to_run) {
      freq_cap <- stringr::str_to_title(freq)
      starts_df <- fetch_scss(target_cmas, cma_name_map, series_name = "Starts",
                              frequency = freq_cap, geo_level = "cma", pause_seconds = pause_seconds)
      
      if (freq == "monthly") {
        # Monthly file
        xlsx_path <- file.path(cma_dir, "housing_starts_41_CMA.xlsx")
        write_dataset_xlsx(starts_df, xlsx_path)
        if (isTRUE(save_stata_files)) {
          write_dataset_dta(starts_df, file.path(cma_dir, "housing_starts_41_CMA.dta"))
        }
        record_log("Housing Starts", "CMA", "Monthly", starts_df, xlsx_path)
        
      } else if (freq == "quarterly") {
        # Quarterly file (NEW)
        xlsx_path <- file.path(cma_dir, "housing_starts_quarterly_41_CMA.xlsx")
        write_dataset_xlsx(starts_df, xlsx_path)
        if (isTRUE(save_stata_files)) {
          write_dataset_dta(starts_df, file.path(cma_dir, "housing_starts_quarterly_41_CMA.dta"))
        }
        record_log("Housing Starts", "CMA", "Quarterly", starts_df, xlsx_path)
        
      } else if (freq == "annual") {
        # Annual file
        xlsx_path <- file.path(cma_dir, "annual_housing_starts_41_CMA.xlsx")
        write_dataset_xlsx(starts_df, xlsx_path)
        if (isTRUE(save_stata_files)) {
          write_dataset_dta(starts_df, file.path(cma_dir, "annual_housing_starts_41_CMA.dta"))
        }
        record_log("Housing Starts", "CMA", "Annual", starts_df, xlsx_path)
      }
    }
  }
  
  # --- 1.4 Housing Completions ---
  if ("completions" %in% datasets_to_run) {
    message("\n--- Fetching CMA Housing Completions ---")
    
    for (freq in frequencies_to_run) {
      freq_cap <- stringr::str_to_title(freq)
      comp_df <- fetch_scss(target_cmas, cma_name_map, series_name = "Completions",
                            frequency = freq_cap, geo_level = "cma", pause_seconds = pause_seconds)
      
      if (freq == "monthly") {
        # Monthly file
        xlsx_path <- file.path(cma_dir, "housing_completions_41_CMA.xlsx")
        write_dataset_xlsx(comp_df, xlsx_path)
        if (isTRUE(save_stata_files)) {
          write_dataset_dta(comp_df, file.path(cma_dir, "housing_completions_41_CMA.dta"))
        }
        record_log("Housing Completions", "CMA", "Monthly", comp_df, xlsx_path)
        
      } else if (freq == "quarterly") {
        # Quarterly file (NEW)
        xlsx_path <- file.path(cma_dir, "housing_completions_quarterly_41_CMA.xlsx")
        write_dataset_xlsx(comp_df, xlsx_path)
        if (isTRUE(save_stata_files)) {
          write_dataset_dta(comp_df, file.path(cma_dir, "housing_completions_quarterly_41_CMA.dta"))
        }
        record_log("Housing Completions", "CMA", "Quarterly", comp_df, xlsx_path)
        
      } else if (freq == "annual") {
        # Annual file
        xlsx_path <- file.path(cma_dir, "annual_housing_completions_41_CMA.xlsx")
        write_dataset_xlsx(comp_df, xlsx_path)
        if (isTRUE(save_stata_files)) {
          write_dataset_dta(comp_df, file.path(cma_dir, "annual_housing_completions_41_CMA.dta"))
        }
        record_log("Housing Completions", "CMA", "Annual", comp_df, xlsx_path)
      }
    }
  }
}


# =============================================================================
# PART 2: PROVINCIAL & TERRITORIAL PIPELINE (10 Provinces + 3 Territories)
# =============================================================================

if (isTRUE(run_provincial_data)) {
  message("\n=======================================================")
  message(">>> STARTING PROVINCIAL PIPELINE (10 Provs + 3 Terrs) <<<")
  message("=======================================================")
  
  # --- 2.1 Average Rent ($) ---
  if ("rent" %in% datasets_to_run) {
    message("\n--- Fetching Provincial Average Rent ---")
    prov_rent <- fetch_rms(province_codes, province_map, series_name = "Average Rent",
                           geo_level = "province", pause_seconds = pause_seconds)
    
    xlsx_path <- file.path(prov_dir, "avg_rent_province_territory.xlsx")
    write_dataset_xlsx(prov_rent, xlsx_path)
    record_log("Average Rent", "Provincial", "Annual", prov_rent, xlsx_path)
  }
  
  # --- 2.2 Vacancy Rate (%) ---
  if ("vacancy" %in% datasets_to_run) {
    message("\n--- Fetching Provincial Vacancy Rate ---")
    prov_vacancy <- fetch_rms(province_codes, province_map, series_name = "Vacancy Rate",
                             geo_level = "province", pause_seconds = pause_seconds)
    
    xlsx_path <- file.path(prov_dir, "vacancy_rate_province_territory.xlsx")
    write_dataset_xlsx(prov_vacancy, xlsx_path)
    record_log("Vacancy Rate", "Provincial", "Annual", prov_vacancy, xlsx_path)
  }
  
  # --- 2.3 Housing Starts ---
  if ("starts" %in% datasets_to_run) {
    message("\n--- Fetching Provincial Housing Starts ---")
    
    # Store monthly if fetched so we can compute completeness flags for annual
    monthly_starts_prov <- NULL
    
    for (freq in frequencies_to_run) {
      freq_cap <- stringr::str_to_title(freq)
      prov_starts <- fetch_scss(province_codes, province_map, series_name = "Starts",
                                frequency = freq_cap, geo_level = "province", pause_seconds = pause_seconds)
      
      if (freq == "monthly") {
        monthly_starts_prov <- prov_starts
        xlsx_path <- file.path(prov_dir, "housing_starts_monthly_province_territory.xlsx")
        write_dataset_xlsx(prov_starts, xlsx_path)
        record_log("Housing Starts", "Provincial", "Monthly", prov_starts, xlsx_path)
        
      } else if (freq == "quarterly") {
        # Quarterly file (NEW)
        xlsx_path <- file.path(prov_dir, "housing_starts_quarterly_province_territory.xlsx")
        write_dataset_xlsx(prov_starts, xlsx_path)
        record_log("Housing Starts", "Provincial", "Quarterly", prov_starts, xlsx_path)
        
      } else if (freq == "annual") {
        # If monthly was also pulled, add months_observed and is_complete_year
        if (!is.null(monthly_starts_prov)) {
          prov_starts <- create_annual_from_monthly(monthly_starts_prov, geo_level = "province")
        }
        xlsx_path <- file.path(prov_dir, "housing_starts_annual_province_territory.xlsx")
        write_dataset_xlsx(prov_starts, xlsx_path)
        record_log("Housing Starts", "Provincial", "Annual", prov_starts, xlsx_path)
      }
    }
  }
  
  # --- 2.4 Housing Completions ---
  if ("completions" %in% datasets_to_run) {
    message("\n--- Fetching Provincial Housing Completions ---")
    
    monthly_comp_prov <- NULL
    
    for (freq in frequencies_to_run) {
      freq_cap <- stringr::str_to_title(freq)
      prov_comp <- fetch_scss(province_codes, province_map, series_name = "Completions",
                              frequency = freq_cap, geo_level = "province", pause_seconds = pause_seconds)
      
      if (freq == "monthly") {
        monthly_comp_prov <- prov_comp
        xlsx_path <- file.path(prov_dir, "housing_completions_monthly_province_territory.xlsx")
        write_dataset_xlsx(prov_comp, xlsx_path)
        record_log("Housing Completions", "Provincial", "Monthly", prov_comp, xlsx_path)
        
      } else if (freq == "quarterly") {
        # Quarterly file (NEW)
        xlsx_path <- file.path(prov_dir, "housing_completions_quarterly_province_territory.xlsx")
        write_dataset_xlsx(prov_comp, xlsx_path)
        record_log("Housing Completions", "Provincial", "Quarterly", prov_comp, xlsx_path)
        
      } else if (freq == "annual") {
        if (!is.null(monthly_comp_prov)) {
          prov_comp <- create_annual_from_monthly(monthly_comp_prov, geo_level = "province")
        }
        xlsx_path <- file.path(prov_dir, "housing_completions_annual_province_territory.xlsx")
        write_dataset_xlsx(prov_comp, xlsx_path)
        record_log("Housing Completions", "Provincial", "Annual", prov_comp, xlsx_path)
      }
    }
  }
}


# =============================================================================
# PART 3: SUMMARY LOG & FINISH
# =============================================================================

if (length(refresh_log) > 0L) {
  summary_df <- dplyr::bind_rows(refresh_log)
  
  # Save refresh log in Provincial directory (matching existing convention)
  log_path <- file.path(prov_dir, "data_refresh_log.xlsx")
  openxlsx::write.xlsx(summary_df, file = log_path, overwrite = TRUE, asTable = TRUE)
  
  message("\n=======================================================")
  message(">>> DATA REFRESH COMPLETE <<<")
  message("=======================================================")
  print(summary_df |> dplyr::select(dataset, geo_level, frequency, rows, latest, file_saved))
} else {
  message("\nNothing was refreshed. Please check USER SETTINGS at top of script.")
}
