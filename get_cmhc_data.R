###############################################################################
# File: get_cmhc_data.R
# Purpose: Refresh CMHC housing data for 41 CMAs across Canada + Canada aggregate.
#
# HOW TO RUN IN RSTUDIO:
# 1. Edit the USER SETTINGS section below to select datasets.
# 2. Click "Source" in the upper-right corner of this script editor.
###############################################################################

# =============================================================================
# USER SETTINGS
# =============================================================================

# Choose which datasets to refresh:
# Options: "rent", "vacancy", "starts", "completions"
datasets_to_run <- c("rent", "vacancy", "starts", "completions")

# Choose which frequencies to download for Starts & Completions:
# Options: "monthly", "quarterly", "annual"
frequencies_to_run <- c("monthly", "quarterly", "annual")

# Save Stata (.dta) files alongside Excel files?
save_stata_files <- TRUE

# Proactive pacing delay (seconds) between requests to prevent CMHC rate-limiting
pause_seconds <- 0.5


# =============================================================================
# SETUP
# =============================================================================

# Dynamically locate the project directory
script_arg  <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)

if (length(script_arg) > 0L) {
  project_root <- normalizePath(dirname(sub("^--file=", "", script_arg[[1]])), mustWork = TRUE)
} else if (!is.null(source_path) && nzchar(source_path)) {
  project_root <- normalizePath(dirname(source_path), mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), mustWork = TRUE)
}

cma_dir <- file.path(project_root, "PBI_Housing_Data")

# Load configuration and unified helpers
source(file.path(project_root, "R", "cmhc_config.R"))
source(file.path(project_root, "R", "cmhc_helpers.R"))


# =============================================================================
# RUN CMA DATA REFRESH
# =============================================================================

message("\n=======================================================")
message(">>> REFRESHING CMA HOUSING DATA (41 CMAs + Canada) <<<")
message("=======================================================")

# --- 1. Average Rent ($) ---
if ("rent" %in% datasets_to_run) {
  message("\n--- Fetching Average Rent ---")
  cma_rent <- fetch_rms(target_cmas, cma_name_map, series_name = "Average Rent",
                        geo_level = "cma", pause_seconds = pause_seconds)
  
  xlsx_path <- file.path(cma_dir, "avg_rent_41_CMA.xlsx")
  write_dataset_xlsx(cma_rent, xlsx_path)
  if (isTRUE(save_stata_files)) {
    write_dataset_dta(cma_rent, file.path(cma_dir, "avg_rent_41_CMA.dta"))
  }
}

# --- 2. Vacancy Rate (%) ---
if ("vacancy" %in% datasets_to_run) {
  message("\n--- Fetching Vacancy Rate ---")
  cma_vacancy <- fetch_rms(target_cmas, cma_name_map, series_name = "Vacancy Rate",
                           geo_level = "cma", pause_seconds = pause_seconds)
  
  xlsx_path <- file.path(cma_dir, "vacancy_rate_41_CMA.xlsx")
  write_dataset_xlsx(cma_vacancy, xlsx_path)
  if (isTRUE(save_stata_files)) {
    write_dataset_dta(cma_vacancy, file.path(cma_dir, "vacancy_rate_41_CMA.dta"))
  }
}

# --- 3. Housing Starts ---
if ("starts" %in% datasets_to_run) {
  message("\n--- Fetching Housing Starts ---")
  for (freq in frequencies_to_run) {
    freq_cap <- stringr::str_to_title(freq)
    starts_df <- fetch_scss(target_cmas, cma_name_map, series_name = "Starts",
                            frequency = freq_cap, geo_level = "cma", pause_seconds = pause_seconds)
    
    if (freq == "monthly") {
      write_dataset_xlsx(starts_df, file.path(cma_dir, "housing_starts_41_CMA.xlsx"))
      if (isTRUE(save_stata_files)) write_dataset_dta(starts_df, file.path(cma_dir, "housing_starts_41_CMA.dta"))
    } else if (freq == "quarterly") {
      write_dataset_xlsx(starts_df, file.path(cma_dir, "housing_starts_quarterly_41_CMA.xlsx"))
      if (isTRUE(save_stata_files)) write_dataset_dta(starts_df, file.path(cma_dir, "housing_starts_quarterly_41_CMA.dta"))
    } else if (freq == "annual") {
      write_dataset_xlsx(starts_df, file.path(cma_dir, "annual_housing_starts_41_CMA.xlsx"))
      if (isTRUE(save_stata_files)) write_dataset_dta(starts_df, file.path(cma_dir, "annual_housing_starts_41_CMA.dta"))
    }
  }
}

# --- 4. Housing Completions ---
if ("completions" %in% datasets_to_run) {
  message("\n--- Fetching Housing Completions ---")
  for (freq in frequencies_to_run) {
    freq_cap <- stringr::str_to_title(freq)
    comp_df <- fetch_scss(target_cmas, cma_name_map, series_name = "Completions",
                          frequency = freq_cap, geo_level = "cma", pause_seconds = pause_seconds)
    
    if (freq == "monthly") {
      write_dataset_xlsx(comp_df, file.path(cma_dir, "housing_completions_41_CMA.xlsx"))
      if (isTRUE(save_stata_files)) write_dataset_dta(comp_df, file.path(cma_dir, "housing_completions_41_CMA.dta"))
    } else if (freq == "quarterly") {
      write_dataset_xlsx(comp_df, file.path(cma_dir, "housing_completions_quarterly_41_CMA.xlsx"))
      if (isTRUE(save_stata_files)) write_dataset_dta(comp_df, file.path(cma_dir, "housing_completions_quarterly_41_CMA.dta"))
    } else if (freq == "annual") {
      write_dataset_xlsx(comp_df, file.path(cma_dir, "annual_housing_completions_41_CMA.xlsx"))
      if (isTRUE(save_stata_files)) write_dataset_dta(comp_df, file.path(cma_dir, "annual_housing_completions_41_CMA.dta"))
    }
  }
}

message("\n>>> CMA Refresh Complete! <<<")
