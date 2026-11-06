testthat::test_that('volume, category mix and weighted price tie to an independent revenue change', {
  previous <- sales_rows(c('Road', 'Mountain'), c(10, 10), c(100, 200))
  current <- sales_rows(c('Road', 'Mountain'), c(24, 6), c(110, 220))
  result <- decompose_revenue(previous, current)
  testthat::expect_equal(result$previous_revenue, 3000)
  testthat::expect_equal(result$current_revenue, 3960)
  testthat::expect_equal(result$change, 960)
  testthat::expect_equal(result$components$change, c(1500, -900, 360))
  testthat::expect_equal(sum(result$categories$volume), 1500)
  testthat::expect_equal(sum(result$categories$mix), -900)
  testthat::expect_equal(sum(result$categories$price), 360)
  testthat::expect_equal(sum(result$components$change), 960)
})

testthat::test_that('new and lost categories have declared reference prices and no invented price change', {
  previous <- sales_rows('Road', 10, 100)
  current <- sales_rows('Mountain', 5, 200)
  result <- decompose_revenue(previous, current)
  testthat::expect_equal(result$components$change, c(-500, 500, 0))
  testthat::expect_equal(result$change, 0)
  testthat::expect_setequal(result$categories$status, c('New', 'Lost'))
  testthat::expect_equal(result$categories$previous_price[result$categories$status == 'New'], 200)
  testthat::expect_equal(result$categories$current_price[result$categories$status == 'Lost'], 100)
})

testthat::test_that('zero periods and equal revenue retain a complete accounting tie', {
  rows <- sales_rows('Road', 10, 100)
  empty <- rows[FALSE, ]
  testthat::expect_equal(decompose_revenue(empty, rows)$components$change, c(1000, 0, 0))
  testthat::expect_equal(decompose_revenue(rows, empty)$components$change, c(-1000, 0, 0))
  testthat::expect_equal(decompose_revenue(empty, empty)$components$change, c(0, 0, 0))
  testthat::expect_equal(decompose_revenue(rows, rows)$components$change, c(0, 0, 0))
})

testthat::test_that('previous comparison period has the same inclusive day count across leap days', {
  periods <- comparison_periods(as.Date(c('2024-03-01', '2024-03-31')))
  testthat::expect_equal(periods$previous, as.Date(c('2024-01-30', '2024-02-29')))
  testthat::expect_equal(periods$days, 31)
  testthat::expect_error(comparison_periods(as.Date(c('2024-03-31', '2024-03-01'))), 'date')
})

testthat::test_that('comparison applies the same stores and categories to both periods', {
  rows <- sales_rows(c('Road', 'Road', 'Road', 'Road', 'Mountain', 'Mountain'),
    c(10, 12, 100, 200, 90, 80), c(100, 110, 100, 100, 200, 200),
    c('2025-01-10', '2025-02-10', '2025-01-10', '2025-02-10', '2025-01-10', '2025-02-10'))
  rows$bikeshop.name[3:4] <- 'Other store'
  dataset <- list(sales = rows,
    metadata = data.frame(coverage_start = '2025-01-01', coverage_end = '2025-02-28'),
    coverage = data.frame(month = as.Date(c('2025-01-01', '2025-02-01')), is_complete = TRUE))
  selected <- list(date_range = as.Date(c('2025-02-01', '2025-02-28')),
    shops = 'Fictional shop', category_1 = 'Road', category_2 = 'Road family')
  result <- compare_periods(dataset, selected)
  testthat::expect_equal(result$periods$previous, as.Date(c('2025-01-04', '2025-01-31')))
  testthat::expect_equal(result$previous_revenue, 1000)
  testthat::expect_equal(result$current_revenue, 1320)
  testthat::expect_equal(result$components$change, c(200, 0, 120))
  testthat::expect_equal(result$change, 320)
  for (month in 1:2) {
    incomplete <- dataset
    incomplete$coverage$is_complete[month] <- FALSE
    testthat::expect_error(compare_periods(incomplete, selected), 'complete data coverage')
    incomplete$coverage <- dataset$coverage[-month, ]
    testthat::expect_error(compare_periods(incomplete, selected), 'complete data coverage')
  }
  selected$date_range <- as.Date(c('2025-01-01', '2025-01-31'))
  testthat::expect_error(compare_periods(dataset, selected), 'both equal periods')
})
