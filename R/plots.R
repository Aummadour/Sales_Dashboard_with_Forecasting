plot_theme <- function(plot, dark = FALSE) {
  foreground <- if (dark) '#e5e7eb' else '#172b3a'
  background <- if (dark) '#111c27' else '#ffffff'
  plotly::config(plotly::layout(plot, paper_bgcolor = background, plot_bgcolor = background,
    font = list(family = 'system-ui, sans-serif', color = foreground, size = 13),
    margin = list(l = 70, r = 20, t = 25, b = 55),
    xaxis = list(title = '', showgrid = FALSE),
    yaxis = list(title = 'Revenue (USD)', tickprefix = '$', separatethousands = TRUE, rangemode = 'tozero'),
    legend = list(orientation = 'h', y = -0.25)), displaylogo = FALSE,
    modeBarButtonsToRemove = c('sendDataToCloud', 'lasso2d', 'select2d'))
}

history_plot <- function(history, dark = FALSE) {
  plot <- plotly::plot_ly(history, x = ~date, y = ~total_sales, type = 'scatter', mode = 'lines+markers',
    name = 'Observed sales', line = list(color = '#2878bd'), marker = list(size = 4),
    hovertemplate = '%{x|%Y-%m-%d}<br>Revenue: $%{y:,.2f}<extra></extra>')
  plot_theme(plot, dark)
}

validation_plot <- function(result, dark = FALSE) {
  data <- result$validation
  plot <- plotly::plot_ly(data, x = ~date) |>
    plotly::add_trace(y = ~lower, type = 'scatter', mode = 'lines', line = list(width = 0),
      showlegend = FALSE, hoverinfo = 'skip', name = 'Lower prediction bound') |>
    plotly::add_trace(y = ~upper, type = 'scatter', mode = 'lines', line = list(width = 0),
      fill = 'tonexty', fillcolor = 'rgba(40,120,189,0.18)', name = '80% model prediction range',
      hovertemplate = '%{x|%b %Y}<br>Upper bound: $%{y:,.2f}<extra></extra>') |>
    plotly::add_trace(y = ~actual, type = 'scatter', mode = 'lines+markers', name = 'Heldout actual',
      line = list(color = if (dark) '#f8fafc' else '#172b3a'),
      marker = list(color = if (dark) '#f8fafc' else '#172b3a')) |>
    plotly::add_trace(y = ~model, type = 'scatter', mode = 'lines+markers', name = 'Seasonal regression',
      line = list(color = '#2878bd'), marker = list(color = '#2878bd')) |>
    plotly::add_trace(y = ~baseline, type = 'scatter', mode = 'lines+markers', name = 'Seasonal naive',
      line = list(color = '#b16b17', dash = 'dot'), marker = list(color = '#b16b17'))
  plot_theme(plot, dark)
}

future_plot <- function(result, dark = FALSE) {
  future <- result$future
  plot <- plotly::plot_ly() |>
    plotly::add_trace(data = future, x = ~date, y = ~lower, type = 'scatter', mode = 'lines',
      line = list(width = 0), showlegend = FALSE, hoverinfo = 'skip') |>
    plotly::add_trace(data = future, x = ~date, y = ~upper, type = 'scatter', mode = 'lines',
      line = list(width = 0), fill = 'tonexty', fillcolor = 'rgba(40,120,189,0.18)', name = '80% prediction range') |>
    plotly::add_trace(data = result$history, x = ~date, y = ~total_sales, type = 'scatter', mode = 'lines',
      name = 'Observed history', line = list(color = if (dark) '#f8fafc' else '#172b3a')) |>
    plotly::add_trace(data = future, x = ~date, y = ~forecast, type = 'scatter', mode = 'lines+markers',
      name = 'Future median estimate', line = list(color = '#2878bd'), marker = list(color = '#2878bd'))
  boundary <- as.character(month_end(result$history_end))
  plot <- plotly::layout(plot, shapes = list(list(type = 'line', x0 = boundary, x1 = boundary,
    y0 = 0, y1 = 1, yref = 'paper', line = list(color = '#b16b17', dash = 'dash'))))
  plot_theme(plot, dark)
}

state_revenue_plot <- function(sales, dark = FALSE) {
  # Local polygons avoid a remote topojson request. The map is the contiguous U.S.
  shapes <- maps::map('state', fill = TRUE, plot = FALSE)
  separators <- which(is.na(shapes$x))
  ends <- if (tail(separators, 1) == length(shapes$x)) separators - 1L else c(separators - 1L, length(shapes$x))
  starts <- c(1L, separators + 1L)[seq_along(ends)]
  code <- c(setNames(state.abb, tolower(state.name)), 'district of columbia' = 'DC')
  revenue <- if (nrow(sales)) tapply(sales$extended_price, sales$state, sum) else numeric()
  maximum <- if (length(revenue)) max(revenue) else 0
  palette <- grDevices::colorRampPalette(c('#dce9f5', '#1764a0'))(100)
  plot <- plotly::plot_ly()
  for (index in seq_along(ends)) {
    if (starts[index] > ends[index]) next
    name <- sub(':.*$', '', shapes$names[index])
    state <- unname(code[name])
    if (!length(state) || is.na(state) || !nzchar(state)) state <- name
    value <- unname(revenue[state])
    if (!length(value) || is.na(value)) value <- 0
    colour <- if (value == 0) { if (dark) '#344455' else '#e7ebef' } else palette[max(1, ceiling(100 * value / maximum))]
    rows <- starts[index]:ends[index]
    plot <- plotly::add_trace(plot, x = shapes$x[rows], y = shapes$y[rows], type = 'scatter',
      mode = 'lines', fill = 'toself', fillcolor = colour, line = list(color = if (dark) '#778899' else '#ffffff', width = .5),
      text = paste(toupper(state), money(value, 2), sep = ': '), hoverinfo = 'text',
      showlegend = FALSE, name = toupper(state))
  }
  plot <- plot_theme(plot, dark)
  plot <- plotly::layout(plot, xaxis = list(title = '', visible = FALSE, range = c(-126, -66)),
    yaxis = list(title = '', visible = FALSE, range = c(24, 50), scaleanchor = 'x', scaleratio = 1.25),
    margin = list(l = 0, r = 0, t = 0, b = 0), dragmode = FALSE)
  # The R builder recycles text into point arrays. Filled polygons need scalar labels.
  plot <- plotly::plotly_build(plot)
  for (index in seq_along(plot$x$data)) {
    trace <- plot$x$data[[index]]
    plot <- plotly::style(plot, name = unique(as.character(trace$name)),
      text = unique(as.character(trace$text)), hoverinfo = 'text', traces = index)
  }
  plot
}
