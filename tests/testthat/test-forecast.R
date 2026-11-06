testthat::test_that('seasonal naive repeats the last year and errors use independent literal values', {
  testthat::expect_equal(seasonal_naive(1:24, 15), c(13:24, 13:15))
  testthat::expect_equal(forecast_metrics(c(10, 20), c(12, 16)), c(MAE = 3, RMSE = sqrt(10)))
  testthat::expect_equal(forecast_metrics(c(0, 0), c(0, 0)), c(MAE = 0, RMSE = 0))
  testthat::expect_error(forecast_metrics(numeric(), numeric()), 'nonempty')
  testthat::expect_error(forecast_metrics(c(1, 2), 1), 'length')
  testthat::expect_error(forecast_metrics(c(1, NA), c(1, 2)), 'finite')
  for (h in c(0, 1.5, 25, NA, Inf)) testthat::expect_error(seasonal_naive(1:24, h), 'horizon')
  testthat::expect_error(seasonal_naive(1:11, 1), '12')
})

testthat::test_that('holdout is the final six ordered complete months with at least36 training months', {
  monthly <- monthly_fixture(48)
  split <- split_holdout(monthly)
  testthat::expect_equal(nrow(split$train), 42)
  testthat::expect_equal(nrow(split$test), 6)
  testthat::expect_equal(split$train$date[c(1, 42)], as.Date(c('2021-01-01', '2024-06-01')))
  testthat::expect_equal(split$test$date, seq(as.Date('2024-07-01'), by = 'month', length.out = 6))
  testthat::expect_error(split_holdout(monthly[1:41, ]), '36 training')
  testthat::expect_error(split_holdout(monthly[-2, ]), 'consecutive')
  testthat::expect_error(split_holdout(monthly[nrow(monthly):1, ]), 'ordered')
})

testthat::test_that('heldout actuals cannot change validation predictions or training boundaries', {
  monthly <- monthly_fixture()
  first <- forecast_analysis(monthly, 12)
  changed <- monthly
  changed$total_sales[55:60] <- changed$total_sales[55:60] * 2
  second <- forecast_analysis(changed, 12)
  testthat::expect_equal(first$validation$model, second$validation$model)
  testthat::expect_equal(first$validation$baseline, second$validation$baseline)
  testthat::expect_equal(first$validation$lower, second$validation$lower)
  testthat::expect_equal(first$validation$upper, second$validation$upper)
  testthat::expect_false(identical(first$validation$actual, second$validation$actual))
  testthat::expect_false(identical(first$future$forecast, second$future$forecast))
  testthat::expect_equal(first$train_end, as.Date('2025-06-01'))
  testthat::expect_equal(first$test_start, as.Date('2025-07-01'))
  testthat::expect_equal(first$test_end, as.Date('2025-12-01'))
})

testthat::test_that('forecast dates, actual errors and genuine prediction ranges have valid boundaries', {
  monthly <- monthly_fixture()
  analysis <- forecast_analysis(monthly, 24)
  testthat::expect_equal(analysis$future$date, seq(as.Date('2026-01-01'), by = 'month', length.out = 24))
  testthat::expect_equal(analysis$interval_level, .8)
  for (frame in list(analysis$future, analysis$validation)) {
    point <- if ('forecast' %in% names(frame)) frame$forecast else frame$model
    testthat::expect_true(all(is.finite(frame$lower) & is.finite(point) & is.finite(frame$upper)))
    testthat::expect_true(all(frame$lower >= 0 & frame$lower <= point & point <= frame$upper))
    testthat::expect_true(all(frame$upper > frame$lower))
  }
  testthat::expect_equal(analysis$validation$baseline, monthly$total_sales[43:48])
  model_error <- analysis$validation$actual - analysis$validation$model
  testthat::expect_equal(analysis$metrics$MAE[analysis$metrics$method == 'Seasonal regression'], mean(abs(model_error)))
  testthat::expect_equal(analysis$metrics$RMSE[analysis$metrics$method == 'Seasonal regression'], sqrt(mean(model_error^2)))
  testthat::expect_error(forecast_analysis(monthly, -1), 'horizon')
  invalid <- monthly; invalid$total_sales[1] <- -1
  testthat::expect_error(forecast_analysis(invalid, 12), 'nonnegative')
})

testthat::test_that('prediction bounds include residual and coefficient variance rather than a percentage ribbon', {
  training <- monthly_fixture(48)
  model <- fit_seasonal_model(training)
  date <- as.Date('2025-01-01')
  predicted <- predict_seasonal_model(model, date, .8)
  # Independent matrix calculation of the declared regression prediction interval.
  frame <- data.frame(trend = 1:48, month = factor(format(training$date, '%m'), levels = sprintf('%02d', 1:12)))
  x <- stats::model.matrix(~ trend + month, frame)
  y <- log1p(training$total_sales)
  coefficients <- qr.solve(x, y)
  residual <- y - as.vector(x %*% coefficients)
  variance <- sum(residual^2) / 35
  future_x <- stats::model.matrix(~ trend + month,
    data.frame(trend = 49, month = factor('01', levels = sprintf('%02d', 1:12))))
  mean <- as.vector(future_x %*% coefficients)
  se <- sqrt(variance * (1 + as.numeric(future_x %*% solve(crossprod(x), t(future_x)))))
  radius <- stats::qt(.9, df = 35) * se
  testthat::expect_equal(predicted$forecast, max(0, expm1(mean)), tolerance = 1e-7)
  testthat::expect_equal(predicted$lower, max(0, expm1(mean - radius)), tolerance = 1e-7)
  testthat::expect_equal(predicted$upper, max(0, expm1(mean + radius)), tolerance = 1e-7)
  single <- forecast_analysis(monthly_fixture(), 1)
  testthat::expect_equal(nrow(single$future), 1)
  testthat::expect_equal(single$future$date, as.Date('2026-01-01'))
  zero <- monthly_fixture(); zero$total_sales[] <- 0
  testthat::expect_error(forecast_analysis(zero, 12), 'No sales')
})
