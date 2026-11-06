# Keep the original helper entry point used by the course dashboard.
# This project now separates data, fixed monthly forecasting and view helpers.
for (file in c('utils.R', 'data.R', 'analysis.R', 'comparison.R', 'forecast.R', 'filters.R', 'plots.R', 'selection_images.R')) {
  source(file.path('R', file), local = FALSE)
}
