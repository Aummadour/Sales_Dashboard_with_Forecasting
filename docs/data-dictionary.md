# Synthetic bicycle data

The generator creates fictional stores, products and sales. It uses no customer or personal data. Public U.S. city names and state codes supply geography only. Monetary values are USD. Quantities count bikes, not order lines.

Default configuration: seed `20261106`, coverage January 1, 2016 through December 31, 2025. The 120 complete months have seasonal demand, changing category shares and modest price changes. The default applied window is January 1, 2022 through December 31, 2025. The seed fixes the table contents on the tested R runtime; it does not make the data representative of a real retailer.

| Table | Columns and meaning |
| --- | --- |
| `bikes` | `bike.id`: unique product key. `model`: fictional model name. `description`: bike type, family and frame material separated by ` - `. `price`: positive reference unit price in USD. |
| `bikeshops` | `bikeshop.id`: unique customer key. `bikeshop.name`: fictional store. `location`: public city and two letter U.S. state code. |
| `orderlines` | `(order.id, order.line)`: unique line key. `customer.id` and `product.id`: foreign keys. `order.date`: ISO date. `quantity`: positive integer bikes. `unit.price`: positive transaction price in USD. |
| `month_coverage` | `month`: unique first day of each month in the declared span. `is_complete`: whether all sales for that month are represented. |
| `metadata` | One row with `schema_version`, `seed`, `coverage_start` and `coverage_end`. Version 1 is this synthetic schema. |

The original product and customer join keys remain. The new data generator adds transaction price and coverage metadata. SQLite joins order lines to stores and bikes and computes `quantity * unit.price` before `collect()`. Weighted prices and revenue use the transaction price. Reference product price is not substituted for it.

Schema checks reject missing columns or values, duplicate keys, broken foreign keys, invalid dates, dates outside coverage, noninteger quantities and invalid prices. The loader checks that the joins preserve the line count. A missing database fails before a connection can create an empty file. Connections close on success and error. The generator uses a temporary database, validates its tables and refuses to replace an existing output unless `--overwrite` is explicit.

A complete month with no matching sales rows means zero revenue for the selected stores and categories. A missing or incomplete coverage row means unknown. Forecasting and comparison refuse unknown coverage. Partial months at the selected range boundaries are excluded from monthly forecasting. Historical charts include only dates in the applied range; their boundary buckets can be partial. A zero sales selection has a useful empty state.

The Mountain to Road ratio is total Mountain bikes divided by total Road bikes. A zero Road denominator has no ratio. The dashboard says `No Road bikes sold`, or `No bikes sold` when the selection is empty. It never adds an arbitrary small denominator.
