# Reusable extraction, validation, and export helpers.

get_cmhc_with_retry <- function(..., attempts = 3L, wait_seconds = 2) {
  last_error <- NULL

  for (attempt in seq_len(attempts)) {
    result <- tryCatch(cmhc::get_cmhc(...), error = identity)
    if (!inherits(result, "error")) return(result)

    last_error <- result
    if (attempt < attempts) Sys.sleep(wait_seconds * attempt)
  }

  stop(conditionMessage(last_error), call. = FALSE)
}

validate_unique_key <- function(data, key, dataset_name) {
  duplicate_count <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(key))) |>
    dplyr::filter(.data$n > 1L) |>
    nrow()

  if (duplicate_count > 0L) {
    stop(dataset_name, " contains ", duplicate_count, " duplicate key combinations.")
  }

  invisible(data)
}

write_powerbi_xlsx <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  openxlsx::write.xlsx(data, file = path, overwrite = TRUE, asTable = TRUE)
  message("Wrote ", nrow(data), " rows to ", path)
}

fetch_provincial_rms <- function(province_codes, province_map, series_name,
                                 value_column_name) {
  output <- list()

  for (province_code in province_codes) {
    for (dwelling_type in dwelling_types_rms) {
      message("Fetching ", series_name, ": ", province_map[[province_code]],
              " / ", dwelling_type)

      raw <- get_cmhc_with_retry(
        survey = "Rms",
        series = series_name,
        dimension = "Bedroom Type",
        breakdown = "Historical Time Periods",
        geo_uid = province_code,
        filters = list(dwelling_type_desc_en = dwelling_type)
      )

      if (!is.data.frame(raw) || nrow(raw) == 0L) {
        warning("No tabular data returned for ", series_name, ": ",
                province_map[[province_code]], " / ", dwelling_type,
                call. = FALSE)
        next
      }

      output[[paste(province_code, dwelling_type, sep = "_")]] <- raw |>
        dplyr::transmute(
          province_code = as.character(.data$GeoUID),
          province = unname(province_map[as.character(.data$GeoUID)]),
          date = as.Date(.data$Date),
          year = as.integer(format(.data$Date, "%Y")),
          dwelling = dplyr::if_else(
            dwelling_type == "Row / Apartment",
            "total",
            stringr::str_to_lower(dwelling_type)
          ),
          bedroom = stringr::str_to_lower(stringr::str_trim(as.character(.data$`Bedroom Type`))),
          quality = as.character(.data$Quality),
          !!value_column_name := as.numeric(.data$Value)
        )
    }
  }

  result <- dplyr::bind_rows(output) |>
    dplyr::arrange(.data$province_code, .data$date, .data$dwelling, .data$bedroom)

  validate_unique_key(
    result,
    c("province_code", "date", "dwelling", "bedroom"),
    series_name
  )
  result
}

fetch_provincial_scss <- function(province_codes, province_map, series_name) {
  output <- list()

  for (province_code in province_codes) {
    for (market_type in market_types) {
      message("Fetching ", series_name, ": ", province_map[[province_code]],
              " / ", market_type)

      raw <- get_cmhc_with_retry(
        survey = "Scss",
        series = series_name,
        dimension = "Dwelling Type",
        breakdown = "Historical Time Periods",
        geo_uid = province_code,
        filters = list(`dimension-18` = market_type)
      )

      if (!is.data.frame(raw) || nrow(raw) == 0L) {
        warning("No tabular data returned for ", series_name, ": ",
                province_map[[province_code]], " / ", market_type,
                call. = FALSE)
        next
      }

      output[[paste(province_code, market_type, sep = "_")]] <- raw |>
        dplyr::transmute(
          province_code = as.character(.data$GeoUID),
          province = unname(province_map[as.character(.data$GeoUID)]),
          date = as.Date(.data$Date),
          year = as.integer(format(.data$Date, "%Y")),
          market = dplyr::case_when(
            market_type == "Homeowner" ~ "homeowner",
            market_type == "Condo" ~ "condo",
            market_type == "Co-op" ~ "co-op",
            TRUE ~ stringr::str_to_lower(market_type)
          ),
          dwelling = dplyr::case_when(
            as.character(.data$`Dwelling Type`) %in% c("Single", "Single-detached") ~ "single",
            TRUE ~ stringr::str_to_lower(as.character(.data$`Dwelling Type`))
          ),
          monthly_units = as.numeric(.data$Value)
        )
    }
  }

  result <- dplyr::bind_rows(output) |>
    dplyr::arrange(.data$province_code, .data$date, .data$market, .data$dwelling)

  validate_unique_key(
    result,
    c("province_code", "date", "market", "dwelling"),
    series_name
  )
  result
}

create_annual_construction <- function(monthly_data) {
  monthly_data |>
    dplyr::group_by(
      .data$province_code, .data$province, .data$year,
      .data$market, .data$dwelling
    ) |>
    dplyr::summarise(
      yearly_units = sum(.data$monthly_units, na.rm = TRUE),
      months_observed = dplyr::n_distinct(.data$date),
      is_complete_year = .data$months_observed == 12L,
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$province_code, .data$year, .data$market, .data$dwelling)
}
