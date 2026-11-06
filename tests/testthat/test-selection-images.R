testthat::test_that('the image catalog covers the exact stores, types and family relationships', {
  catalog <- selection_image_catalog()
  stores <- catalog[catalog$kind == 'stores', ]
  testthat::expect_equal(stores$store_id, 1:8)
  testthat::expect_equal(stores$value, c('Cedar Cycles', 'Summit Bicycle', 'Juniper Wheels',
    'Palmetto Cycle', 'Canal Bicycle', 'Sound Cycles', 'Piedmont Wheels', 'Riverbend Cycle'))
  tables <- generate_synthetic_tables(small_config())
  testthat::expect_equal(stores$store_id, tables$bikeshops$bikeshop.id)
  testthat::expect_equal(stores$value, tables$bikeshops$bikeshop.name)
  testthat::expect_equal(catalog$value[catalog$kind == 'types'], c('Mountain', 'Road'))
  families <- catalog[catalog$kind == 'families', ]
  testthat::expect_equal(families$value, c('Cross Country', 'Endurance', 'Race', 'Trail'))
  testthat::expect_equal(families$parent, c('Mountain', 'Road', 'Road', 'Mountain'))
  testthat::expect_equal(nrow(catalog), 14L)
  testthat::expect_equal(anyDuplicated(catalog$slug), 0L)
  testthat::expect_setequal(catalog$slug, c('type-road', 'type-mountain', 'family-endurance',
    'family-race', 'family-trail', 'family-cross-country', 'store-cedar-cycles',
    'store-summit-bicycle', 'store-juniper-wheels', 'store-palmetto-cycle',
    'store-canal-bicycle', 'store-sound-cycles', 'store-piedmont-wheels', 'store-riverbend-cycle'))
})

testthat::test_that('single, multiple and all applied values retain every selected mapping', {
  root <- tempfile('invented-image-fixtures-')
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  catalog <- selection_image_catalog()
  # Invented bytes test file resolution only. They are never app images.
  for (file in catalog$file) writeBin(charToRaw('invented local test fixture'), file.path(root, file))
  cases <- list(
    single = list(shops = 'Canal Bicycle', category_1 = 'Road', category_2 = 'Race'),
    multiple = list(shops = c('Cedar Cycles', 'Canal Bicycle'), category_1 = 'Mountain',
      category_2 = c('Cross Country', 'Trail')),
    all = list(shops = catalog$value[catalog$kind == 'stores'], category_1 = c('Mountain', 'Road'),
      category_2 = c('Cross Country', 'Endurance', 'Race', 'Trail')))
  for (name in names(cases)) {
    selected <- cases[[name]]
    result <- selection_images(selected, root)
    testthat::expect_equal(result$stores$value, selected$shops, info = name)
    testthat::expect_equal(result$types$value, selected$category_1, info = name)
    testthat::expect_equal(result$families$value, selected$category_2, info = name)
    for (group in result) {
      testthat::expect_true(all(group$status == 'ready'), info = name)
      testthat::expect_true(all(startsWith(group$src, 'selection-images/')), info = name)
      testthat::expect_true(all(nzchar(group$alt)), info = name)
    }
  }
  single <- selection_images(cases$single, root)
  testthat::expect_identical(single$stores$slug, 'store-canal-bicycle')
  testthat::expect_identical(single$stores$store_id, 5L)
  testthat::expect_identical(single$types$slug, 'type-road')
  testthat::expect_identical(single$families$slug, 'family-race')
  testthat::expect_true(single$families$parent_selected)
})

testthat::test_that('empty, unknown and incompatible selections have explicit safe states', {
  selected <- list(shops = character(), category_1 = character(), category_2 = character())
  result <- selection_images(selected)
  testthat::expect_equal(vapply(result, nrow, integer(1)), c(stores = 0L, types = 0L, families = 0L))
  html <- as.character(selection_images_ui(selected))
  testthat::expect_match(html, 'No stores in this applied selection.', fixed = TRUE)
  testthat::expect_false(grepl('<img', html, fixed = TRUE))
  selected <- list(shops = c('Unknown store', NA_character_), category_1 = 'Unknown type', category_2 = 'Unknown family')
  result <- selection_images(selected)
  testthat::expect_true(all(result$stores$status == 'unknown'))
  testthat::expect_identical(result$types$status, 'unknown')
  testthat::expect_identical(result$families$status, 'unknown')
  testthat::expect_true(all(is.na(result$stores$src)))
  testthat::expect_false(grepl('<img', as.character(selection_images_ui(selected)), fixed = TRUE))
  testthat::expect_false(grepl('>NA<', as.character(selection_images_ui(selected)), fixed = TRUE))
  conflict <- selection_images(list(shops = 'Canal Bicycle', category_1 = 'Mountain', category_2 = 'Race'))
  testthat::expect_identical(conflict$families$parent, 'Road')
  testthat::expect_false(conflict$families$parent_selected)
  testthat::expect_match(as.character(selection_images_ui(list(shops = 'Canal Bicycle',
    category_1 = 'Mountain', category_2 = 'Race'))), 'Road is not selected.', fixed = TRUE)
})

testthat::test_that('image paths refuse external, missing, traversal and symbolic link files', {
  root <- tempfile('invented-path-fixtures-')
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeBin(charToRaw('invented local test fixture'), file.path(root, 'type-road.jpg'))
  testthat::expect_identical(local_selection_image('type-road.jpg', root), 'selection-images/type-road.jpg')
  for (file in c('https://example.invalid/bike.jpg', '//example.invalid/bike.jpg',
    '../type-road.jpg', '/tmp/type-road.jpg', 'nested/type-road.jpg', 'type-road.svg',
    'type-road.jpg?x=1', 'type-road%2ejpg', 'missing.jpg', NA_character_, '')) {
    testthat::expect_null(local_selection_image(file, root), info = paste('refused', file))
  }
  testthat::expect_null(local_selection_image(c('type-road.jpg', 'other.jpg'), root))
  dir.create(file.path(root, 'directory.jpg'))
  testthat::expect_null(local_selection_image('directory.jpg', root))
  linked <- file.path(root, 'linked.jpg')
  testthat::expect_true(file.symlink(file.path(root, 'type-road.jpg'), linked))
  testthat::expect_null(local_selection_image('linked.jpg', root))
  linked_root <- paste0(root, '-link')
  on.exit(unlink(linked_root), add = TRUE)
  testthat::expect_true(file.symlink(root, linked_root))
  testthat::expect_null(local_selection_image('type-road.jpg', linked_root))
  missing <- selection_images(list(shops = 'Canal Bicycle', category_1 = 'Road', category_2 = 'Race'), root)
  testthat::expect_identical(missing$stores$status, 'unavailable')
  testthat::expect_true(is.na(missing$stores$src))
})

testthat::test_that('gallery HTML labels fictional images and starts with a bounded closed gallery', {
  root <- tempfile('invented-gallery-fixtures-')
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  for (file in selection_image_catalog()$file) writeBin(charToRaw('invented local test fixture'), file.path(root, file))
  html <- as.character(selection_images_ui(list(shops = 'Canal Bicycle', category_1 = 'Road', category_2 = 'Race'), root))
  testthat::expect_match(html, 'AI-generated fictional illustrations.', fixed = TRUE)
  testthat::expect_match(html, 'Stores: 1. Bike types: 1. Families: 1.', fixed = TRUE)
  testthat::expect_match(html, 'selection-images/store-canal-bicycle.webp', fixed = TRUE)
  testthat::expect_match(html, 'Fictional bicycle storefront for Canal Bicycle in Albany, NY.', fixed = TRUE)
  testthat::expect_match(html, 'Road bike category illustration', fixed = TRUE)
  testthat::expect_match(html, 'Race family illustration', fixed = TRUE)
  testthat::expect_false(grepl(' open=', html, fixed = TRUE))
  testthat::expect_false(grepl('http', html, fixed = TRUE))
})

testthat::test_that('R Markdown startup maps only its exact local illustration directory', {
  before <- shiny::resourcePaths()
  on.exit({
    for (prefix in setdiff(names(shiny::resourcePaths()), names(before))) shiny::removeResourcePath(prefix)
    for (prefix in names(before)) shiny::addResourcePath(prefix, before[[prefix]])
  }, add = TRUE)
  app <- tempfile('invented-startup-app-')
  dir.create(file.path(app, 'www', 'selection-images'), recursive = TRUE)
  on.exit(unlink(app, recursive = TRUE), add = TRUE)
  file.copy(file.path(project_root, 'R'), app, recursive = TRUE)
  file.copy(file.path(project_root, '04_demand_forecast.R'), app)
  # Execute the actual setup prefix before database or reactive work.
  document <- readLines(file.path(project_root, 'sales_dashboard_with_forecasting_app.Rmd'))
  start <- grep('^```\\{r setup,', document)[1] + 1L
  end <- which(seq_along(document) > start & document == '```')[1] - 1L
  expressions <- parse(text = document[start:end])
  startup <- expressions[seq_len(match('dataset', vapply(expressions, function(expr)
    if (is.call(expr) && identical(expr[[1]], as.name('<-')) && is.symbol(expr[[2]])) as.character(expr[[2]]) else '', character(1))) - 1L)]
  old <- setwd(app)
  on.exit(setwd(old), add = TRUE)
  unrelated <- tempfile('invented-other-resource-')
  dir.create(unrelated)
  on.exit(unlink(unrelated, recursive = TRUE), add = TRUE)
  shiny::addResourcePath('invented-unrelated', unrelated)
  expected <- shiny::resourcePaths()
  expected['selection-images'] <- normalizePath(file.path(app, 'www', 'selection-images'))
  for (attempt in 1:2) {
    eval(startup, envir = new.env(parent = globalenv()))
    testthat::expect_setequal(names(shiny::resourcePaths()), names(expected))
    testthat::expect_equal(shiny::resourcePaths()[sort(names(expected))], expected[sort(names(expected))])
  }
  testthat::expect_false(normalizePath(app) %in% shiny::resourcePaths())
  testthat::expect_false(normalizePath(file.path(app, 'www')) %in% shiny::resourcePaths())
})

testthat::test_that('illustration registration refuses missing and escaped roots without changing mappings', {
  before <- shiny::resourcePaths()
  on.exit({
    for (prefix in setdiff(names(shiny::resourcePaths()), names(before))) shiny::removeResourcePath(prefix)
    for (prefix in names(before)) shiny::addResourcePath(prefix, before[[prefix]])
  }, add = TRUE)
  app <- tempfile('invented-refused-app-')
  outside <- tempfile('invented-outside-images-')
  dir.create(app); dir.create(outside); dir.create(file.path(app, 'www'))
  on.exit(unlink(c(app, outside), recursive = TRUE), add = TRUE)
  testthat::expect_error(register_selection_image_resources(app), 'Illustration directory')
  testthat::expect_identical(shiny::resourcePaths(), before)
  testthat::expect_true(file.symlink(outside, file.path(app, 'www', 'selection-images')))
  testthat::expect_error(register_selection_image_resources(app), 'Illustration directory')
  testthat::expect_identical(shiny::resourcePaths(), before)
  unlink(file.path(app, 'www', 'selection-images'))
  unlink(file.path(app, 'www'), recursive = TRUE)
  testthat::expect_true(file.symlink(outside, file.path(app, 'www')))
  dir.create(file.path(outside, 'selection-images'))
  testthat::expect_error(register_selection_image_resources(app), 'Illustration directory')
  testthat::expect_identical(shiny::resourcePaths(), before)
})
