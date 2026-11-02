# Power BI housing data pipeline

## Existing CMA pipeline

`get_cmhc_data.R` is the original CMA pipeline and has not been modified.

## Provincial and territorial CMHC pipeline

### Run from RStudio

1. Open `get_cmhc_provincial_data.R` in RStudio.
2. Find the `USER SETTINGS` section near the top.
3. Set `datasets_to_run` to the datasets you want, for example:

```r
datasets_to_run <- c("rent", "vacancy")
```

4. Click **Source** in the upper-right corner of the script editor.

To run the CMA and provincial pipelines together, open `run_all_data.R`, edit
its settings, and click **Source**:

```r
run_cma_data <- TRUE
run_provincial_data <- TRUE
provincial_datasets_to_run <- c("rent", "vacancy", "starts", "completions")
```

Set `run_cma_data <- FALSE` if you only want the provincial files refreshed.

### Optional terminal use

Run every provincial/territorial dataset:

```sh
Rscript get_cmhc_provincial_data.R
```

Run only selected datasets:

```sh
Rscript get_cmhc_provincial_data.R rent vacancy
Rscript get_cmhc_provincial_data.R starts completions
```

Outputs are written to `PBI_Housing_Data/Provincial/`. The construction
pipeline creates separate monthly and annual files. Annual files contain
`months_observed` and `is_complete_year`; partial current-year totals should
not be compared with completed calendar years without applying that flag.

The pipeline includes all ten provinces and all three territories. Edit
`province_map` in `R/cmhc_provincial_config.R` if a narrower geography list is
needed.

## Master runner

Run both the original CMA pipeline and every provincial dataset:

```sh
Rscript run_all_data.R
```

Run only provincial datasets:

```sh
Rscript run_all_data.R provincial
```

Run selected provincial datasets:

```sh
Rscript run_all_data.R provincial rent vacancy
```

The original CMA script runs in a separate R process. This prevents its
environment-clearing command from affecting the master runner.

## Statistics Canada and Power BI

Choose the connection after identifying the Statistics Canada table Product
ID (PID) and required dimensions:

- For a small set of series or vectors, call the WDS JSON endpoint directly
  from Power Query using `Web.Contents`.
- For most or all of a table, use the WDS full-table CSV download method and
  filter the CSV in Power Query.
- Keep the `Web.Contents` host static and use its `RelativePath` and `Query`
  options when parameters are needed. This is more compatible with scheduled
  refresh in the Power BI service than constructing an entirely dynamic URL.
- Use Anonymous credentials for the public Statistics Canada endpoint.

The final Power Query should be written for the selected table rather than as
a generic query, so column names, scalar factors, status symbols, and filters
can be handled explicitly.
