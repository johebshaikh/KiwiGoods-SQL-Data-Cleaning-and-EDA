# KiwiGoods: SQL Data Cleaning and EDA

A SQL project in MySQL: clean four messy tables from a fictional NZ online retailer, then answer a stakeholder's questions about revenue.

> **The data is synthetic.** I generated it for practice, with data quality problems planted on purpose. The findings describe this dataset only and are not real market insights.

## The business problem

KiwiGoods is a fictional NZ online store selling homewares, outdoor gear, food and gifts. The Head of E-commerce asks:

> How much did we really make, excluding GST? Which regions and categories drive it? Do customers come back? And can I trust this data?

## Data

Four CSV files, imported as text into raw tables and profiled before any change:

| Table | Rows | Contents |
|---|---|---|
| customers | 622 | name, email, phone, city, region, signup date, loyalty member |
| products | 36 | name, category, unit price, cost price, supplier |
| orders | 2,430 | customer, order date, status, payment method, shipping fee |
| order_items | 4,640 | order, product, quantity, unit price at sale |

## Tools and method

MySQL Workbench, SQL (joins, CTEs, window functions, `GROUP BY` with `HAVING`, `STR_TO_DATE`, `REPLACE`).
The cleaning and EDA structure follows Alex the Analyst's SQL portfolio project tutorial, applied here to a new, multi-table dataset.

## Data cleaning

Work was done on staging copies, and the raw tables were never changed. Every step was checked with a count or a query.
The full list of problems is in [`data_quality_log.md`](data_quality_log.md), and the code is in [`02_data_cleaning.sql`](02_data_cleaning.sql).

| Problem | Fix |
|---|---|
| 22 duplicate customers, 30 duplicate orders | `ROW_NUMBER()` in a CTE, delete `row_num > 1` |
| 32 spellings of 10 cities (case, spaces, AKL, WLG, CHCH) | `TRIM` and `UPDATE ... LIKE` |
| 70 blank regions | Filled from the city with a self join |
| Emails: 45 blank, 23 with " at " instead of "@", mixed case | NULL, `REPLACE`, `LOWER` |
| Phones in 4 formats | One format: 10 plain digits |
| Dates in two formats (day first and year first) | Two `STR_TO_DATE` updates, then `DATE` type |
| 8 orders dated 2030 | Set to NULL, rows kept |
| 31 impossible quantities (0, negatives, 500, 999) | Set to NULL, rows kept |
| 120 blank sale prices | Filled from the product price by `product_id` |
| `$` in prices, category spellings, blank costs | `REPLACE`, `UPDATE ... LIKE`, NULL |
| 35 orders with no customer, 40 items with no product | Kept and flagged ("Unknown Customer", "Unknown Product") |

Final clean tables: customers 600, orders 2,400, order items 4,640, products 36.

## Revenue definition

- **Revenue = Delivered orders only, excluding GST.** Cancelled orders were never completed, returned orders are assumed refunded, and shipped orders are not yet delivered.
- **GST is removed by dividing by 1.15.** Prices are assumed to include 15% GST. Dividing by 1.15 is correct, while multiplying by 0.85 would understate revenue.
- Revenue = `quantity x unit_price_at_sale`. Shipping fees are not included.

## Findings

All figures are Delivered revenue excluding GST, in NZD.

**Total: 390,109.21.** Including GST, Delivered orders are 448,625.59. For reference, the gross item value of the other statuses (including GST) is Shipped 38,759.32, Returned 35,639.02 and Cancelled 40,781.04.

**By category**

| Category | Revenue |
|---|---|
| Outdoor & Sport | 97,187.87 |
| Food & Drink | 85,785.76 |
| Gifts & Souvenirs | 76,114.45 |
| Home & Kitchen | 72,183.80 |
| Beauty & Care | 55,915.05 |
| Unknown product | 2,922.28 |

**By region**

| Region | Revenue |
|---|---|
| Auckland | 125,678.05 |
| Wellington | 70,438.14 |
| Canterbury | 50,544.37 |
| Otago | 45,372.18 |
| Bay of Plenty | 30,938.77 |
| Waikato | 28,464.42 |
| Hawkes Bay | 14,174.62 |
| Manawatu-Whanganui | 9,983.96 |
| Nelson | 8,650.79 |
| Unknown customer | 5,863.92 |

Auckland alone is about 32% of revenue, and Auckland and Wellington together are about 50%.

**Over time:** orders run from January 2024 to 17 September 2026. Revenue was 148,748.50 in 2024, 145,044.36 in 2025 and 95,621.10 in 2026 so far (a partial year). The busiest month was December 2025 (15,769.50).

**Repeat customers:** of 571 known customers with a Delivered order, 494 ordered more than once and 77 once. This high repeat rate is an artefact of how the synthetic orders were generated and should not be read as a real result. Two customers (C0402 and C0329) placed 11 Delivered orders each.

**Top 3 products by year:** Headlamp, Harakeke Hand Cream and NZ Map Poster in 2024. Manuka Honey 500g, Dry Bag 20L and Harakeke Hand Cream in 2025. NZ Map Poster, Pinot Noir Vinegar and Harakeke Hand Cream in 2026.

**Payment methods:** Credit Card is 45.1% of orders and 45.1% of revenue. Afterpay is 24.6% of orders and 25.2% of revenue. PayPal and Bank Transfer are about 14% each. 50 orders (2.1%) have no payment method recorded, worth 7,233.07 (1.9% of revenue).

## How reliable is the revenue?

The total of 390,109.21 is reliable, because every order is counted in it. About **2.4% (9,481.45)** rests on records with a missing customer, product or date, so the splits by region (1.5%), category (0.7%) and month (0.2%) are slightly understated. 31 items with an impossible quantity could not be priced, so the true total may be a little higher, by an amount that can't be measured.

Each split was reconciled to the total, for example `revenue by category + unknown product = total revenue`.

## Recommendations (illustrative)

1. Ask the data owners why 30 customers and 10 products are missing from the source files.
2. Add date validation at order entry, so impossible dates like 2030 can't be saved.
3. Record the payment method on every order.
4. Review the dependence on Auckland, which brings in about a third of revenue.

## Assumptions and limits

- Prices include GST, and the sale price equals the product's current price where a sale price was blank.
- Setting impossible dates and quantities to NULL keeps the revenue but removes those rows from date and quantity analysis.
- This is a synthetic dataset, so patterns such as repeat purchases are not real findings.

## Repository

```
data/                      the four CSV files
data_quality_log.md        every problem found, with row counts
02_data_cleaning.sql       the cleaning script
03_eda.sql                 the analysis queries
README.md                  this file
```

## How to reproduce

1. Create a schema in MySQL Workbench and import each CSV with the Table Data Import Wizard as `raw_customers`, `raw_products`, `raw_orders` and `raw_order_items`, with every column set to text.
2. Check that the row counts match the table above.
3. Create the `_staging` copies, then run `02_data_cleaning.sql` and `03_eda.sql`.
