# Parse only. This script does not source, load packages or execute the app.
paths <- c(list.files('R', pattern = '\\.[Rr]$', recursive = TRUE, full.names = TRUE),
           list.files('scripts', pattern = '\\.[Rr]$', full.names = TRUE),
           list.files('tests', pattern = '\\.[Rr]$', recursive = TRUE, full.names = TRUE),
           '04_demand_forecast.R')
for (path in paths) parse(file = path)
lines <- readLines('sales_dashboard_with_forecasting_app.Rmd', warn = FALSE)
inside <- FALSE; chunk <- character(); chunks <- 0L
for (line in lines) {
  if (!inside && grepl('^```\\{r([ ,}]|$)', line)) { inside <- TRUE; chunk <- character(); next }
  if (inside && grepl('^```\\s*$', line)) {
    parse(text = chunk); chunks <- chunks + 1L; inside <- FALSE
  } else if (inside) chunk <- c(chunk, line)
}
if (inside) stop('Unclosed R chunk.')
cat(sprintf('Parsed %d R files and %d R Markdown chunks. No code evaluated.\n', length(paths), chunks))
