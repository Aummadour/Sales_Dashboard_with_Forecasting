comparison_periods <- function(dates) {
  current <- validate_date_range(dates)
  days <- as.integer(current[2] - current[1]) + 1L
  list(current = current, previous = c(current[1] - days, current[1] - 1), days = days)
}

category_totals <- function(sales) {
  if (!nrow(sales)) return(data.frame(category = character(), quantity = numeric(), revenue = numeric()))
  key <- paste(sales$category_1, sales$category_2, sep = ' / ')
  result <- stats::aggregate(cbind(quantity = sales$quantity, revenue = sales$extended_price),
                             list(category = key), sum)
  result[order(result$category), , drop = FALSE]
}

decompose_revenue <- function(previous, current) {
  before <- category_totals(previous); after <- category_totals(current)
  categories <- sort(union(before$category, after$category))
  pick <- function(data, field) {
    value <- data[[field]][match(categories, data$category)]
    value[is.na(value)] <- 0
    value
  }
  q0 <- pick(before, 'quantity'); q1 <- pick(after, 'quantity')
  r0 <- pick(before, 'revenue'); r1 <- pick(after, 'revenue')
  Q0 <- sum(q0); Q1 <- sum(q1)
  # New categories use their current price; lost categories retain their prior price.
  p0 <- ifelse(q0 > 0, r0 / pmax(q0, 1), ifelse(q1 > 0, r1 / pmax(q1, 1), 0))
  p1 <- ifelse(q1 > 0, r1 / pmax(q1, 1), p0)
  # With no prior sales, use current shares. With no current sales, use prior shares.
  s0 <- if (Q0 > 0) q0 / Q0 else if (Q1 > 0) q1 / Q1 else rep(0, length(categories))
  s1 <- if (Q1 > 0) q1 / Q1 else s0
  volume <- (Q1 - Q0) * s0 * p0
  mix <- Q1 * (s1 - s0) * p0
  price <- Q1 * s1 * (p1 - p0)
  difference <- sum(r1) - sum(r0)
  components <- data.frame(driver = c('Volume', 'Category mix', 'Weighted price'),
                            change = c(sum(volume), sum(mix), sum(price)))
  if (abs(sum(components$change) - difference) > 64 * .Machine$double.eps * max(1, abs(sum(r0)), abs(sum(r1)))) {
    stop_dashboard('Revenue drivers do not reconcile.')
  }
  list(previous_revenue = sum(r0), current_revenue = sum(r1), change = difference,
       previous_quantity = Q0, current_quantity = Q1,
       previous_weighted_price = if (Q0 > 0) sum(r0) / Q0 else NA_real_,
       current_weighted_price = if (Q1 > 0) sum(r1) / Q1 else NA_real_,
       components = components,
       categories = data.frame(category = categories, previous_quantity = q0, current_quantity = q1,
         previous_price = p0, current_price = p1, volume = volume, mix = mix, price = price,
         revenue_change = r1 - r0,
         status = ifelse(q0 == 0 & q1 > 0, 'New', ifelse(q0 > 0 & q1 == 0, 'Lost', 'Continuing'))))
}

compare_periods <- function(dataset, selected) {
  periods <- comparison_periods(selected$date_range)
  limits <- parse_dates(c(dataset$metadata$coverage_start, dataset$metadata$coverage_end))
  if (periods$previous[1] < limits[1] || periods$current[2] > limits[2]) {
    stop_dashboard('Choose a shorter or later date range so both equal periods fit within the data coverage.')
  }
  relevant <- seq(month_start(periods$previous[1]), month_start(periods$current[2]), by = 'month')
  position <- match(relevant, dataset$coverage$month)
  if (anyNA(position) || anyNA(dataset$coverage$is_complete[position]) || any(!dataset$coverage$is_complete[position])) {
    stop_dashboard('Both comparison periods need complete data coverage.')
  }
  result <- decompose_revenue(filter_sales(dataset$sales, selected, periods$previous),
                              filter_sales(dataset$sales, selected, periods$current))
  result$periods <- periods
  result
}
