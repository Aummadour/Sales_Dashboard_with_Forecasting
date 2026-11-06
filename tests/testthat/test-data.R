testthat::test_that('the seed reproduces valid fictional tables without changing caller RNG', {
  set.seed(123)
  before <- .Random.seed
  first <- generate_synthetic_tables(small_config())
  testthat::expect_identical(.Random.seed, before)
  testthat::expect_identical(first, generate_synthetic_tables(small_config()))
  testthat::expect_false(identical(first$orderlines, generate_synthetic_tables(small_config(43))$orderlines))
  testthat::expect_true(validate_tables(first))
  testthat::expect_setequal(names(first), c('bikes', 'bikeshops', 'orderlines', 'month_coverage', 'metadata'))
  testthat::expect_equal(first$month_coverage$month, c('2020-01-01', '2020-02-01', '2020-03-01'))
  testthat::expect_true(all(first$orderlines$quantity > 0 & first$orderlines$quantity %% 1 == 0))
  testthat::expect_true(all(first$orderlines$order.date >= '2020-01-01' & first$orderlines$order.date <= '2020-03-31'))
})

testthat::test_that('schema, keys, references, prices, quantities and dates fail with useful errors', {
  original <- generate_synthetic_tables(small_config())
  cases <- list(
    list(change = function(x) { x$bikes$price[1] <- NA_real_; x }, pattern = 'price'),
    list(change = function(x) { x$orderlines$quantity[1] <- 1.5; x }, pattern = 'quantity'),
    list(change = function(x) { x$orderlines$unit.price[1] <- -1; x }, pattern = 'price'),
    list(change = function(x) { x$orderlines$customer.id[1] <- 999; x }, pattern = 'customer'),
    list(change = function(x) { x$orderlines$product.id[1] <- 999; x }, pattern = 'product'),
    list(change = function(x) { x$orderlines[2, c('order.id', 'order.line')] <- x$orderlines[1, c('order.id', 'order.line')]; x }, pattern = 'unique'),
    list(change = function(x) { x$bikes$bike.id[2] <- x$bikes$bike.id[1]; x }, pattern = 'unique'),
    list(change = function(x) { x$orderlines$order.date[1] <- '2020-02-30'; x }, pattern = 'date'),
    list(change = function(x) { x$orderlines$order.date[1] <- '2019-12-31'; x }, pattern = 'coverage'),
    list(change = function(x) { x$orderlines$quantity <- NULL; x }, pattern = 'quantity')
  )
  for (case in cases) testthat::expect_error(validate_tables(case$change(original)), case$pattern)
})

testthat::test_that('missing data fails before SQLite can create an empty file', {
  missing <- tempfile(fileext = '.db')
  testthat::expect_false(file.exists(missing))
  testthat::expect_error(load_sales_data(missing), 'generate_data.R')
  testthat::expect_false(file.exists(missing))
})

testthat::test_that('joined data keeps original keys, row count and transaction revenue', {
  path <- tempfile(fileext = '.db')
  on.exit(unlink(path), add = TRUE)
  tables <- generate_synthetic_tables(small_config())
  write_synthetic_database(path, tables)
  testthat::expect_error(write_synthetic_database(path, tables), 'exists')
  data <- load_sales_data(path)
  testthat::expect_equal(nrow(data$sales), nrow(tables$orderlines))
  testthat::expect_equal(sum(data$sales$extended_price),
    sum(tables$orderlines$quantity * tables$orderlines$unit.price), tolerance = 1e-7)
  testthat::expect_true(inherits(data$sales$order.date, 'Date'))
  testthat::expect_false(anyNA(data$sales))
  testthat::expect_equal(sort(unique(data$sales$bikeshop.name)), sort(tables$bikeshops$bikeshop.name))
})

testthat::test_that('database cleanup runs after a read error and preserves the primary error', {
  path <- tempfile(fileext = '.db')
  on.exit(unlink(path), add = TRUE)
  write_synthetic_database(path, generate_synthetic_tables(small_config()))
  captured <- NULL
  primary <- simpleError('synthetic read error')
  actual <- tryCatch(with_database(path, function(con) {
    captured <<- con
    stop(primary)
  }), error = identity)
  testthat::expect_identical(actual, primary)
  testthat::expect_false(DBI::dbIsValid(captured))
})

testthat::test_that('complete calendar months with no sales are zero and unknown months are refused', {
  dates <- seq(as.Date('2020-01-01'), by = 'month', length.out = 3)
  coverage <- data.frame(month = dates, is_complete = TRUE)
  sales <- sales_rows('Road', c(2, 3), c(100, 100), c('2020-01-10', '2020-03-10'))
  result <- monthly_sales(sales, coverage, as.Date(c('2020-01-01', '2020-03-31')))
  testthat::expect_equal(result$date, dates)
  testthat::expect_equal(result$total_sales, c(200, 0, 300))
  testthat::expect_error(monthly_sales(sales, coverage[-2, ], as.Date(c('2020-01-01', '2020-03-31'))), 'coverage')
  coverage$is_complete[2] <- FALSE
  testthat::expect_error(monthly_sales(sales, coverage, as.Date(c('2020-01-01', '2020-03-31'))), 'complete')
  result <- monthly_sales(sales, transform(coverage, is_complete = TRUE), as.Date(c('2020-01-15', '2020-03-05')))
  testthat::expect_equal(result$date, as.Date('2020-02-01'))
  testthat::expect_equal(result$total_sales, 0)
})

testthat::test_that('empty filters are explicit and date limits are inclusive', {
  data <- sales_rows(c('Road', 'Mountain', 'Road'), c(1, 2, 3), c(100, 200, 100),
                     c('2025-01-01', '2025-01-02', '2025-01-03'))
  selected <- list(date_range = as.Date(c('2025-01-01', '2025-01-02')),
                   category_1 = c('Road', 'Mountain'), category_2 = unique(data$category_2),
                   shops = 'Fictional shop', time_unit = 'month', horizon = 12, forecast_mode = FALSE)
  testthat::expect_equal(filter_sales(data, selected)$order.id, c(1L, 2L))
  selected$shops <- character()
  testthat::expect_error(validate_selection(selected, data), 'Select at least one')
  selected$shops <- 'Fictional shop'
  selected$date_range <- rev(selected$date_range)
  testthat::expect_error(validate_selection(selected, data), 'date')
})

testthat::test_that('Mountain to Road ratio counts bikes and defines a zero Road denominator', {
  rows <- sales_rows(c('Road', 'Mountain'), c(2, 6), c(100, 200))
  testthat::expect_equal(sales_kpis(rows)$ratio, 3)
  testthat::expect_equal(sales_kpis(rows)$bikes, 8)
  testthat::expect_equal(sales_kpis(rows)$orders, 2)
  testthat::expect_equal(sales_kpis(rows)$revenue, 1400)
  testthat::expect_true(is.na(sales_kpis(rows[2, ])$ratio))
  testthat::expect_equal(sales_kpis(rows[2, ])$ratio_note, 'No Road bikes sold')
  testthat::expect_equal(sales_kpis(rows[FALSE, ])$ratio_note, 'No bikes sold')
})

testthat::test_that('the explicit overwrite replaces only its test output and empty data fails clearly', {
  path <- tempfile(fileext = '.db')
  on.exit(unlink(path), add = TRUE)
  first <- generate_synthetic_tables(small_config(42))
  second <- generate_synthetic_tables(small_config(43))
  write_synthetic_database(path, first)
  testthat::expect_error(write_synthetic_database(path, second), 'exists')
  testthat::expect_equal(load_sales_data(path)$metadata$seed, 42)
  write_synthetic_database(path, second, overwrite = TRUE)
  testthat::expect_equal(load_sales_data(path)$metadata$seed, 43)
  with_database(path, function(con) DBI::dbExecute(con, 'DELETE FROM orderlines'), read_only = FALSE)
  testthat::expect_error(load_sales_data(path), 'no order lines')
})

testthat::test_that('the ordinary loader connection is read only', {
  path <- tempfile(fileext = '.db')
  on.exit(unlink(path), add = TRUE)
  write_synthetic_database(path, generate_synthetic_tables(small_config()))
  testthat::expect_error(with_database(path, function(con) DBI::dbExecute(con, 'DELETE FROM orderlines')), 'readonly|read.only')
  testthat::expect_gt(nrow(load_sales_data(path)$sales), 0)
})
