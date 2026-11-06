if (!requireNamespace('testthat', quietly = TRUE)) stop('testthat is missing. Follow the project runtime instructions.', call. = FALSE)
testthat::test_dir('tests/testthat', reporter = 'summary', stop_on_failure = TRUE)
