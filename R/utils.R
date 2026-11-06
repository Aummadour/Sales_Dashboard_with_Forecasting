# Shared date and input contracts. All monetary values are synthetic USD.
stop_dashboard <- function(message) stop(message, call. = FALSE)

whole_number <- function(value, minimum, maximum, label) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
      value != floor(value) || value < minimum || value > maximum) {
    stop_dashboard(sprintf('%s must be a whole number from %s to %s.', label, minimum, maximum))
  }
  as.integer(value)
}

parse_dates <- function(value, label = 'date') {
  if (inherits(value, 'Date')) result <- value else {
    result <- as.Date(as.character(value), format = '%Y-%m-%d')
    if (anyNA(result) || any(format(result, '%Y-%m-%d') != as.character(value))) {
      stop_dashboard(sprintf('Invalid %s. Use YYYY-MM-DD.', label))
    }
  }
  if (anyNA(result) || any(!is.finite(as.numeric(result)))) stop_dashboard(sprintf('Invalid %s.', label))
  result
}

month_start <- function(date) as.Date(format(parse_dates(date), '%Y-%m-01'))
month_after <- function(date) seq(month_start(date), by = 'month', length.out = 2L)[2L]
month_end <- function(date) month_after(date) - 1

validate_date_range <- function(dates) {
  dates <- parse_dates(dates, 'date range')
  if (length(dates) != 2L || dates[1] > dates[2]) stop_dashboard('Select a valid ordered date range.')
  dates
}

money <- function(value, digits = 0L) {
  paste0(ifelse(value < 0, '-$', '$'), formatC(abs(value), format = 'f', digits = digits, big.mark = ','))
}
