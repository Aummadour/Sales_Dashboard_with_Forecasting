dashboard_filters_ui <- function(id, dataset) {
  ns <- shiny::NS(id)
  defaults <- default_selection(dataset)
  shiny::tagList(
    shiny::tags$p('Deterministic synthetic bicycle sales. No customer records.'),
    shiny::dateRangeInput(ns('dates'), 'Date range', start = defaults$date_range[1],
      end = defaults$date_range[2], min = parse_dates(dataset$metadata$coverage_start),
      max = parse_dates(dataset$metadata$coverage_end)),
    shiny::checkboxGroupInput(ns('types'), 'Bike type', choices = defaults$category_1, selected = defaults$category_1),
    shiny::selectInput(ns('families'), 'Bike family', choices = defaults$category_2, selected = defaults$category_2, multiple = TRUE),
    shiny::selectInput(ns('shops'), 'Store (customer)', choices = defaults$shops, selected = defaults$shops, multiple = TRUE),
    shiny::selectInput(ns('time_unit'), 'Historical chart unit',
      choices = c(Daily = 'day', Weekly = 'week', Monthly = 'month', Quarterly = 'quarter', Yearly = 'year'), selected = 'month'),
    shiny::checkboxInput(ns('forecast_mode'), 'Show monthly forecast', value = FALSE),
    shiny::numericInput(ns('horizon'), 'Forecast horizon (months)', value = 12, min = 1, max = 24, step = 1),
    shiny::div(class = 'filter-actions', shiny::actionButton(ns('apply'), 'Apply'), shiny::actionButton(ns('reset'), 'Reset')),
    shiny::tags$p(class = 'filter-note', 'Charts use the applied selection. Reset restores and applies defaults.'),
    shiny::div(role = 'alert', shiny::textOutput(ns('error'))),
    shiny::textOutput(ns('pending')),
    shiny::selectInput('view_mode', 'Appearance', c(Light = 'light', Dark = 'dark'), selected = 'light')
  )
}

dashboard_filters_server <- function(id, dataset) {
  shiny::moduleServer(id, function(input, output, session) {
    defaults <- default_selection(dataset)
    applied <- shiny::reactiveVal(defaults)
    error <- shiny::reactiveVal(NULL)
    read_inputs <- function() list(date_range = input$dates, category_1 = input$types,
      category_2 = input$families, shops = input$shops, time_unit = input$time_unit,
      horizon = input$horizon, forecast_mode = input$forecast_mode)
    shiny::observeEvent(input$apply, {
      candidate <- tryCatch(validate_selection(read_inputs(), dataset$sales, c(dataset$metadata$coverage_start, dataset$metadata$coverage_end)), error = identity)
      if (inherits(candidate, 'error')) error(paste('Changes not applied:', conditionMessage(candidate)))
      else { applied(candidate); error(NULL) }
    }, ignoreInit = TRUE)
    shiny::observeEvent(input$reset, {
      shiny::updateDateRangeInput(session, 'dates', start = defaults$date_range[1], end = defaults$date_range[2])
      shiny::updateCheckboxGroupInput(session, 'types', selected = defaults$category_1)
      shiny::updateSelectInput(session, 'families', selected = defaults$category_2)
      shiny::updateSelectInput(session, 'shops', selected = defaults$shops)
      shiny::updateSelectInput(session, 'time_unit', selected = defaults$time_unit)
      shiny::updateCheckboxInput(session, 'forecast_mode', value = defaults$forecast_mode)
      shiny::updateNumericInput(session, 'horizon', value = defaults$horizon)
      applied(defaults)
      error(NULL)
    }, ignoreInit = TRUE)
    output$error <- shiny::renderText(error())
    output$pending <- shiny::renderText({
      if (is.null(input$dates)) return('')
      candidate <- tryCatch(validate_selection(read_inputs(), dataset$sales, c(dataset$metadata$coverage_start, dataset$metadata$coverage_end)), error = identity)
      if (inherits(candidate, 'error') || !identical(candidate, applied())) 'Changes are pending. Select Apply.' else ''
    })
    list(applied = shiny::reactive(applied()),
      sales = shiny::reactive(filter_sales(dataset$sales, applied())),
      error = shiny::reactive(error()))
  })
}
