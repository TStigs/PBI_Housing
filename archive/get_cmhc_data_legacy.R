###############################################################################
# Author: Tyler Stigall
# Last Updated: 24-08-2026
# Purpose: This script is used to access the CMHC housing data for the 41
#          CMA's accross Canada for the Scss and Rms surveys.
###############################################################################


################################################################################
# Acknowledgment of Source
# Source: Canada Mortgage and Housing Corporation (CMHC), name of product or 
# information, reference date. This information is reproduced and distributed 
# on an “as is” basis with the permission of CMHC.


# Where any Information is contained within a Value-added Product, you shall
# include on such Value-added Product the following notice:
#   Adapted from Canada Mortgage and Housing Corporation, name of product or 
# information, reference date. This does not constitute an endorsement by 
# Canada Mortgage and Housing Corporation of this product, or any other notice 
# approved in advance in writing by CMHC.
###############################################################################

# Clear environment
rm(list = ls())


# Load libraries

# install.packages("cmhc")
# install.packages("openxlsx")
# install.packages("readxl")

library(cmhc)
library(dplyr)
library(purrr)
library(stringr)
library(openxlsx)
library(readxl)
library(haven)


################################################################################
# Set up file path
###############################################################################

# Project root: Set this to where you want to work out of. Output will be 
# relative to this file path

root_path <- "/Users/tylerstigall/Documents/UVic/RA/Justin/PBI_Housing"


# Data directory: This is where the data will be accessed/stored
data_dir <- file.path(root_path, "PBI_Housing_Data")

############################
## Acessing CMAs
############################

# Get a list of all the CMAs in Canada
# Note: These are not all true CMAs, it includes smaller census tracts as well
canada_cmas <- cmhc_cma_translation_data

# Create a named vector: names are the IDs, values are the clean English names
cma_name_map <- cmhc_cma_translation_data$NAME_EN
names(cma_name_map) <- cmhc_cma_translation_data$CMA_UID


# Append Canada to the map manually (Country-level GeoUID)
cma_name_map["1"] <- "Canada"

# Custom helper function to look up a CMA code
find_cma_code <- function(city_search_string) {
  
  results <- cmhc_cma_translation_data %>%
    # Filter for names that contain your search term (ignoring uppercase/lowercase)
    filter(str_detect(str_to_lower(NAME_EN), str_to_lower(city_search_string))) %>%
    # Select and rename columns for clarity
    select(CMA_Code = CMA_UID, CMA_Name = NAME_EN)
  
  if (nrow(results) == 0) {
    message("No Census Metropolitan Areas found matching '", city_search_string, "'")
  } else {
    return(results)
  }
}

find_cma_code("Toronto")
find_cma_code("Vancouver")
find_cma_code("Sherbrooke")
find_cma_code("Canada")


# Target CMAs
target_cma <- c(
  "1",       # Canada
  "59932",   # Abbotsford - Mission, British Columbia
  "35568",   # Barrie, Ontario
  "35522",   # Belleville - Quinte West, Ontario
  "35543",   # Brantford, Ontario
  "48825",   # Calgary, Alberta
  "59930",   # Chilliwack, British Columbia
  "24447",   # Drummondville, Quebec
  "48835",   # Edmonton, Alberta
  "13320",   # Fredericton, New Brunswick
  "35580",   # Greater Sudbury, Ontario
  "35550",   # Guelph, Ontario
  "12205",   # Halifax, Nova Scotia
  "35537",   # Hamilton, Ontario
  "59925",   # Kamloops, British Columbia
  "59915",   # Kelowna, British Columbia
  "35521",   # Kingston, Ontario
  "35541",   # Kitchener - Cambridge - Waterloo, Ontario
  "48810",   # Lethbridge, Alberta
  "35555",   # London, Ontario
  "13305",   # Moncton, New Brunswick
  "24462",   # Montréal, Quebec
  "59938",   # Nanaimo, British Columbia
  "35532",   # Oshawa, Ontario
  "35505",   # Ottawa - Gatineau, Ontario
  "35529",   # Peterborough, Ontario
  "24421",   # Québec, Quebec
  "48830",   # Red Deer, Alberta
  "47705",   # Regina, Saskatchewan
  "24408",   # Saguenay, Quebec
  "13310",   # Saint John, New Brunswick
  "47725",   # Saskatoon, Saskatchewan
  "24433",   # Sherbrooke, Quebec
  "35539",   # St. Catharines - Niagara, Ontario
  "10001",   # St. John's, Newfoundland
  "35595",   # Thunder Bay, Ontario
  "35535",   # Toronto, Ontario
  "24442",   # Trois-Rivières, Quebec
  "59933",   # Vancouver, British Columbia
  "59935",   # Victoria, British Columbia
  "35559",   # Windsor, Ontario
  "46602"    # Winnipeg, Manitoba
)






#' Fetch and Clean Custom CMHC Rental Market Survey (RMS) Metrics
#'
#' @description This function automates the extraction of historical rental market 
#' metrics (e.g., Average Rent, Vacancy Rate, Availability Rate) from the CMHC API across 
#' multiple Census Metropolitan Areas (CMAs). It breaks down data by dwelling type 
#' and bedroom type, handles server crashes gracefully, maps code IDs to geographic 
#' name strings, and names your metric column dynamically.
#'
#' @param target_cmas A character vector of CMHC Census Metropolitan Area UIDs (e.g., \code{c("35535", "59933")}).
#' @param cma_map A named character vector used to translate CMHC GeoUID codes into english city strings (e.g., \code{cma_name_map}).
#' @param series_name A character string matching an explicit CMHC Rental Market Survey series identifier (e.g., \code{"Rent"}, \code{"Vacancy Rate"}).
#' @param value_column_name A character string defining the final name of your data column (e.g., \code{"avg_rent_dollars"} or \code{"vacancy_rate_pct"}).
#'
#' @details 
#' The function maps structural tables natively via a dual nested loop layer:
#' \enumerate{
#'   \item Loops through each specified geographic CMA.
#'   \item Iterates across three explicit target structures: "Apartment", "Row", and "Row / Apartment" (which is reformatted to "total").
#' }
#' It bypasses potential CMHC gateway error 500 crashes via an embedded \code{tryCatch()} framework, warning you of specific network extraction dropped segments while letting the rest of your loop continue running safely.
#'
#' @return A cleaned and structured data frame sorted chronologically and hierarchically by:
#' \itemize{
#'   \item Geography / CMA code
#'   \item Year
#'   \item Dwelling classification layout (\code{apartment}, \code{row}, \code{total})
#'   \item Bedroom layout (\code{studio}, \code{1 bedroom}, \code{2 bedroom}, \code{3 bedroom +}, \code{total})
#' }
#' 
#' @export
#'
#' @examples
#' \dontrun{
#' # Pull average historical rent metrics for your targets
#' rent_table <- fetch_cmhc_metric(
#'   target_cmas = target_cma,
#'   cma_map = cma_name_map,
#'   series_name = "Rent",
#'   value_column_name = "average_rent"
#' )
#' } 
#' 
# Function to fetch any CMHC Rental Market Survey metric
fetch_cmhc_metric <- function(target_cmas, cma_map, series_name, value_column_name) {
  
  dwelling_types_to_get <- c("Apartment", "Row", "Row / Apartment")
  master_list <- list()
  
  for (cma in target_cmas) {
    dwelling_list <- list()
    
    for (dtype in dwelling_types_to_get) {
      message("Fetching ", dtype, " [", series_name, "] data for CMA ", cma, "...")
      
      # Safely handle server code 500 crashes
      raw_data <- tryCatch({
        get_cmhc(
          survey = "Rms", 
          series = series_name, 
          dimension = "Bedroom Type", 
          breakdown = "Historical Time Periods",
          geo_uid = cma,
          filters = list(dwelling_type_desc_en = dtype)
        )
      }, error = function(e) {
        warning("Failed to retrieve ", series_name, " for CMA ", cma, " (", dtype, ")")
        return(NULL)
      })
      
      if (!is.null(raw_data) && nrow(raw_data) > 0) {
        dwelling_list[[dtype]] <- raw_data
      }
    }
    
    # Process and clean the matrix strings if data exists
    if (length(dwelling_list) > 0) {
      master_list[[cma]] <- bind_rows(dwelling_list, .id = "source_dwelling_type") %>%
        mutate(
          date = DateString,
          year = as.numeric(format(Date, "%Y")),
          geography = as.vector(as.character(cma_map[as.character(GeoUID)])),
          
          dwelling = case_when(
            source_dwelling_type == "Row / Apartment" ~ "total",
            TRUE ~ str_to_lower(source_dwelling_type)
          ),
          
          bedroom = str_trim(str_to_lower(`Bedroom Type`)),
          
          # Assign dynamically to whatever column name you request
          !!value_column_name := Value
        )
    }
  }
  
  # Combine into a final master table and apply sorting rules
  final_df <- bind_rows(master_list, .id = "cma_code") %>%
    arrange(
      cma_code,
      year, 
      factor(dwelling, levels = c("apartment", "row", "total")),
      factor(bedroom, levels = c("1 bedroom", "2 bedroom", "3 bedroom +", "studio", "total"))
    ) %>%
    select(year, date, geography, dwelling, bedroom, !!sym(value_column_name))
  
  return(final_df)
}




##############################################################################
# Average Rent ($)
##############################################################################

sorted_average_rent_df <- fetch_cmhc_metric(
  target_cmas = target_cma,
  cma_map = cma_name_map,
  series_name = "Average Rent",
  value_column_name = "avg_rent"
)



# Name the Excel File
output_excel_path_average_rent <- file.path(data_dir, "avg_rent_41_CMA.xlsx")

# Export to Excel
write.xlsx(sorted_average_rent_df, file = output_excel_path_average_rent)


# Name the .dta file
output_dta_path_average_rent <- file.path(data_dir, "avg_rent_41_CMA.dta")

# Export to .dta
write_dta(sorted_average_rent_df, output_dta_path_average_rent)






##############################################################################
# Vacancy Rate (%)
##############################################################################


sorted_vacancy_rate_df <- fetch_cmhc_metric(
  target_cmas = target_cma,
  cma_map = cma_name_map,
  series_name = "Vacancy Rate",
  value_column_name = "vacancy_rate"
)


# Name the Excel file
output_excel_path_vacancy <- file.path(data_dir, "vacancy_rate_41_CMA.xlsx")
# Export to Excel
write.xlsx(sorted_vacancy_rate_df, file = output_excel_path_vacancy)


# Name the .dta file
output_dta_path_vacancy <- file.path(data_dir, "vacancy_rate_41_CMA.dta")
# Export to .dta (Input your file Path)
write_dta(sorted_vacancy_rate_df, output_dta_path_vacancy)






##############################################################################
# Housing Starts
##############################################################################


# Function to extract true cross-tabulated data for CMHC Scss Survey data
fetch_cmhc_true_crossover_pipeline <- function(target_cmas, cma_map, series_name) {
  
  # The 5 internal filter string values recognized by `dimension-18` for dwelling type
  market_api_filters <- c("All", "Condo", "Co-op", "Homeowner", "Rental")
  
  # List to store all CMA level dwelling type by market type
  master_list <- list()
  
  # For each CMA
  for (cma in target_cmas) {
    city_name <- as.character(cma_map[as.character(cma)])
    message(">>> Pulling Complete Matrix Archive for: ", city_name, " (", series_name, ") <<<")
    
    city_combinations <- list()
    
    for (mtype in market_api_filters) {
      combo_label <- paste(cma, mtype, sep = " - ")
      
      # Pull the all dwelling type data by Market type safely using the verified internal filter key
      raw_pull <- tryCatch({
        get_cmhc(
          survey = "Scss", 
          series = series_name, 
          dimension = "Dwelling Type", 
          breakdown = "Historical Time Periods",
          geo_uid = as.character(cma),
          filters = list(
            `dimension-18` = mtype
          )
        )
      }, error = function(e) { NULL })
      
      
      # Verify data exists and the Date column structure is fully present
      if (!is.null(raw_pull) && "Date" %in% names(raw_pull) && nrow(raw_pull) > 0) {
        
        city_combinations[[combo_label]] <- raw_pull %>% 
          mutate(
            geography     = city_name,
            year          = as.numeric(format(Date, "%Y")),
            period        = as.character(format(Date, "%Y-%m-%d")),
            
            # Map the API keys cleanly to match previous data formmating
            market        = case_when(
              mtype == "Homeowner" ~ "homeowner",
              mtype == "Condo"     ~ "condo",
              mtype == "Co-op"     ~ "co-op",
              TRUE                 ~ str_to_lower(mtype)
            ),
            
            # Clean up the physical building shapes to match previous data formatting
            dwelling      = case_when(
              `Dwelling Type` == "Single-detached" ~ "single", # Ensures single detached is captured correctly
              `Dwelling Type` == "Single"          ~ "single", # Catching any mapping variations
              `Dwelling Type` == "All"             ~ "all",
              TRUE                                 ~ str_to_lower(as.character(`Dwelling Type`))
            ),
            
            monthly_units = as.numeric(Value)
          ) %>%
          select(geography, year, period, market, dwelling, monthly_units)
      }
    }
    
    # Process window total calculations per CMA bucket if iterations generated data
    if (length(city_combinations) > 0) {
      master_list[[cma]] <- bind_rows(city_combinations) %>%
        group_by(geography, year, market, dwelling) %>%
        mutate(
          # Window Partition: Annual aggregations for each month
          yearly_units = sum(monthly_units, na.rm = TRUE)
        ) %>%
        ungroup()
    }
  }
  
  # Final table compilation and hierarchical layout sorting
  if (length(master_list) > 0) {
    final_sheet_df <- bind_rows(master_list) %>%
      arrange(
        geography,
        year,
        period,
        # Sorting to arrange by market type first, then dwelling type 
        factor(market,   levels = c("all", "condo", "co-op", "homeowner", "rental")),
        factor(dwelling, levels = c("all", "apartment", "row", "semi-detached", "single"))
      ) %>%
      select(geography, year, period, market, dwelling, monthly_units, yearly_units)
    
    return(final_sheet_df)
  } else {
    stop("Execution finished, but no matrix records matched the configuration.")
  }
}

## End Function to output Scss survey data




##############################################################################
# Housing Starts
##############################################################################

# Extract and format the complete Housing Starts Data Frame
final_starts_excel_df <- fetch_cmhc_true_crossover_pipeline(
  target_cmas = target_cma,
  cma_map = cma_name_map,
  series_name = "Starts"
)


# Name Excel File
output_excel_path_starts <- file.path(data_dir, "housing_starts_41_CMA.xlsx")
# Export to Excel (Input your file path)
write.xlsx(final_starts_excel_df, file = output_excel_path_starts)


# Name .dta file
output_dta_path_starts <- file.path(data_dir, "housing_starts_41_CMA.dta")
# Export to .dta (Input your file path)
write_dta(final_starts_excel_df, output_dta_path_starts)




##############################################################################
# Housing Completions
##############################################################################

final_completions_excel_df <- fetch_cmhc_true_crossover_pipeline(
  target_cmas = target_cma,
  cma_map = cma_name_map,
  series_name = "Completions"
)

# Name Excel file
output_excel_path_completions <- file.path(data_dir, "housing_completions_41_CMA.xlsx")
# Export to Excel (Input your file path)
write.xlsx(final_completions_excel_df, file = output_excel_path_completions)

# Name .dta file
output_dta_path_completions <- file.path(data_dir, "housing_completions_41_CMA.dta")
# Export to .dta (Input your file path)
write_dta(final_completions_excel_df, output_dta_path_completions)




###############################################################################
# Create dataset for only annual observations for housing starts and completions 
###############################################################################

# Create Annual Housing Starts
# Simply use "distinct()" which will remove duplicate rows based on the selected
# columns, keeping only unique combinations of geography, year, market, 
# dwelling, and yearly_units.
annual_starts_df <- final_starts_excel_df %>%
  select(geography, year, market, dwelling, yearly_units) %>%
  distinct()

# Create Annual Housing Completions
annual_completions_df <- final_completions_excel_df %>%
  select(geography, year, market, dwelling, yearly_units) %>%
  distinct()


# Export Annual Starts
output_excel_annual_starts <- file.path(data_dir, "annual_housing_starts_41_CMA.xlsx")
write.xlsx(annual_starts_df, file = output_excel_annual_starts)

output_dta_annual_starts <- file.path(data_dir, "annual_housing_starts_41_CMA.dta")
write_dta(annual_starts_df, output_dta_annual_starts)


# Export Annual Completions
output_excel_annual_completions <- file.path(data_dir, "annual_housing_completions_41_CMA.xlsx")
write.xlsx(annual_completions_df, file = output_excel_annual_completions)

output_dta_annual_completions <- file.path(data_dir, "annual_housing_completions_41_CMA.dta")
write_dta(annual_completions_df, output_dta_annual_completions)

##############################################################################
# END
##############################################################################


