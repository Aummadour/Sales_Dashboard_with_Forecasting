synthetic_config <- function() {
  list(seed = 20261106L, start = as.Date('2016-01-01'), end = as.Date('2025-12-31'))
}

generate_synthetic_tables <- function(config = synthetic_config()) {
  seed <- whole_number(config$seed, 0, .Machine$integer.max, 'Seed')
  range <- validate_date_range(c(config$start, config$end))
  if (range[1] != month_start(range[1]) || range[2] != month_end(range[2])) {
    stop_dashboard('Synthetic coverage must start and end with complete months.')
  }
  previous_kind <- RNGkind()
  had_seed <- exists('.Random.seed', envir = .GlobalEnv, inherits = FALSE)
  previous_seed <- if (had_seed) get('.Random.seed', envir = .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(previous_kind))
    if (had_seed) assign('.Random.seed', previous_seed, envir = .GlobalEnv)
    else if (exists('.Random.seed', envir = .GlobalEnv, inherits = FALSE)) rm('.Random.seed', envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind('Mersenne-Twister', 'Inversion', 'Rejection')
  set.seed(seed)
  shops <- data.frame(bikeshop.id = 1:8,
    bikeshop.name = c('Cedar Cycles', 'Summit Bicycle', 'Juniper Wheels', 'Palmetto Cycle',
                     'Canal Bicycle', 'Sound Cycles', 'Piedmont Wheels', 'Riverbend Cycle'),
    location = c('Sacramento, CA', 'Denver, CO', 'Austin, TX', 'Orlando, FL',
                 'Albany, NY', 'Tacoma, WA', 'Raleigh, NC', 'Columbus, OH'))
  families <- c('Road - Endurance', 'Road - Race', 'Mountain - Trail', 'Mountain - Cross Country')
  bikes <- data.frame(bike.id = 1:16, model = sprintf('Demo bicycle %02d', 1:16),
    description = paste(rep(families, each = 4), rep(c('Aluminum', 'Aluminum', 'Carbon', 'Carbon'), 4), sep = ' - '),
    price = rep(c(850, 1200, 1900, 2600), 4) * rep(c(1, 1.2, 1.1, .95), each = 4))
  months <- seq(range[1], month_start(range[2]), by = 'month')
  lines <- list(); order_id <- 0L
  for (index in seq_along(months)) {
    first <- months[index]; days <- seq(first, month_end(first), by = 'day')
    season <- 1 + .3 * sin(2 * pi * (as.integer(format(first, '%m')) - 3) / 12)
    for (shop in shops$bikeshop.id) {
      orders <- max(3L, as.integer(round((7 + shop) * season * (1 + .003 * index))))
      for (unused in seq_len(orders)) {
        order_id <- order_id + 1L
        products <- sample(bikes$bike.id, sample(1:3, 1), replace = FALSE,
                           prob = rep(c(1 + .002 * index, 1, 1.1, 1 + .001 * index), each = 4))
        date <- sample(days, 1)
        quantity <- sample(1:5, length(products), replace = TRUE, prob = c(6, 4, 2, 1, 1))
        prices <- round(bikes$price[products] * (1 + .018 * floor((index - 1) / 12)) *
                          sample(c(.9, .95, 1), length(products), replace = TRUE), 2)
        lines[[length(lines) + 1L]] <- data.frame(order.id = order_id,
          order.line = seq_along(products), customer.id = shop, product.id = products,
          order.date = format(date, '%Y-%m-%d'), quantity = quantity, unit.price = prices)
      }
    }
  }
  tables <- list(bikes = bikes, bikeshops = shops, orderlines = do.call(rbind, lines),
    month_coverage = data.frame(month = format(months, '%Y-%m-%d'), is_complete = TRUE),
    metadata = data.frame(schema_version = 1L, seed = seed,
      coverage_start = format(range[1], '%Y-%m-%d'), coverage_end = format(range[2], '%Y-%m-%d')))
  validate_tables(tables)
  tables
}

validate_tables <- function(tables) {
  required <- list(bikes = c('bike.id', 'model', 'description', 'price'),
    bikeshops = c('bikeshop.id', 'bikeshop.name', 'location'),
    orderlines = c('order.id', 'order.line', 'customer.id', 'product.id', 'order.date', 'quantity', 'unit.price'),
    month_coverage = c('month', 'is_complete'),
    metadata = c('schema_version', 'seed', 'coverage_start', 'coverage_end'))
  for (table in names(required)) {
    if (!is.data.frame(tables[[table]])) stop_dashboard(paste('Missing table:', table))
    missing <- setdiff(required[[table]], names(tables[[table]]))
    if (length(missing)) stop_dashboard(paste('Missing columns in', table, ':', paste(missing, collapse = ', ')))
    if (anyNA(tables[[table]][required[[table]]])) stop_dashboard(paste('Missing values in', table, 'columns:', paste(required[[table]], collapse = ', ')))
  }
  positive_integer <- function(x, label) {
    if (!is.numeric(x) || any(!is.finite(x) | x <= 0 | x != floor(x))) stop_dashboard(paste('Invalid', label))
  }
  for (entry in list(c('bikes', 'bike.id'), c('bikeshops', 'bikeshop.id'))) {
    key <- tables[[entry[1]]][[entry[2]]]; positive_integer(key, entry[2])
    if (anyDuplicated(key)) stop_dashboard(paste(entry[2], 'must be unique.'))
  }
  orders <- tables$orderlines
  for (key in c('order.id', 'order.line', 'customer.id', 'product.id')) positive_integer(orders[[key]], key)
  if (anyDuplicated(paste(orders$order.id, orders$order.line))) stop_dashboard('Order id and line must be unique.')
  if (any(!orders$customer.id %in% tables$bikeshops$bikeshop.id)) stop_dashboard('Unknown customer reference.')
  if (any(!orders$product.id %in% tables$bikes$bike.id)) stop_dashboard('Unknown product reference.')
  positive_integer(orders$quantity, 'quantity')
  for (price in list(tables$bikes$price, orders$unit.price)) {
    if (!is.numeric(price) || any(!is.finite(price) | price <= 0)) stop_dashboard('Every price must be finite and positive.')
  }
  if (any(lengths(strsplit(tables$bikes$description, ' - ', fixed = TRUE)) != 3L)) stop_dashboard('Invalid product description.')
  if (any(!grepl('^.+, [A-Z]{2}$', tables$bikeshops$location))) stop_dashboard('Invalid store location.')
  metadata <- tables$metadata
  if (nrow(metadata) != 1L || metadata$schema_version != 1L) stop_dashboard('Unsupported data schema version.')
  whole_number(metadata$seed, 0, .Machine$integer.max, 'Seed')
  coverage_range <- validate_date_range(c(metadata$coverage_start, metadata$coverage_end))
  if (coverage_range[1] != month_start(coverage_range[1]) || coverage_range[2] != month_end(coverage_range[2])) stop_dashboard('Data coverage must use complete month boundaries.')
  dates <- parse_dates(orders$order.date, 'order date')
  if (any(dates < coverage_range[1] | dates > coverage_range[2])) stop_dashboard('Order date is outside data coverage.')
  coverage <- tables$month_coverage
  months <- parse_dates(coverage$month, 'coverage month')
  expected <- seq(coverage_range[1], month_start(coverage_range[2]), by = 'month')
  if (anyDuplicated(months) || !identical(sort(months), expected)) stop_dashboard('Monthly coverage is missing, duplicated or outside the declared span.')
  if (any(!coverage$is_complete %in% c(TRUE, FALSE))) stop_dashboard('Invalid complete month flag.')
  TRUE
}

with_database <- function(path, code, read_only = TRUE) {
  if (read_only && !file.exists(path)) stop_dashboard('Synthetic data is missing. Run Rscript --vanilla scripts/generate_data.R first.')
  con <- DBI::dbConnect(RSQLite::SQLite(), path,
                       flags = if (read_only) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC)
  primary <- NULL
  on.exit({
    cleanup <- tryCatch({ DBI::dbDisconnect(con); NULL }, error = identity)
    if (inherits(cleanup, 'error')) {
      if (is.null(primary)) stop(cleanup)
      else warning(paste('Database cleanup also failed:', conditionMessage(cleanup)), call. = FALSE)
    }
  }, add = TRUE)
  tryCatch(code(con), error = function(error) { primary <<- error; stop(error) })
}

write_synthetic_database <- function(path, tables = generate_synthetic_tables(), overwrite = FALSE) {
  if (file.exists(path) && !isTRUE(overwrite)) stop_dashboard('Output already exists. Use --overwrite only for a synthetic database you want to replace.')
  validate_tables(tables)
  if (!dir.exists(dirname(path))) stop_dashboard('Output directory does not exist.')
  temporary <- tempfile('.synthetic-', tmpdir = dirname(path), fileext = '.db')
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  with_database(temporary, function(con) {
    DBI::dbWithTransaction(con, {
      for (name in names(tables)) DBI::dbWriteTable(con, name, tables[[name]], row.names = FALSE)
    })
  }, read_only = FALSE)
  if (file.exists(path) && !isTRUE(overwrite)) stop_dashboard('Output was created by another process; it was not replaced.')
  if (!file.rename(temporary, path)) stop_dashboard('Could not move the generated synthetic database to its output path.')
  invisible(path)
}

load_sales_data <- function(path = 'bikes_database.db') {
  if (!requireNamespace('dbplyr', quietly = TRUE)) stop_dashboard('dbplyr is missing. Follow the runtime instructions.')
  with_database(path, function(con) {
    required <- c('bikes', 'bikeshops', 'orderlines', 'month_coverage', 'metadata')
    if (!all(required %in% DBI::dbListTables(con))) stop_dashboard('Data schema is incomplete. Regenerate the synthetic database.')
    bikes <- DBI::dbReadTable(con, 'bikes'); shops <- DBI::dbReadTable(con, 'bikeshops')
    # Preserve the original architecture: both joins and line revenue run in SQLite before collect.
    joined <- dplyr::tbl(con, 'orderlines') |>
      dplyr::left_join(dplyr::tbl(con, 'bikeshops'), by = c('customer.id' = 'bikeshop.id')) |>
      dplyr::left_join(dplyr::tbl(con, 'bikes'), by = c('product.id' = 'bike.id')) |>
      dplyr::mutate(extended_price = quantity * unit.price) |>
      dplyr::collect()
    coverage <- DBI::dbReadTable(con, 'month_coverage'); metadata <- DBI::dbReadTable(con, 'metadata')
    validate_tables(list(bikes = bikes, bikeshops = shops, orderlines = as.data.frame(joined),
                         month_coverage = coverage, metadata = metadata))
    source_count <- DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM orderlines')$n
    if (nrow(joined) != source_count) stop_dashboard('The database joins changed the order line count.')
    if (!nrow(joined)) stop_dashboard('The database has no order lines. Regenerate the synthetic data.')
    description <- do.call(rbind, strsplit(joined$description, ' - ', fixed = TRUE))
    location <- do.call(rbind, strsplit(joined$location, ', ', fixed = TRUE))
    sales <- data.frame(order.date = parse_dates(joined$order.date), order.id = joined$order.id,
      order.line = joined$order.line, state = location[, 2], quantity = joined$quantity,
      price = joined$unit.price, extended_price = joined$extended_price,
      category_1 = description[, 1], category_2 = description[, 2], frame_material = description[, 3],
      bikeshop.name = joined$bikeshop.name)
    coverage$month <- parse_dates(coverage$month); coverage$is_complete <- as.logical(coverage$is_complete)
    list(sales = sales, coverage = coverage, metadata = metadata)
  })
}
