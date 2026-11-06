# Explicit opt-in setup for a fresh checkout. Installs only in this project.
library_path <- file.path(getwd(), '.runtime', 'library')
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(library_path, .Library))
packages <- c('flexdashboard', 'shiny', 'plotly', 'DBI', 'RSQLite', 'dplyr', 'dbplyr',
              'maps', 'testthat', 'rmarkdown', 'knitr')
utils::install.packages(packages, lib = library_path, repos = 'https://cloud.r-project.org',
                        dependencies = c('Depends', 'Imports', 'LinkingTo'))
inventory <- utils::installed.packages(lib.loc = library_path)
utils::write.csv(inventory[, c('Package', 'Version', 'Built'), drop = FALSE],
                file.path('.runtime', 'package-inventory.csv'), row.names = FALSE)
cat('Project library created. Set R_LIBS_USER to .runtime/library for each command.\n')
cat('Install Pandoc separately if it is not available, then run scripts/check_runtime.R.\n')
