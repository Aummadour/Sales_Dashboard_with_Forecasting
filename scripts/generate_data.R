source('R/utils.R')
source('R/data.R')
args <- commandArgs(trailingOnly = TRUE)
output <- 'bikes_database.db'; overwrite <- FALSE; config <- synthetic_config(); index <- 1L
while (index <= length(args)) {
  argument <- args[index]
  if (argument == '--overwrite') overwrite <- TRUE
  else if (argument %in% c('--output', '--seed') && index < length(args)) {
    index <- index + 1L
    if (argument == '--output') output <- args[index]
    else config$seed <- suppressWarnings(as.numeric(args[index]))
  } else stop(paste('Unknown or incomplete argument:', argument), call. = FALSE)
  index <- index + 1L
}
tables <- generate_synthetic_tables(config)
write_synthetic_database(output, tables, overwrite = overwrite)
cat(sprintf('Created synthetic bicycle data: seed %d, %s to %s, %d order lines.\n',
            config$seed, as.character(config$start), as.character(config$end), nrow(tables$orderlines)))
