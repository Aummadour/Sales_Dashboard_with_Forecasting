selection_image_catalog <- function() {
  stores <- data.frame(kind = 'stores', store_id = 1:8,
    value = c('Cedar Cycles', 'Summit Bicycle', 'Juniper Wheels', 'Palmetto Cycle',
      'Canal Bicycle', 'Sound Cycles', 'Piedmont Wheels', 'Riverbend Cycle'),
    parent = NA_character_,
    slug = c('store-cedar-cycles', 'store-summit-bicycle', 'store-juniper-wheels',
      'store-palmetto-cycle', 'store-canal-bicycle', 'store-sound-cycles',
      'store-piedmont-wheels', 'store-riverbend-cycle'))
  cities <- c('Sacramento, CA', 'Denver, CO', 'Austin, TX', 'Orlando, FL',
    'Albany, NY', 'Tacoma, WA', 'Raleigh, NC', 'Columbus, OH')
  stores$alt <- sprintf('Fictional bicycle storefront for %s in %s.', stores$value, cities)
  types <- data.frame(kind = 'types', store_id = NA_integer_, value = c('Mountain', 'Road'),
    parent = NA_character_, slug = c('type-mountain', 'type-road'),
    alt = c('Mountain bike category illustration with flat handlebars and knobby tires.',
      'Road bike category illustration with drop handlebars and narrow tires.'))
  families <- data.frame(kind = 'families', store_id = NA_integer_,
    value = c('Cross Country', 'Endurance', 'Race', 'Trail'),
    parent = c('Mountain', 'Road', 'Road', 'Mountain'),
    slug = c('family-cross-country', 'family-endurance', 'family-race', 'family-trail'),
    alt = c('Cross Country family illustration of a hardtail mountain bike.',
      'Endurance family illustration of a road bike with relaxed geometry.',
      'Race family illustration of a road bike with racing geometry.',
      'Trail family illustration of a mountain bike with full suspension.'))
  catalog <- rbind(stores, types, families)
  catalog$file <- paste0(catalog$slug, '.webp')
  catalog
}

register_selection_image_resources <- function(app_dir = '.') {
  app_dir <- normalizePath(app_dir, mustWork = TRUE)
  www <- file.path(app_dir, 'www')
  root <- file.path(www, 'selection-images')
  if (!dir.exists(root) || nzchar(Sys.readlink(www)) || nzchar(Sys.readlink(root))) {
    stop('Illustration directory is missing or is a symbolic link.', call. = FALSE)
  }
  root <- normalizePath(root, mustWork = TRUE)
  if (!identical(root, file.path(app_dir, 'www', 'selection-images'))) {
    stop('Illustration directory must remain inside this app.', call. = FALSE)
  }
  shiny::addResourcePath('selection-images', root)
  invisible(root)
}

local_selection_image <- function(file, root = file.path('www', 'selection-images')) {
  if (length(file) != 1L || is.na(file) ||
      !grepl('^[a-z0-9]+(-[a-z0-9]+)*\\.(jpg|jpeg|png|webp)$', file)) return(NULL)
  if (!dir.exists(root) || nzchar(Sys.readlink(root))) return(NULL)
  path <- file.path(root, file)
  if (!file.exists(path) || dir.exists(path) || nzchar(Sys.readlink(path))) return(NULL)
  base <- normalizePath(root, mustWork = TRUE)
  actual <- normalizePath(path, mustWork = TRUE)
  if (!identical(dirname(actual), base)) return(NULL)
  paste0('selection-images/', file)
}

selection_images <- function(selected, root = file.path('www', 'selection-images')) {
  catalog <- selection_image_catalog()
  fields <- c(stores = 'shops', types = 'category_1', families = 'category_2')
  result <- lapply(names(fields), function(kind) {
    values <- unique(as.character(selected[[fields[[kind]]]]))
    rows <- catalog[rep(NA_integer_, length(values)), , drop = FALSE]
    rownames(rows) <- NULL
    rows$kind <- rep(kind, length(values))
    rows$value <- ifelse(is.na(values), '(unknown)', values)
    rows$src <- rep(NA_character_, length(values))
    rows$status <- rep('unknown', length(values))
    rows$parent_selected <- rep(NA, length(values))
    candidates <- catalog[catalog$kind == kind, , drop = FALSE]
    for (index in seq_along(values)) {
      match <- match(values[index], candidates$value)
      if (is.na(match)) next
      rows[index, names(catalog)] <- candidates[match, ]
      src <- local_selection_image(rows$file[index], root)
      rows$status[index] <- if (is.null(src)) 'unavailable' else 'ready'
      if (!is.null(src)) rows$src[index] <- src
      if (kind == 'families') rows$parent_selected[index] <- rows$parent[index] %in% selected$category_1
    }
    rows
  })
  names(result) <- names(fields)
  result
}

selection_images_ui <- function(selected, root = file.path('www', 'selection-images')) {
  groups <- selection_images(selected, root)
  labels <- c(stores = 'Stores', types = 'Bike types', families = 'Families')
  empty <- c(stores = 'No stores in this applied selection.',
    types = 'No bike types in this applied selection.', families = 'No families in this applied selection.')
  counts <- vapply(groups, nrow, integer(1))
  figure <- function(row, kind) {
    image <- if (identical(row$status, 'ready')) shiny::tags$img(src = row$src,
      alt = row$alt, loading = 'lazy', decoding = 'async', width = '240', height = '160') else
        shiny::tags$p(class = 'selection-image-unavailable',
          if (identical(row$status, 'unknown')) 'No illustration mapping for this selection.' else 'Illustration unavailable.')
    parent_note <- if (kind == 'families' && !is.na(row$parent)) shiny::tagList(
      shiny::tags$span(class = 'selection-image-parent', row$parent),
      if (isFALSE(row$parent_selected)) shiny::tags$span(class = 'selection-image-parent',
        paste0(row$parent, ' is not selected. This family has no selected parent type.')))
    shiny::tags$li('data-image-slug' = if (!is.na(row$slug)) row$slug else 'unknown',
      shiny::tags$figure(image, shiny::tags$figcaption(row$value, parent_note)))
  }
  shiny::tags$div(id = 'selection-illustrations',
    shiny::tags$p(class = 'selection-image-note',
      'AI-generated fictional illustrations. Storefronts are fictional premises. Bicycle images show categories, not specific product models.'),
    shiny::tags$details(class = 'selection-gallery',
      shiny::tags$summary(sprintf('View selection illustrations. Stores: %d. Bike types: %d. Families: %d.',
        counts[['stores']], counts[['types']], counts[['families']])),
      lapply(names(groups), function(kind) {
        rows <- groups[[kind]]
        shiny::tags$section(class = 'selection-image-group', 'data-image-kind' = kind,
          shiny::tags$h4(paste0(labels[[kind]], ' (', nrow(rows), ')')),
          if (!nrow(rows)) shiny::tags$p(empty[[kind]]) else
            shiny::tags$ul(class = 'selection-image-list', tabindex = '0',
              'aria-label' = paste(labels[[kind]], 'illustrations'),
              lapply(seq_len(nrow(rows)), function(index) figure(rows[index, ], kind)))
        )
      })))
}
