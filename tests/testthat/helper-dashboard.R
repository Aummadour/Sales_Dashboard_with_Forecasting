project_root <- normalizePath(file.path('..', '..'), mustWork = TRUE)
for (file in c('utils.R', 'data.R', 'analysis.R', 'comparison.R', 'forecast.R', 'filters.R')) {
  source(file.path(project_root, 'R', file), local = FALSE)
}

small_config <- function(seed = 42L) {
  list(seed = seed, start = as.Date('2020-01-01'), end = as.Date('2020-03-31'))
}

sales_rows <- function(category, quantity, price, dates = '2025-01-15') {
  data.frame(order.date = as.Date(rep(dates, length.out = length(quantity))),
             order.id = seq_along(quantity), order.line = 1L,
             state = rep('CA', length(quantity)), quantity = quantity, price = price,
             extended_price = quantity * price,
             category_1 = category, category_2 = paste0(category, ' family'),
             frame_material = rep('Aluminum', length(quantity)),
             bikeshop.name = rep('Fictional shop', length(quantity)))
}

monthly_fixture <- function(n = 60L) {
  date <- seq(as.Date('2021-01-01'), by = 'month', length.out = n)
  # A fixed known seasonal pattern and trend, with nonzero residual variation.
  data.frame(date = date, total_sales = round(exp(7 + seq_len(n) * 0.008 +
    rep(c(0, .1, .2, .3, .4, .5, .4, .3, .2, .1, 0, -.1), length.out = n) +
    rep(c(-.03, .02, .01, -.01, .025), length.out = n)) - 1, 2))
}
