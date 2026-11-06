# Bicycle sales dashboard

![Illustration of a fictional bicycle shop. Decorative chart, not app output.](docs/screenshots/sales-header.png)

Illustration of a fictional bicycle shop. Decorative chart, not app output.

This R Shiny portfolio dashboard uses reproducible synthetic bicycle store sales. It has flexdashboard, interactive maps, database joins and store, category and date filters. It evaluates monthly forecasts and explains period revenue changes through an original comparison.

Use the dashboard to see where selected sales occurred and how revenue changed over time. Compare a modest forecast with last year's seasonal pattern. Check how much bike volume, category mix and weighted price each contribute to a period revenue change.

All data is generated. It contains no customer or personal records. Forecast accuracy on synthetic data says nothing about real retail performance. This example supplies no financial decision guidance.

## Run a fresh checkout

The tested runtime uses R 4.6.1 and Pandoc 3.13. [Tested package versions](docs/tested-packages.tsv) record the 90 installed packages. The earlier Packrat lock and deployment manifest describe an R 4.2.2 course environment. Those historical files have not been tested as a restore path for the current app. Bootstrap installs only the direct application/test packages and their required dependencies in this checkout. It does not restore all 172 old deployment records.

From the repository root:

```sh
Rscript --vanilla scripts/bootstrap.R
export R_LIBS_USER="$PWD/.runtime/library"
Rscript --vanilla scripts/check_runtime.R
Rscript --vanilla scripts/generate_data.R
Rscript --vanilla scripts/test.R
Rscript --vanilla scripts/validation_report.R
Rscript --vanilla scripts/run_app.R
```

Install Pandoc for your system. If its directory is outside PATH, set `RSTUDIO_PANDOC` to that directory. The app binds to localhost on port 7431 by default. Set `DASHBOARD_PORT` to use another available local port. Stop the R process to close the app.

Installing packages from source needs an R build toolchain and system development libraries. In the tested environment, fs 2.1.0 required libuv headers and pkg-config. Bootstrap does not install system libraries. Resolve build errors before starting the app.

The generator creates `bikes_database.db`, which Git ignores. Its default seed is `20261106`, with complete monthly coverage from 2016 through 2025. It protects an existing database. Use `--overwrite` only to replace a synthetic database you intend to discard. Use `--output` or `--seed` to choose another output or seed. See the [data dictionary and zero sales contract](docs/data-dictionary.md).

The runtime check reports a missing package or Pandoc and stops. Opening the app without data fails and shows the generator command. It does not create an empty database. Bootstrap resolves current compatible package releases and records the installed versions in `.runtime/package-inventory.csv`. That local inventory does not establish a restore of the historical Packrat environment.

## Runtime choices

The app uses Plotly and flexdashboard. It runs SQLite joins before collecting data into R. The explicit direct imports are DBI, RSQLite, dplyr, dbplyr, shiny, flexdashboard, plotly and maps. Plotly and rendering packages retain their own required dependencies.

The fixed monthly model uses base R stats instead of the previous XGBoost/calendar feature stack. This removes parsnip, timetk, xgboost and tidyquant from direct requirements and makes evaluation and prediction ranges easier to inspect. Core Shiny widgets replace shinyWidgets and delayed shinyjs clicks. The unused odbc and here imports and the broad tidyverse aggregate are removed. Store/category/date controls, historical time scales and the interactive map remain.

## Use the dashboard

Select dates, bike types, bike families and stores, then choose Apply. Historical aggregation, forecast mode and horizon share that applied state. While changes are pending or invalid, the previous applied view stays visible and the app explains what to fix. Reset restores and applies defaults without a delayed click. Appearance can change independently.

The default window is 2022-2025. The Mountain to Road ratio uses bike counts. It does not count order lines, and it is unavailable when the Road denominator is zero. The map uses local contiguous U.S. polygons and has an accessible state revenue table. Both light and dark views have readable labels and keyboard focus styles.

The selection illustrations use the applied stores, bike types and families. Pending controls leave them unchanged. Apply updates the images with the analytical selection. Reset restores all defaults. The gallery starts collapsed and shows counts. Open it to browse every selected value in horizontal lists. It does not choose one image to represent several stores or categories.

AI-generated fictional illustrations. Storefronts are fictional premises. Bicycle images show categories, not specific product models. A family label states its parent bike type. If that type is absent from the applied filters, the gallery says so. This label does not change the filters or imply matching sales. Empty, unknown and missing images have text states.

The local image catalog binds the eight synthetic store IDs and names, two bike types and four families. Images load only from `www/selection-images`. Local file checks refuse missing files, symbolic links, external URLs and paths outside that folder. The 14 WebP images keep the complete 960 by 640 frame (3:2). They total 1,432,252 bytes. Each file is from 41,938 to 195,722 bytes. The images received a review for each image and one artist revision before integration.

## Forecast validation

The fixed evaluation rule holds out the last six complete selected months, after at least 36 training months. The model is a regression of `log(1 + revenue)` on time and month. The seasonal naive baseline repeats the matching month from the prior year. Both show MAE and RMSE in USD/month. The baseline may win.

After evaluation, a separate refit on all selected complete history produces future predictions. Shading shows the model's nominal 80 percent prediction range, with explicit assumptions. It is not a smoothing ribbon. The view shows validation dates and the future boundary. Forecast accuracy is monthly only; other time units remain descriptive. See the [method and assumptions](docs/forecast-method.md).

The default synthetic run uses seed `20261106` and 26,118 order lines across all eight stores and all categories. Training covers January 2022 through June 2025. The six heldout months are July through December 2025:

| Method | MAE (USD/month) | RMSE (USD/month) |
| --- | ---: | ---: |
| Seasonal regression | 59,018.84 | 68,243.95 |
| Seasonal naive | 48,821.70 | 55,449.68 |

The baseline wins on both measures. The model and split were fixed before this run. No tuning followed these results. The future forecast uses a separate refit through December 2025. The default 12 month horizon covers January through December 2026.

The native R test suite passed 167 assertions. The original 141 cover data, calendars, real isolated SQLite joins and cleanup, Apply/Reset, no leakage, baseline errors, prediction intervals and accounting. The other 26 check map polygon labels, zero sales colors and scalar DC hover values in built and serialized traces. Four Node helper cases check default capture preservation, explicit image updates and the real missing executable path.

The real browser check passed Apply, invalid horizon refusal, Reset and empty store refusal. It also passed checks for retained state through desktop/phone resize, plot containment and visible accounting reconciliation. It observed no external page asset request or JavaScript exception. The phone page width was 390 pixels at a 390 pixel viewport. Measured contrast exceeded 4.5:1 for light body text, dark body text and dark table headings. These checks do not constitute a complete accessibility audit.

Start the synthetic app before the optional browser check. Use an installed Chrome and Node with global WebSocket support (tested with Chrome 156 and Node 26.8.2). Run `DASHBOARD_URL=http://127.0.0.1:7431/ DASHBOARD_EVIDENCE_DIR=.runtime/browser-run-1 node scripts/browser_smoke.mjs`. Choose a new evidence directory for each run. Captures go to its `screenshots` folder. The default check preserves the tracked images.

To refresh `docs/screenshots`, opt in explicitly: `DASHBOARD_UPDATE_SCREENSHOTS=1 DASHBOARD_URL=http://127.0.0.1:7431/ DASHBOARD_EVIDENCE_DIR=.runtime/browser-run-2 node scripts/browser_smoke.mjs`. This mode also keeps the run originals. Inspect the new images before committing them. File output and missing Chrome controls run with `node --test tests/browser_capture.test.mjs tests/browser_launch.test.mjs`.

Use a short private TMPDIR if your system's temporary path exceeds Chrome's socket path limit. The script opens a fresh browser profile and closes the browser group it owns. If the executable is missing, it reports the original launch error and removes the unused profile. Stop the separate R app when finished.

## Actual app views

The captures use generated data. The overview shows the default eight stores. The forecast and comparison views show Canal Bicycle with the same 2022-2025 date window and a six month future horizon. That store's validation results differ from the default all store metrics above.

Desktop overview, 1440 by 1080:

![Synthetic overview with applied filters, revenue map and historical sales](docs/screenshots/overview-desktop.png)

Desktop validation and future forecast, 1440 by 1440:

![Heldout model and baseline results with prediction ranges and the future boundary](docs/screenshots/forecast-validation-desktop.png)

Phone comparison in dark appearance, 390 by 844:

![Visible volume, category mix and weighted price components reconcile the period revenue change](docs/screenshots/comparison-phone-dark.png)

## My contributions

The additions to the course dashboard are:

- A deterministic synthetic SQLite generator, schema and coverage checks, data dictionary and connection cleanup.
- One applied filter/settings state, useful empty and invalid states, defined ratio units and responsive light/dark styling.
- A fixed time ordered evaluation, seasonal baseline, error metrics and model based prediction ranges.
- An original period comparison that reconciles volume, category mix and weighted price with the exact revenue change. [Accounting definitions and zero cases](docs/revenue-comparison.md).
- Behavioral tests for data, calendars, filters, validation, intervals and accounting.

This project builds on a course dashboard. The exact course title, version and reuse terms have not been supplied. The original history, helper entry point and historical dependency records remain. No repository license has been selected. The owner should confirm course reuse terms before choosing one.

## Existing demo

The existing demo URL is https://jshield0341.shinyapps.io/sales_dashboard_with_forecasting_app/ . Its current availability and correspondence to this branch are unverified. This work includes no hosting or deployment change.
