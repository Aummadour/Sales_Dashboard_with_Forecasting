default_selection <- function(dataset) {
  start <- parse_dates(dataset$metadata$coverage_start)
  end <- parse_dates(dataset$metadata$coverage_end)
  dates <- seq(month_start(end), by = '-1 month', length.out = 48L)
  list(date_range = c(max(start, tail(dates, 1)), end),
       category_1 = sort(unique(dataset$sales$category_1)),
       category_2 = sort(unique(dataset$sales$category_2)),
       shops = sort(unique(dataset$sales$bikeshop.name)),
       time_unit = 'month', horizon = 12L, forecast_mode = FALSE)
}

validate_selection <- function(selected, sales, coverage_range = NULL) {
  selected$date_range <- validate_date_range(selected$date_range)
  if (!is.null(coverage_range)) {
    limits <- validate_date_range(coverage_range)
    if (selected$date_range[1] < limits[1] || selected$date_range[2] > limits[2]) stop_dashboard('The date range is outside declared data coverage.')
  }
  for (field in c('category_1', 'category_2', 'shops')) {
    if (!length(selected[[field]])) stop_dashboard('Select at least one store, bike type and bike family, then Apply.')
    available <- if (field == 'shops') unique(sales$bikeshop.name) else unique(sales[[field]])
    if (anyNA(selected[[field]]) || any(!selected[[field]] %in% available)) stop_dashboard('A selected filter value is unavailable.')
  }
  if (length(selected$time_unit) != 1L || is.na(selected$time_unit) || !selected$time_unit %in% c('day', 'week', 'month', 'quarter', 'year')) stop_dashboard('Choose a valid time unit.')
  selected$horizon <- whole_number(selected$horizon, 1, 24, 'Forecast horizon (months)')
  if (!is.logical(selected$forecast_mode) || length(selected$forecast_mode) != 1L || is.na(selected$forecast_mode)) stop_dashboard('Invalid forecast setting.')
  selected
}

filter_sales <- function(sales, selected, dates = selected$date_range) {
  dates <- validate_date_range(dates)
  sales[sales$order.date >= dates[1] & sales$order.date <= dates[2] &
    sales$category_1 %in% selected$category_1 & sales$category_2 %in% selected$category_2 &
    sales$bikeshop.name %in% selected$shops, , drop = FALSE]
}

sales_kpis <- function(sales) {
  mountain <- sum(sales$quantity[sales$category_1 == 'Mountain'])
  road <- sum(sales$quantity[sales$category_1 == 'Road'])
  list(orders = length(unique(sales$order.id)), bikes = sum(sales$quantity),
       revenue = sum(sales$extended_price), ratio = if (road == 0) NA_real_ else mountain / road,
       ratio_note = if (!nrow(sales)) 'No bikes sold' else if (road == 0) 'No Road bikes sold' else 'Mountain bikes per Road bike')
}

monthly_sales <- function(sales, coverage, date_range) {
  dates <- validate_date_range(date_range)
  first <- if (dates[1] == month_start(dates[1])) dates[1] else month_after(dates[1])
  last <- if (dates[2] == month_end(dates[2])) month_start(dates[2]) else month_start(dates[2]) - 1
  if (first > last) stop_dashboard('Select at least one complete calendar month for forecasting.')
  months <- seq(first, month_start(last), by = 'month')
  coverage_dates <- parse_dates(coverage$month)
  if (anyDuplicated(coverage_dates)) stop_dashboard('Duplicate monthly coverage.')
  position <- match(months, coverage_dates)
  if (anyNA(position)) stop_dashboard('Monthly coverage is missing. Unknown months cannot be treated as zero sales.')
  if (anyNA(coverage$is_complete[position]) || any(!coverage$is_complete[position])) stop_dashboard('Forecasting requires complete monthly coverage.')
  values <- numeric(length(months))
  within <- sales[sales$order.date >= first & sales$order.date <= month_end(tail(months, 1)), , drop = FALSE]
  if (nrow(within)) {
    totals <- tapply(within$extended_price, format(within$order.date, '%Y-%m-01'), sum)
    found <- match(format(months, '%Y-%m-%d'), names(totals))
    values[!is.na(found)] <- as.numeric(totals[found[!is.na(found)]])
  }
  data.frame(date = months, total_sales = values)
}

aggregate_sales <- function(sales, time_unit = 'month') {
  if (!nrow(sales)) return(data.frame(date = as.Date(character()), total_sales = numeric()))
  dates <- sales$order.date
  bucket <- switch(time_unit,
    day = dates,
    week = dates - (as.integer(format(dates, '%u')) - 1L),
    month = month_start(dates),
    quarter = as.Date(sprintf('%s-%02d-01', format(dates, '%Y'), ((as.integer(format(dates, '%m')) - 1L) %/% 3L) * 3L + 1L)),
    year = as.Date(paste0(format(dates, '%Y'), '-01-01')),
    stop_dashboard('Choose a valid time unit.'))
  totals <- stats::aggregate(sales$extended_price, list(date = bucket), sum)
  names(totals)[2] <- 'total_sales'
  totals[order(totals$date), , drop = FALSE]
}
