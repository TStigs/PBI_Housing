###############################################################################
# Purpose: Master runner for all Power BI housing-data refreshes.
#
# RSTUDIO INSTRUCTIONS
# 1. Choose what to run in the USER SETTINGS section below.
# 2. Open this script in RStudio.
# 3. Click Source in the upper-right corner of the script editor.
#
# The original get_cmhc_data.R file remains unchanged. It is launched in a
# separate R session so its rm(list = ls()) command cannot clear this script.
###############################################################################


###############################################################################
# USER SETTINGS
###############################################################################

# TRUE refreshes the existing CMA datasets; FALSE skips them.
run_cma_data <- TRUE

# TRUE refreshes the new provincial/territorial datasets; FALSE skips them.
run_provincial_data <- TRUE

# Choose provincial datasets. Valid values are "rent", "vacancy", "starts",
# and "completions". Remove any dataset that you do not want to refresh.
provincial_datasets_to_run <- c(
  "rent",
  "vacancy",
  "starts",
  "completions"
)


###############################################################################
# FIND THE PROJECT FOLDER
###############################################################################

# Support RStudio's Source button and optional Rscript terminal execution.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
source_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)

if (length(script_arg) > 0L) {
  script_path <- sub("^--file=", "", script_arg[[1]])
} else if (!is.null(source_path) && nzchar(source_path)) {
  script_path <- source_path
} else {
  script_path <- file.path(getwd(), "run_all_data.R")
}

project_root <- normalizePath(dirname(script_path), mustWork = TRUE)


###############################################################################
# INTERPRET RSTUDIO SETTINGS OR OPTIONAL COMMAND-LINE OPTIONS
###############################################################################

# RStudio uses the settings above. If this file is run with Rscript instead,
# command-line options override those settings for backward compatibility.
running_from_command_line <- length(script_arg) > 0L

if (running_from_command_line) {
  requested <- tolower(commandArgs(trailingOnly = TRUE))
  if (length(requested) == 0L || "all" %in% requested) {
    requested <- c("cma", "provincial")
  }
} else {
  requested <- character()

  if (isTRUE(run_cma_data)) {
    requested <- c(requested, "cma")
  }

  if (isTRUE(run_provincial_data)) {
    requested <- c(
      requested,
      "provincial",
      tolower(provincial_datasets_to_run)
    )
  }
}

# Catch spelling mistakes before launching either long-running data pipeline.
valid_options <- c(
  "cma", "provincial", "rent", "vacancy", "starts", "completions"
)
invalid <- setdiff(requested, valid_options)
if (length(invalid) > 0L) {
  stop("Unknown option(s): ", paste(invalid, collapse = ", "))
}

if (length(requested) == 0L) {
  stop("Nothing is selected. Set run_cma_data and/or run_provincial_data to TRUE.")
}


###############################################################################
# FUNCTION TO RUN A CHILD SCRIPT SAFELY
###############################################################################

# Each pipeline runs in a separate R session. This isolates the original CMA
# script and lets the master script detect a non-zero failure status.
run_script <- function(script, script_args = character()) {
  status <- system2(
    command = file.path(R.home("bin"), "Rscript"),
    args = c(shQuote(file.path(project_root, script)), script_args)
  )

  if (!identical(status, 0L)) {
    stop(script, " failed with exit status ", status)
  }
}


###############################################################################
# RUN THE EXISTING CMA PIPELINE
###############################################################################

if ("cma" %in% requested) {
  message("Running the existing CMA pipeline...")
  run_script("get_cmhc_data.R")
}


###############################################################################
# RUN THE NEW PROVINCIAL/TERRITORIAL PIPELINE
###############################################################################

if (
  "provincial" %in% requested ||
  any(requested %in% c("rent", "vacancy", "starts", "completions"))
) {
  provincial_args <- intersect(
    requested,
    c("rent", "vacancy", "starts", "completions")
  )

  if (length(provincial_args) == 0L) {
    provincial_args <- "all"
  }

  message("Running the provincial/territorial pipeline...")
  run_script("get_cmhc_provincial_data.R", provincial_args)
}

message("All requested data refreshes completed successfully.")

