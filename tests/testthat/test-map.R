testthat::test_that('rendered local polygons have valid names and DC has a zero-sales hover', {
  source(file.path(project_root, 'R', 'plots.R'))
  for (dark in c(FALSE, TRUE)) {
    plot <- state_revenue_plot(sales_rows('Road', 1, 100), dark)
    traces <- plotly::plotly_build(plot)$x$data
    names <- vapply(traces, function(trace) paste(unique(as.character(trace$name)), collapse = ','), character(1))
    testthat::expect_true(all(!is.na(names) & nzchar(names)))
    testthat::expect_true(all(names %in% c(state.abb, 'DC')))
    dc <- traces[which(names == 'DC')]
    testthat::expect_length(dc, 1L)
    if (length(dc) == 1L) {
      testthat::expect_length(dc[[1]]$text, 1L)
      testthat::expect_length(dc[[1]]$hoverinfo, 1L)
      testthat::expect_equal(unique(as.character(dc[[1]]$text)), 'DC: $0.00')
      testthat::expect_equal(unique(as.character(dc[[1]]$hoverinfo)), 'text')
      testthat::expect_equal(dc[[1]]$fillcolor, if (dark) '#344455' else '#e7ebef')
      encoded <- jsonlite::fromJSON(plotly::plotly_json(plot, jsonedit = FALSE, pretty = FALSE), simplifyVector = FALSE)
      encoded_dc <- Filter(function(trace) identical(trace$name, 'DC'), encoded$data)[[1]]
      testthat::expect_identical(encoded_dc$name, 'DC')
      testthat::expect_identical(encoded_dc$text, 'DC: $0.00')
      testthat::expect_identical(encoded_dc$hoverinfo, 'text')
    }
    california <- traces[which(names == 'CA')]
    testthat::expect_gt(length(california), 0)
    testthat::expect_true(all(vapply(california, function(trace) identical(unique(as.character(trace$text)), 'CA: $100.00'), logical(1))))
  }
})
