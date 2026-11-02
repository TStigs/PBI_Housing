###############################################################################
# File: get_cmhc_provincial_data.R
# Purpose: Refresh CMHC housing data for 10 Provinces + 3 Territories.
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

prov_dir <- file.path(project_root, "PBI_Housing_Data", "Provincial")

# Load configuration and unified helpers
source(file.path(project_root, "R", "cmhc_config.R"))
source(file.path(project_root, "R", "cmhc_helpers.R"))


# =============================================================================
# RUN PROVINCIAL DATA REFRESH
# =============================================================================

message("\n=======================================================")
message(">>> REFRESHING PROVINCIAL HOUSING DATA (10 Provs + 3 Terrs) <<<")
message("=======================================================")

# --- 1. Average Rent ($) ---
if ("rent" %in% datasets_to_run) {
  message("\n--- Fetching Provincial Average Rent ---")
  prov_rent <- fetch_rms(province_codes, province_map, series_name = "Average Rent", geo_level = "province")
  write_dataset_xlsx(prov_rent, file.path(prov_dir, "avg_rent_province_territory.xlsx"))
}

# --- 2. Vacancy Rate (%) ---
if ("vacancy" %in% datasets_to_run) {
  message("\n--- Fetching Provincial Vacancy Rate ---")
  prov_vacancy <- fetch_rms(province_codes, province_map, series_name = "Vacancy Rate", geo_level = "province")
  write_dataset_xlsx(prov_vacancy, file.path(prov_dir, "vacancy_rate_province_territory.xlsx"))
}

# --- 3. Housing Starts ---
if ("starts" %in% datasets_to_run) {
  message("\n--- Fetching Provincial Housing Starts ---")
  monthly_starts_prov <- NULL
  
  for (freq in frequencies_to_run) {
    freq_cap <- stringr::str_to_title(freq)
    prov_starts <- fetch_scss(province_codes, province_map, series_name = "Starts",
                              frequency = freq_cap, geo_level = "province")
    
    if (freq == "monthly") {
      monthly_starts_prov <- prov_starts
      write_dataset_xlsx(prov_starts, file.path(prov_dir, "housing_starts_monthly_province_territory.xlsx"))
    } else if (freq == "quarterly") {
      write_dataset_xlsx(prov_starts, file.path(prov_dir, "housing_starts_quarterly_province_territory.xlsx"))
    } else if (freq == "annual") {
      if (!is.null(monthly_starts_prov)) {
        prov_starts <- create_annual_from_monthly(monthly_starts_prov, geo_level = "province")
      }
      write_dataset_xlsx(prov_starts, file.path(prov_dir, "housing_starts_annual_province_territory.xlsx"))
    }
  }
}

# --- 4. Housing Completions ---
if ("completions" %in% datasets_to_run) {
  message("\n--- Fetching Provincial Housing Completions ---")
  monthly_comp_prov <- NULL
  
  for (freq in frequencies_to_run) {
    freq_cap <- stringr::str_to_title(freq)
    prov_comp <- fetch_scss(province_codes, province_map, series_name = "Completions",
                            frequency = freq_cap, geo_level = "province")
    
    if (freq == "monthly") {
      monthly_comp_prov <- prov_comp
      write_dataset_xlsx(prov_comp, file.path(prov_dir, "housing_completions_monthly_province_territory.xlsx"))
    } else if (freq == "quarterly") {
      write_dataset_xlsx(prov_comp, file.path(prov_dir, "housing_completions_quarterly_province_territory.xlsx"))
    } else if (freq == "annual") {
      if (!is.null(monthly_comp_prov)) {
        prov_comp <- create_annual_from_monthly(monthly_comp_prov, geo_level = "province")
      }
      write_dataset_xlsx(prov_comp, file.path(prov_dir, "housing_completions_annual_province_territory.xlsx"))
    }
  }
}

message("\n>>> Provincial Refresh Complete! <<<")
