required <- c('flexdashboard', 'shiny', 'plotly', 'DBI', 'RSQLite', 'dplyr', 'dbplyr', 'maps', 'testthat', 'rmarkdown', 'knitr')
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop(paste('Missing packages:', paste(missing, collapse = ', '), '. Follow the project runtime instructions.'), call. = FALSE)
if (!rmarkdown::pandoc_available()) stop('Pandoc is required. Set RSTUDIO_PANDOC to its directory or install it using the project runtime instructions.', call. = FALSE)
cat(R.version.string, '\n')
for (package in required) cat(package, as.character(utils::packageVersion(package)), '\n')
cat('Pandoc:', as.character(rmarkdown::pandoc_version()), '\n')
