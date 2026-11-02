###############################################################################
# File: R/cmhc_config.R
# Purpose: Shared configuration, geography definitions, and category mappings
#          for both CMA and Provincial CMHC data pipelines.
###############################################################################

# -----------------------------------------------------------------------------
# 1. Target CMAs (Census Metropolitan Areas)
# -----------------------------------------------------------------------------
# We track 41 major metropolitan areas across Canada plus the Canada aggregate (ID "1").
# The names are mapped using CMHC's internal translation dataset (cmhc_cma_translation_data).

suppressPackageStartupMessages(library(cmhc))

# Create a lookup dictionary mapping CMA GeoUID -> English Name
cma_name_map <- cmhc::cmhc_cma_translation_data$NAME_EN
names(cma_name_map) <- cmhc::cmhc_cma_translation_data$CMA_UID

# Manually add Canada as a country-level geography (GeoUID = "1")
cma_name_map["1"] <- "Canada"

# List of target CMAs (41 CMAs + Canada = 42 total geographies)
target_cmas <- c(
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
  "35580",   # Greater Sudbury / Grand Sudbury, Ontario
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
  "35505",   # Ottawa - Gatineau, Ontario / Quebec
  "35529",   # Peterborough, Ontario
  "24421",   # Québec, Quebec
  "48830",   # Red Deer, Alberta
  "47705",   # Regina, Saskatchewan
  "24408",   # Saguenay, Quebec
  "13310",   # Saint John, New Brunswick
  "47725",   # Saskatoon, Saskatchewan
  "24433",   # Sherbrooke, Quebec
  "35539",   # St. Catharines - Niagara, Ontario
  "10001",   # St. John's, Newfoundland and Labrador
  "35595",   # Thunder Bay, Ontario
  "35535",   # Toronto, Ontario
  "24442",   # Trois-Rivières, Quebec
  "59933",   # Vancouver, British Columbia
  "59935",   # Victoria, British Columbia
  "35559",   # Windsor, Ontario
  "46602"    # Winnipeg, Manitoba
)

# -----------------------------------------------------------------------------
# 2. Provinces and Territories
# -----------------------------------------------------------------------------
# Standard 2-digit Statistics Canada province/territory codes
province_map <- c(
  "10" = "Newfoundland and Labrador",
  "11" = "Prince Edward Island",
  "12" = "Nova Scotia",
  "13" = "New Brunswick",
  "24" = "Quebec",
  "35" = "Ontario",
  "46" = "Manitoba",
  "47" = "Saskatchewan",
  "48" = "Alberta",
  "59" = "British Columbia",
  "60" = "Yukon",
  "61" = "Northwest Territories",
  "62" = "Nunavut" # Note: CMHC frequently returns no data rows for Nunavut
)

province_codes <- names(province_map)

# -----------------------------------------------------------------------------
# 3. Survey Category Filters
# -----------------------------------------------------------------------------
# Scss (Starts & Completions Survey) market tenure filters (internal CMHC dimension-18)
market_types <- c("All", "Condo", "Co-op", "Homeowner", "Rental")

# RMS (Rental Market Survey) dwelling type filters
# "Row / Apartment" corresponds to the combined total
dwelling_types_rms <- c("Apartment", "Row", "Row / Apartment")
