###############################################################################
# File: R/cmhc_helpers.R
# Purpose: Reusable, thoroughly commented helper functions for retrieving,
#          cleaning, validating, and saving CMHC housing data.
###############################################################################

suppressPackageStartupMessages({
  library(cmhc)
  library(dplyr)
  library(stringr)
  library(openxlsx)
  library(haven)
})


# =============================================================================
# 1. CMHC API Wrapper with Automatic Retry
# =============================================================================

#' Query CMHC with Automatic Retries
#'
#' CMHC's web servers occasionally drop connections or return error 500 when
#' handling long batches of requests. This helper catches network errors and
#' retries up to `attempts` times with an increasing pause before giving up.
#'
#' @param ... Arguments forwarded directly to cmhc::get_cmhc()
#' @param attempts Number of retry attempts (default = 3)
#' @param wait_seconds Initial wait time in seconds between retries
#' @return A data frame returned by cmhc::get_cmhc()
get_cmhc_with_retry <- function(..., attempts = 3L, wait_seconds = 2) {
  last_error <- NULL
  
  for (attempt in seq_len(attempts)) {
    result <- tryCatch(
      cmhc::get_cmhc(...),
      error = function(err) err
    )
    
    # If successful (result is not an error object), return it immediately
    if (!inherits(result, "error")) {
      return(result)
    }
    
    last_error <- result
    if (attempt < attempts) {
      message("  [Retry ", attempt, "/", attempts, "] Server busy, waiting ",
              wait_seconds * attempt, " seconds...")
      Sys.sleep(wait_seconds * attempt)
    }
  }
  
  # If all attempts failed, throw a readable error explaining what happened
  warning("CMHC request failed after ", attempts, " attempts: ",
          conditionMessage(last_error), call. = FALSE)
  return(NULL)
}


# =============================================================================
# 2. Fetch Rental Market Survey Data (RMS: Rent & Vacancy Rate)
# =============================================================================

#' Fetch CMHC Rental Market Survey Data
#'
#' CMHC conducts the Rental Market Survey (RMS) annually in October.
#' This function queries Average Rent or Vacancy Rate across all target
#' geographies and the three standard dwelling structures.
#'
#' @param geo_codes Character vector of geography IDs (CMAs or Provinces)
#' @param geo_map Named vector translating IDs to clean English names
#' @param series_name "Average Rent" or "Vacancy Rate"
#' @param geo_level "cma" or "province" (determines output column schema)
#' @return A cleaned data frame sorted chronologically and geographically
fetch_rms <- function(geo_codes, geo_map, series_name = c("Average Rent", "Vacancy Rate"),
                      geo_level = c("cma", "province")) {
  
  series_name <- match.arg(series_name)
  geo_level   <- match.arg(geo_level)
  
  # Determine the metric column name in the output table
  value_col_name <- if (series_name == "Average Rent") "avg_rent" else "vacancy_rate"
  
  # The 3 dwelling classifications reported by CMHC RMS
  # "Row / Apartment" corresponds to the combined total
  dwelling_types_to_get <- c("Apartment", "Row", "Row / Apartment")
  master_list <- list()
  
  for (geo in geo_codes) {
    geo_name <- unname(geo_map[as.character(geo)])
    if (is.na(geo_name)) geo_name <- as.character(geo)
    
    for (dtype in dwelling_types_to_get) {
      message("Fetching RMS [", series_name, "] for: ", geo_name, " (", dtype, ")...")
      
      raw <- get_cmhc_with_retry(
        survey    = "Rms",
        series    = series_name,
        dimension = "Bedroom Type",
        breakdown = "Historical Time Periods",
        geo_uid   = as.character(geo),
        filters   = list(dwelling_type_desc_en = dtype)
      )
      
      # Skip if CMHC returned no rows (e.g., Nunavut)
      if (is.null(raw) || !is.data.frame(raw) || nrow(raw) == 0L) {
        next
      }
      
      # Clean dwelling label: "Row / Apartment" -> "total", lowercase the rest
      clean_dwelling <- if (dtype == "Row / Apartment") "total" else tolower(dtype)
      
      # Standardize row contents
      cleaned <- raw |>
        dplyr::mutate(
          geo_id   = as.character(geo),
          geography_name = geo_name,
          date_raw = as.character(DateString),
          date_obj = as.Date(Date),
          year_num = as.integer(format(Date, "%Y")),
          dwelling = clean_dwelling,
          bedroom  = stringr::str_trim(stringr::str_to_lower(as.character(`Bedroom Type`))),
          quality  = if ("Quality" %in% names(raw)) as.character(Quality) else NA_character_,
          measure_value = as.numeric(Value)
        )
      
      master_list[[paste(geo, dtype, sep = "_")]] <- cleaned
    }
  }
  
  if (length(master_list) == 0L) {
    warning("No RMS data was returned for series: ", series_name)
    return(data.frame())
  }
  
  combined <- dplyr::bind_rows(master_list)
  
  # Format columns to match existing Power BI expectations:
  if (geo_level == "cma") {
    result <- combined |>
      dplyr::arrange(
        geography_name,
        year_num,
        factor(dwelling, levels = c("apartment", "row", "total")),
        factor(bedroom, levels = c("1 bedroom", "2 bedroom", "3 bedroom +", "studio", "total"))
      ) |>
      dplyr::transmute(
        year      = year_num,
        date      = date_raw,         # e.g., "1990 October"
        geography = geography_name,
        dwelling  = dwelling,
        bedroom   = bedroom,
        !!value_col_name := measure_value
      )
  } else {
    # Provincial schema includes province_code and quality flags
    result <- combined |>
      dplyr::arrange(
        geo_id,
        date_obj,
        factor(dwelling, levels = c("apartment", "row", "total")),
        factor(bedroom, levels = c("1 bedroom", "2 bedroom", "3 bedroom +", "studio", "total"))
      ) |>
      dplyr::transmute(
        province_code = geo_id,
        province      = geography_name,
        date          = date_obj,     # e.g., 1990-10-01
        year          = year_num,
        dwelling      = dwelling,
        bedroom       = bedroom,
        quality       = quality,
        !!value_col_name := measure_value
      )
  }
  
  return(result)
}


# =============================================================================
# 3. Fetch Starts & Completions Survey Data (Scss: Starts & Completions)
# =============================================================================

#' Fetch CMHC Starts and Completions Survey Data
#'
#' CMHC publishes construction activity at Monthly, Quarterly, and Annual
#' frequencies. This function queries CMHC directly for the requested frequency
#' and standardizes market tenures and physical building structures.
#'
#' @param geo_codes Character vector of geography IDs (CMAs or Provinces)
#' @param geo_map Named vector translating IDs to clean English names
#' @param series_name "Starts" or "Completions"
#' @param frequency "Monthly", "Quarterly", or "Annual"
#' @param geo_level "cma" or "province"
#' @return A cleaned data frame sorted chronologically and geographically
fetch_scss <- function(geo_codes, geo_map, series_name = c("Starts", "Completions"),
                       frequency = c("Monthly", "Quarterly", "Annual"),
                       geo_level = c("cma", "province")) {
  
  series_name <- match.arg(series_name)
  frequency   <- match.arg(frequency)
  geo_level   <- match.arg(geo_level)
  
  # The 5 housing tenure markets tracked by CMHC Scss
  market_api_filters <- c("All", "Condo", "Co-op", "Homeowner", "Rental")
  master_list <- list()
  
  for (geo in geo_codes) {
    geo_name <- unname(geo_map[as.character(geo)])
    if (is.na(geo_name)) geo_name <- as.character(geo)
    
    message("Fetching [", frequency, " ", series_name, "] for: ", geo_name, "...")
    
    for (mtype in market_api_filters) {
      raw <- get_cmhc_with_retry(
        survey    = "Scss",
        series    = series_name,
        dimension = "Dwelling Type",
        breakdown = "Historical Time Periods",
        geo_uid   = as.character(geo),
        frequency = frequency, # <-- Tells CMHC which frequency table to return
        filters   = list(`dimension-18` = mtype)
      )
      
      if (is.null(raw) || !is.data.frame(raw) || nrow(raw) == 0L) {
        next
      }
      
      # Clean market tenure string
      clean_market <- dplyr::case_when(
        mtype == "Homeowner" ~ "homeowner",
        mtype == "Condo"     ~ "condo",
        mtype == "Co-op"     ~ "co-op",
        TRUE                 ~ stringr::str_to_lower(mtype)
      )
      
      # Clean building dwelling structure string
      clean_dwelling <- dplyr::case_when(
        as.character(raw$`Dwelling Type`) %in% c("Single", "Single-detached") ~ "single",
        as.character(raw$`Dwelling Type`) == "All" ~ "all",
        TRUE ~ stringr::str_to_lower(as.character(raw$`Dwelling Type`))
      )
      
      # Parse dates according to frequency
      year_extracted <- as.integer(format(raw$Date, "%Y"))
      date_extracted <- as.Date(raw$Date)
      
      # For quarterly, CMHC gives DateString like "1990/Q1" or "2024/Q2"
      quarter_extracted <- if (frequency == "Quarterly") {
        stringr::str_extract(raw$DateString, "Q[1-4]")
      } else {
        NA_character_
      }
      
      period_label <- dplyr::case_when(
        frequency == "Monthly"   ~ as.character(format(raw$Date, "%Y-%m-%d")),
        frequency == "Quarterly" ~ paste(year_extracted, quarter_extracted),
        frequency == "Annual"    ~ as.character(year_extracted)
      )
      
      cleaned <- raw |>
        dplyr::mutate(
          geo_id          = as.character(geo),
          geography_name  = geo_name,
          date            = date_extracted,
          year            = year_extracted,
          quarter         = quarter_extracted,
          period          = period_label,
          market          = clean_market,
          dwelling        = clean_dwelling,
          units           = as.numeric(Value)
        )
      
      master_list[[paste(geo, mtype, sep = "_")]] <- cleaned
    }
  }
  
  if (length(master_list) == 0L) {
    warning("No Scss data was returned for: ", frequency, " ", series_name)
    return(data.frame())
  }
  
  combined <- dplyr::bind_rows(master_list)
  
  # Format output columns to match existing Power BI expectations:
  if (geo_level == "cma") {
    if (frequency == "Monthly") {
      # In the existing CMA monthly file, yearly_units is included as a rolling annual sum
      result <- combined |>
        dplyr::group_by(geography_name, year, market, dwelling) |>
        dplyr::mutate(yearly_units = sum(units, na.rm = TRUE)) |>
        dplyr::ungroup() |>
        dplyr::arrange(
          geography_name, year, period,
          factor(market, levels = c("all", "condo", "co-op", "homeowner", "rental")),
          factor(dwelling, levels = c("all", "apartment", "row", "semi-detached", "single"))
        ) |>
        dplyr::transmute(
          geography     = geography_name,
          year          = year,
          period        = period,
          market        = market,
          dwelling      = dwelling,
          monthly_units = units,
          yearly_units  = yearly_units
        )
    } else if (frequency == "Quarterly") {
      # CMA Quarterly table (NEW)
      result <- combined |>
        dplyr::arrange(
          geography_name, year, quarter,
          factor(market, levels = c("all", "condo", "co-op", "homeowner", "rental")),
          factor(dwelling, levels = c("all", "apartment", "row", "semi-detached", "single"))
        ) |>
        dplyr::transmute(
          geography       = geography_name,
          year            = year,
          quarter         = quarter,
          period          = period,
          market          = market,
          dwelling        = dwelling,
          quarterly_units = units
        )
    } else {
      # CMA Annual table
      result <- combined |>
        dplyr::arrange(
          geography_name, year,
          factor(market, levels = c("all", "condo", "co-op", "homeowner", "rental")),
          factor(dwelling, levels = c("all", "apartment", "row", "semi-detached", "single"))
        ) |>
        dplyr::transmute(
          geography    = geography_name,
          year         = year,
          market       = market,
          dwelling     = dwelling,
          yearly_units = units
        )
    }
  } else {
    # Provincial schema
    if (frequency == "Monthly") {
      result <- combined |>
        dplyr::arrange(geo_id, date, market, dwelling) |>
        dplyr::transmute(
          province_code = geo_id,
          province      = geography_name,
          date          = date,
          year          = year,
          market        = market,
          dwelling      = dwelling,
          monthly_units = units
        )
    } else if (frequency == "Quarterly") {
      # Provincial Quarterly table (NEW)
      result <- combined |>
        dplyr::arrange(geo_id, date, market, dwelling) |>
        dplyr::transmute(
          province_code   = geo_id,
          province        = geography_name,
          date            = date,
          year            = year,
          quarter         = quarter,
          market          = market,
          dwelling        = dwelling,
          quarterly_units = units
        )
    } else {
      # Provincial Annual table
      result <- combined |>
        dplyr::arrange(geo_id, year, market, dwelling) |>
        dplyr::transmute(
          province_code = geo_id,
          province      = geography_name,
          year          = year,
          market        = market,
          dwelling      = dwelling,
          yearly_units  = units
        )
    }
  }
  
  return(result)
}


# =============================================================================
# 4. Optional Local Aggregations (from Monthly to Quarterly/Annual)
# =============================================================================

#' Create Annual Construction Totals from Monthly Data with Completeness Flags
#'
#' Derives annual totals directly from monthly records and checks whether all
#' 12 months are observed so incomplete YTD years are clearly marked.
create_annual_from_monthly <- function(monthly_df, geo_level = c("province", "cma")) {
  geo_level <- match.arg(geo_level)
  
  if (geo_level == "province") {
    monthly_df |>
      dplyr::group_by(province_code, province, year, market, dwelling) |>
      dplyr::summarise(
        yearly_units     = sum(monthly_units, na.rm = TRUE),
        months_observed  = dplyr::n_distinct(date),
        is_complete_year = (months_observed == 12L),
        .groups = "drop"
      ) |>
      dplyr::arrange(province_code, year, market, dwelling)
  } else {
    monthly_df |>
      dplyr::group_by(geography, year, market, dwelling) |>
      dplyr::summarise(
        yearly_units     = sum(monthly_units, na.rm = TRUE),
        months_observed  = dplyr::n_distinct(period),
        is_complete_year = (months_observed == 12L),
        .groups = "drop"
      ) |>
      dplyr::arrange(geography, year, market, dwelling)
  }
}

#' Create Quarterly Construction Totals from Monthly Data with Completeness Flags
#'
#' Derives quarterly totals directly from monthly records and flags whether
#' all 3 months of the quarter were present.
create_quarterly_from_monthly <- function(monthly_df, geo_level = c("province", "cma")) {
  geo_level <- match.arg(geo_level)
  
  if (geo_level == "province") {
    monthly_df |>
      dplyr::mutate(
        month_num = as.integer(format(date, "%m")),
        quarter   = paste0("Q", (month_num - 1L) %/% 3L + 1L)
      ) |>
      dplyr::group_by(province_code, province, year, quarter, market, dwelling) |>
      dplyr::summarise(
        quarterly_units     = sum(monthly_units, na.rm = TRUE),
        months_observed     = dplyr::n_distinct(date),
        is_complete_quarter = (months_observed == 3L),
        .groups = "drop"
      ) |>
      dplyr::arrange(province_code, year, quarter, market, dwelling)
  } else {
    monthly_df |>
      dplyr::mutate(
        date_parsed = as.Date(period),
        month_num   = as.integer(format(date_parsed, "%m")),
        quarter     = paste0("Q", (month_num - 1L) %/% 3L + 1L),
        period_qtr  = paste(year, quarter)
      ) |>
      dplyr::group_by(geography, year, quarter, period_qtr, market, dwelling) |>
      dplyr::summarise(
        quarterly_units     = sum(monthly_units, na.rm = TRUE),
        months_observed     = dplyr::n_distinct(period),
        is_complete_quarter = (months_observed == 3L),
        .groups = "drop"
      ) |>
      dplyr::rename(period = period_qtr) |>
      dplyr::arrange(geography, year, quarter, market, dwelling)
  }
}


# =============================================================================
# 5. Export Functions (Excel & Stata)
# =============================================================================

#' Save Data Frame to Excel
write_dataset_xlsx <- function(df, output_path) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  openxlsx::write.xlsx(df, file = output_path, overwrite = TRUE, asTable = TRUE)
  message("  Saved Excel: ", output_path, " (", nrow(df), " rows)")
}

#' Save Data Frame to Stata (.dta)
write_dataset_dta <- function(df, output_path) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  haven::write_dta(df, path = output_path)
  message("  Saved Stata: ", output_path, " (", nrow(df), " rows)")
}
