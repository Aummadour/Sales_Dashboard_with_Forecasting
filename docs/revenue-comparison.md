# Original period comparison

Compare selected stores and categories in the applied inclusive date range with the immediately preceding equal number of days. Both periods must fit within declared complete data coverage. The comparison reports revenue, bikes and weighted unit prices. It does not compare unequal calendar durations or silently treat unknown dates as zero.

For each category (bike type and family), let `q` be bikes, `p` be revenue divided by bikes, `Q` be all selected bikes and `s = q / Q`. Subscript 0 is previous and 1 is current. Revenue is `Q * sum(s * p)`.

The sequential accounting components are:

| Component | Formula | Meaning |
| --- | --- | --- |
| Volume | `(Q1 - Q0) * sum(s0 * p0)` | Change total bikes at previous category shares and reference prices. |
| Category mix | `Q1 * sum((s1 - s0) * p0)` | Change category shares at those reference prices. |
| Weighted price | `Q1 * sum(s1 * (p1 - p0))` | Change weighted unit prices inside categories. This includes transaction prices and product mix within a category. |

The three unrounded components sum to observed current revenue minus previous revenue. Per category components also reconcile. Displayed cents are rounded. The sequence is a declared accounting convention; a different sequence can assign interaction terms differently. It does not establish causes, pricing power or an action to take.

New categories have no observed previous price, so their current price is the reference. Lost categories keep their previous price. If previous total bikes is zero, use current category shares. If current total is zero, use previous shares. Both zero gives zero components. These conventions avoid division by zero and keep the revenue change tie without inventing an observed historical price.
