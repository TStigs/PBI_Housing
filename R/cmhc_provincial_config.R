# Shared configuration for the provincial and territorial CMHC pipeline.

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
  "62" = "Nunavut"
)

province_codes <- names(province_map)
market_types <- c("All", "Condo", "Co-op", "Homeowner", "Rental")
dwelling_types_rms <- c("Apartment", "Row", "Row / Apartment")

