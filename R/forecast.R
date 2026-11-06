# Fixed before evaluation: six heldout complete months and at least36 training months.
# No model search or holdout tuning. Other overview scales have no accuracy claim.
validate_monthly <- function(monthly) {
  if (!is.data.frame(monthly) || !all(c('date', 'total_sales') %in% names(monthly)) || !nrow(monthly)) {
    stop_dashboard('Monthly history must be nonempty.')
  }
  dates <- parse_dates(monthly$date)
  if (any(diff(as.numeric(dates)) <= 0)) stop_dashboard('Monthly dates must be strictly ordered.')
  expected <- seq(month_start(dates[1]), by = 'month', length.out = length(dates))
  if (!identical(dates, expected)) stop_dashboard('History must contain consecutive complete calendar months.')
  if (!is.numeric(monthly$total_sales) || any(!is.finite(monthly$total_sales) | monthly$total_sales < 0)) {
    stop_dashboard('Monthly revenue must be finite and nonnegative.')
  }
  invisible(TRUE)
}

seasonal_naive <- function(values, horizon) {
  horizon <- whole_number(horizon, 1, 24, 'Forecast horizon (months)')
  if (!is.numeric(values) || any(!is.finite(values) | values < 0)) stop_dashboard('Baseline history must be finite and nonnegative.')
  if (length(values) < 12L) stop_dashboard('Seasonal naive needs at least12 months of history.')
  rep(tail(values, 12L), length.out = horizon)
}

forecast_metrics <- function(actual, predicted) {
  if (!length(actual) || !length(predicted)) stop_dashboard('Error vectors must be nonempty.')
  if (length(actual) != length(predicted)) stop_dashboard('Error vectors must have equal length.')
  if (!is.numeric(actual) || !is.numeric(predicted) || any(!is.finite(actual)) || any(!is.finite(predicted))) {
    stop_dashboard('Error vectors must be finite numeric values.')
  }
  error <- actual - predicted
  c(MAE = mean(abs(error)), RMSE = sqrt(mean(error^2)))
}

split_holdout <- function(monthly) {
  validate_monthly(monthly)
  if (nrow(monthly) < 42L) stop_dashboard('Forecast evaluation needs at least36 training months plus six heldout complete months. Widen the date range.')
  n <- nrow(monthly)
  list(train = monthly[seq_len(n - 6L), , drop = FALSE], test = monthly[(n - 5L):n, , drop = FALSE])
}

fit_seasonal_model <- function(monthly) {
  validate_monthly(monthly)
  frame <- data.frame(revenue = monthly$total_sales, trend = seq_len(nrow(monthly)),
                       month = factor(format(monthly$date, '%m'), levels = sprintf('%02d', 1:12)))
  fit <- stats::lm(log1p(revenue) ~ trend + month, data = frame)
  if (fit$rank != 13L || fit$df.residual <= 0) stop_dashboard('Seasonal model needs enough complete yearly cycles.')
  list(fit = fit, origin = monthly$date[1])
}

predict_seasonal_model <- function(model, dates, level = .8) {
  dates <- parse_dates(dates)
  if (!is.numeric(level) || length(level) != 1L || !is.finite(level) || level <= 0 || level >= 1) {
    stop_dashboard('Prediction interval level must be between zero and one.')
  }
  month_index <- function(date) as.integer(format(date, '%Y')) * 12L + as.integer(format(date, '%m'))
  frame <- data.frame(trend = month_index(dates) - month_index(model$origin) + 1L,
                       month = factor(format(dates, '%m'), levels = sprintf('%02d', 1:12)))
  # Prediction intervals include residual and parameter uncertainty on the log scale.
  raw <- stats::predict(model$fit, newdata = frame, interval = 'prediction', level = level)
  values <- expm1(raw)
  values[values < 0] <- 0
  if (any(!is.finite(values))) stop_dashboard('Forecast ranges are not finite for this selection.')
  data.frame(date = dates, forecast = values[, 'fit'], lower = values[, 'lwr'], upper = values[, 'upr'])
}

forecast_analysis <- function(monthly, horizon = 12L, level = .8) {
  horizon <- whole_number(horizon, 1, 24, 'Forecast horizon (months)')
  split <- split_holdout(monthly)
  if (sum(monthly$total_sales) == 0) stop_dashboard('No sales in the selected complete months. Choose another selection for forecasting.')
  training_model <- fit_seasonal_model(split$train)
  predicted <- predict_seasonal_model(training_model, split$test$date, level)
  baseline <- seasonal_naive(split$train$total_sales, 6L)
  validation <- data.frame(date = split$test$date, actual = split$test$total_sales,
    model = predicted$forecast, baseline = baseline, lower = predicted$lower, upper = predicted$upper)
  model_errors <- forecast_metrics(validation$actual, validation$model)
  baseline_errors <- forecast_metrics(validation$actual, validation$baseline)
  metrics <- data.frame(method = c('Seasonal regression', 'Seasonal naive'),
    MAE = c(model_errors[['MAE']], baseline_errors[['MAE']]),
    RMSE = c(model_errors[['RMSE']], baseline_errors[['RMSE']]))
  # Only after heldout evaluation is complete, fit the future model on all selected history.
  future_model <- fit_seasonal_model(monthly)
  future_dates <- seq(month_after(tail(monthly$date, 1)), by = 'month', length.out = horizon)
  list(history = monthly, validation = validation, metrics = metrics,
    future = predict_seasonal_model(future_model, future_dates, level), interval_level = level,
    train_start = split$train$date[1], train_end = tail(split$train$date, 1),
    test_start = split$test$date[1], test_end = tail(split$test$date, 1),
    history_start = monthly$date[1], history_end = tail(monthly$date, 1),
    method = 'Fixed log revenue regression with trend and month effects')
}
