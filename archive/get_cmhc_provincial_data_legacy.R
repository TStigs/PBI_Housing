###############################################################################
# Purpose: Download province/territory-level CMHC data for Power BI.
#
# RSTUDIO INSTRUCTIONS
# 1. Choose datasets in the USER SETTINGS section below.
# 2. Open this script in RStudio.
# 3. Click Source in the upper-right corner of the script editor.
#
# The Excel outputs are saved in PBI_Housing_Data/Provincial.
###############################################################################


###############################################################################
# USER SETTINGS
###############################################################################

# Choose which datasets to download when using RStudio's Source button.
# Valid values: "rent", "vacancy", "starts", and "completions".
# Remove a value from this vector when you do not want to refresh that dataset.
datasets_to_run <- c("rent", "vacancy", "starts", "completions")


###############################################################################
# CHECK REQUIRED R PACKAGES
###############################################################################

# Check all dependencies before starting a potentially long download. If a
# package is missing, the script stops with a list of packages to install.
required_packages <- c("cmhc", "dplyr", "stringr", "openxlsx")
missing_packages <- required_packages[!vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)]

if (length(missing_packages) > 0L) {
  stop(
    "Install required R packages first: ",
    paste(missing_packages, collapse = ", ")
  )
}


###############################################################################
# FIND THE PROJECT FOLDER
###############################################################################

# Rscript supplies a --file argument. RStudio's Source button supplies the
# source filename through sys.frame(1)$ofile. The fallback assumes the RStudio
# working directory is the project folder.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)

if (length(script_arg) > 0L) {
  script_path <- sub("^--file=", "", script_arg[[1]])
} else if (!is.null(source_path) && nzchar(source_path)) {
  script_path <- source_path
} else {
  script_path <- file.path(getwd(), "get_cmhc_provincial_data.R")
}

project_root <- normalizePath(dirname(script_path), mustWork = TRUE)


###############################################################################
# LOAD CONFIGURATION AND HELPER FUNCTIONS
###############################################################################

# The configuration file contains province codes and CMHC category lists.
# The helper file contains the API, cleaning, validation, and export functions.
source(file.path(project_root, "R", "cmhc_provincial_config.R"))
source(file.path(project_root, "R", "cmhc_provincial_helpers.R"))


###############################################################################
# CHOOSE OUTPUT FOLDER AND DATASETS
###############################################################################

# Keep provincial outputs separate from the existing CMA Excel files.
output_dir <- file.path(project_root, "PBI_Housing_Data", "Provincial")

# When sourced in RStudio, use datasets_to_run from USER SETTINGS. Command-line
# arguments remain supported as an optional alternative and override it.
running_from_command_line <- length(script_arg) > 0L
requested <- if (running_from_command_line) {
  tolower(commandArgs(trailingOnly = TRUE))
} else {
  tolower(datasets_to_run)
}

# No selection, or "all", means refresh every available provincial dataset.
if (length(requested) == 0L || "all" %in% requested) {
  requested <- c("rent", "vacancy", "starts", "completions")
}

# Stop early if a dataset name is misspelled in USER SETTINGS.
valid_datasets <- c("rent", "vacancy", "starts", "completions")
invalid <- setdiff(requested, valid_datasets)
if (length(invalid) > 0L) {
  stop(
    "Unknown dataset(s): ", paste(invalid, collapse = ", "),
    ". Choose from: ", paste(valid_datasets, collapse = ", ")
  )
}


###############################################################################
# PREPARE THE REFRESH LOG
###############################################################################

# Each completed dataset adds one summary row containing its row count, date
# coverage, missing-value count, and output filename.
run_log <- list()

record_run <- function(dataset, data, output_file) {
  identifier_columns <- c(
    "province_code", "province", "date", "year", "dwelling",
    "bedroom", "quality", "market"
  )
  measure_column <- setdiff(names(data), identifier_columns)[[1]]

  run_log[[dataset]] <<- data.frame(
    dataset = dataset,
    refreshed_at = Sys.time(),
    rows = nrow(data),
    earliest_date = min(data$date, na.rm = TRUE),
    latest_date = max(data$date, na.rm = TRUE),
    missing_measure_values = sum(is.na(data[[measure_column]])),
    output_file = basename(output_file)
  )
}


###############################################################################
# DOWNLOAD AND EXPORT RENTAL MARKET DATA
###############################################################################

# Average rent and vacancy rate have the same CMHC table structure. The shared
# RMS helper downloads all selected provinces, dwelling types, and bedrooms.
if ("rent" %in% requested) {
  rent_data <- fetch_provincial_rms(
    province_codes,
    province_map,
    "Average Rent",
    "avg_rent"
  )
  rent_path <- file.path(output_dir, "avg_rent_province_territory.xlsx")
  write_powerbi_xlsx(rent_data, rent_path)
  record_run("rent", rent_data, rent_path)
}

if ("vacancy" %in% requested) {
  vacancy_data <- fetch_provincial_rms(
    province_codes,
    province_map,
    "Vacancy Rate",
    "vacancy_rate"
  )
  vacancy_path <- file.path(output_dir, "vacancy_rate_province_territory.xlsx")
  write_powerbi_xlsx(vacancy_data, vacancy_path)
  record_run("vacancy", vacancy_data, vacancy_path)
}


###############################################################################
# DOWNLOAD AND EXPORT HOUSING STARTS AND COMPLETIONS
###############################################################################

# CMHC construction observations are downloaded monthly. A separate annual
# table is calculated without repeating annual totals in every monthly row.
# The annual output flags incomplete years, such as the current calendar year.
for (dataset in intersect(c("starts", "completions"), requested)) {
  series_name <- if (dataset == "starts") "Starts" else "Completions"

  monthly_data <- fetch_provincial_scss(
    province_codes,
    province_map,
    series_name
  )
  annual_data <- create_annual_construction(monthly_data)

  monthly_path <- file.path(
    output_dir,
    paste0("housing_", dataset, "_monthly_province_territory.xlsx")
  )
  annual_path <- file.path(
    output_dir,
    paste0("housing_", dataset, "_annual_province_territory.xlsx")
  )

  write_powerbi_xlsx(monthly_data, monthly_path)
  write_powerbi_xlsx(annual_data, annual_path)
  record_run(dataset, monthly_data, monthly_path)
}


###############################################################################
# EXPORT THE REFRESH LOG
###############################################################################

# Write the run summary only after all requested data downloads succeed.
refresh_log <- dplyr::bind_rows(run_log)
write_powerbi_xlsx(
  refresh_log,
  file.path(output_dir, "data_refresh_log.xlsx")
)

message("Provincial/territorial CMHC refresh completed successfully.")

