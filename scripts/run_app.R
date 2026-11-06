source('scripts/check_runtime.R')
port <- suppressWarnings(as.integer(Sys.getenv('DASHBOARD_PORT', '7431')))
if (length(port) != 1L || is.na(port) || port < 1024L || port > 65535L) stop('DASHBOARD_PORT must be from1024 to65535.', call. = FALSE)
if (!file.exists('bikes_database.db')) stop('Synthetic data is missing. Run Rscript --vanilla scripts/generate_data.R first.', call. = FALSE)
rmarkdown::run('sales_dashboard_with_forecasting_app.Rmd', dir = getwd(), auto_reload = FALSE,
              shiny_args = list(host = '127.0.0.1', port = port, launch.browser = FALSE))
