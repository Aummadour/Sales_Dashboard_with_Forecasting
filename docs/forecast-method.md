# Forecast evaluation and prediction ranges

The method was fixed before evaluation. It is a modest reference model for a synthetic portfolio example. There is no model search or tuning against heldout values.

1. Apply stores, categories, dates and horizon as one selection. Complete the monthly calendar only inside declared complete coverage. Include complete zero sales months. Exclude partial boundary months.
2. Reserve the last six complete selected months as a time ordered holdout. Require at least 36 earlier complete months. Fit the evaluation model only on that training period.
3. Compare a fixed regression with a seasonal naive baseline. The regression uses `log(1 + monthly revenue)` as response, a linear time index and month factors. The baseline repeats the matching month from the last training year. It uses no test actuals.
4. Show both MAE and RMSE in USD per month, all six test dates, test count and training dates. Either model can win. Do not change the model to manufacture a win.
5. After evaluation, refit the same specification on all selected complete history. Forecast 1-24 future months. Keep future estimates and heldout validation separate. Show the history boundary.

MAE is the mean absolute error. RMSE is the square root of mean squared error. Neither is divided by actual revenue, so zero actuals are valid. Results describe only the selected synthetic sample and say nothing about real retail performance.

`stats::predict.lm(..., interval = 'prediction', level = 0.80)` supplies a real conditional prediction range. It includes estimated residual and parameter uncertainty. Bounds and the point are transformed back with `expm1`; values below zero are limited to zero. The point is a median estimate on the revenue scale, not a bias corrected conditional mean. This is not a smoothing band or an arbitrary percentage around the point.

The nominal 80 percent level relies on independent, normally distributed residuals with constant variance on the log scale, a correct regression specification and continued seasonal/trend behavior. Real sales can violate these assumptions. These ranges are not a claim of calibrated real world coverage. Six heldout months are too few to establish general coverage. Extreme or nonfinite fits fail with a useful message. No forecast is supplied for an all zero history.

Daily, weekly, quarterly and yearly overview charts remain descriptive. Their accuracy is not evaluated and they receive no forecast accuracy claim. Forecast evaluation and future predictions always use monthly USD revenue.
