-- ============================================================
-- KiwiGoods: Step 3, Exploratory Data Analysis (EDA)
-- ============================================================
-- Business questions from the Head of E-commerce:
--   How much did we really make, excluding GST?
--   Which categories and regions drive it?
--   Do customers come back?
--   Can we trust the data?
--
-- Revenue definition used in this file:
--   * Delivered orders only (cancelled and returned orders are not revenue,
--     shipped orders have not arrived yet).
--   * Excluding GST: prices include 15% GST, so revenue = price / 1.15.
--   * Revenue = quantity * unit_price_at_sale. Shipping fees are not included.
--
-- Tables: order_items_staging (oi), orders_staging2 (o), products_staging (p), customers_staging2 (c)
-- Habit: after every split, add the pieces up and compare with the total.


-- ============================================================
-- 1. Total value of all items
-- ============================================================
select round(sum(quantity * unit_price_at_sale),2) as Total_value
from order_items_staging;
-- 563,804.97 = value of every item, before GST and before looking at order status

-- How many items contributed to that total?
select count(quantity * unit_price_at_sale)as Total_value
from order_items_staging;
-- 4609, not 4640: the 31 items with a NULL quantity (impossible values set to NULL)
-- cannot be priced, so the total is slightly understated.


-- ============================================================
-- 2. Value by order status
-- ============================================================
-- Join items to orders on order_id to get each item's status.
select o.status, round(sum(oi.quantity * oi.unit_price_at_sale),2) as Total_value
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
group by 1;
-- Delivered 448,625.59, Returned 35,639.02, Cancelled 40,781.04, Shipped 38,759.32
-- These add up to 563,804.97, so the join lost and duplicated nothing.


-- ============================================================
-- 3. Revenue: Delivered only, excluding GST
-- ============================================================
select o.status, round(sum(oi.quantity * oi.unit_price_at_sale)/1.15 ,2) as Total_value
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status = 'Delivered'
group by 1;
-- Revenue (Delivered, excluding GST) = 390,109.21
-- GST in those orders = 448,625.59 - 390,109.21 = 58,516.38
-- (15% of the price WITHOUT GST. Dividing by 1.15 is correct, multiplying by 0.85 is not.)


-- ============================================================
-- 4. Revenue by category
-- ============================================================
-- Three tables: items to orders (order_id), items to products (product_id).
select p.category,o.status,round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join order_items_staging oi
on oi.order_id=o.order_id
join products_staging p
on p.product_id=oi.product_id
where o.status = 'Delivered'
group by 1
order by Revenue_excluding_GST desc;
-- Outdoor & Sport 97,187.87
-- Food & Drink 85,785.76
-- Gifts & Souvenirs 76,114.45
-- Home & Kitchen 72,183.80
-- Beauty & Care 55,915.05
-- Sum = 387,186.93, which is 2,922.28 below 390,109.21 (reconciled below)

-- Reconciliation: the gap is the revenue of items whose product is not in the product table.
select oi.product_status,o.status, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and oi.product_status= 'Unknown Product'
group by 1;
-- 2,922.28, so: revenue by category + unknown products = total revenue


-- ============================================================
-- 5. Revenue by region
-- ============================================================
-- Chain: items to orders (order_id), orders to customers (customer_id).
select c.region,o.status, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join customers_staging2 c
on c.customer_id=o.customer_id
join order_items_staging oi
on oi.order_id=o.order_id
where o.status='Delivered'
group by 1
order by Revenue_excluding_GST desc;
-- Auckland 125,678.05
-- Wellington 70,438.14
-- Canterbury 50,544.37
-- Otago 45,372.18
-- Bay of Plenty 30,938.77
-- Waikato 28,464.42
-- Hawkes Bay 14,174.62
-- Manawatu-Whanganui 9,983.96
-- Nelson 8,650.79

-- Reconciliation: add up the nine regions
with a as
(
select c.region,o.status, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join customers_staging2 c
on c.customer_id=o.customer_id
join order_items_staging oi
on oi.order_id=o.order_id
where o.status='Delivered'
group by 1
order by Revenue_excluding_GST desc
)
select sum(Revenue_excluding_GST)
from a;
-- 384,245.30

-- The gap is the revenue of orders whose customer is not in the customer table.
select o.status,o.customer_status,round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join order_items_staging oi
on o.order_id=oi.order_id
where o.status= 'Delivered' and o.customer_status= 'Unknown Customer'
group by 1;
-- 5,863.92, so: revenue by region + unknown customers = total revenue
-- (A one-cent difference can appear because each region is rounded before adding.)


-- ============================================================
-- 6. Monthly revenue and the rolling total
-- ============================================================
-- substring(order_date, 1, 7) keeps the year and month, for example 2024-01.
-- Orders with a NULL date (the 2030 fix) are left out of the monthly view.
select substring(o.order_date, 1,7) as Month, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.order_date is not null and o.status= 'Delivered'
group by Month
order by Month;
-- 33 months. First two: 2024-01 13,293.17 and 2024-02 12,278.05

-- Rolling total: the revenue so far, month by month.
-- The CTE holds the monthly revenue, and sum() over (order by Month) adds it up as it goes.
with rolling_total as
(
select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.order_date is not null and o.status= 'Delivered'
group by Month
order by Month asc
)
select Month, Revenue_excluding_GST, sum(Revenue_excluding_GST) over (order by Month)
from rolling_total;
-- Last month (2026-09): 5,455.69 and a rolling total of 389,413.97

-- Where is the rest of the 390,109.21? In the orders with a NULL date.
select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.order_date is null and o.status= 'Delivered'
group by Month
order by Month asc;
-- 695.25 (month is NULL)

-- Proof: monthly revenue + revenue with no date = total revenue
with dated_revenue as
(
select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.order_date is not null and o.status= 'Delivered'
group by Month
order by Month asc
),
missing_revenue as
(
select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.order_date is null and o.status= 'Delivered'
group by Month
order by Month asc
)
select
(select sum(Revenue_excluding_GST) from dated_revenue) +
(Select sum(Revenue_excluding_GST)from missing_revenue) as total_revenue;
-- 390,109.22 (one cent from 390,109.21, caused by rounding each month)


-- ============================================================
-- 7. Repeat customers
-- ============================================================
-- Customers with more than one Delivered order (known and unknown customers together).
-- having filters groups, the way where filters rows.
select customer_id, count(*)
from orders_staging2
where status = 'Delivered'
group by 1
having count(*)>1
order by 2;
-- 498 customers

-- Known customers only
select customer_id, count(*)
from orders_staging2
where status = 'Delivered' and customer_status = 'Known Customer'
group by 1
having count(*)>1
order by 2;
-- 494 customers ordered more than once

select customer_id, count(*)
from orders_staging2
where status = 'Delivered' and customer_status = 'Known Customer'
group by 1
having count(*)=1;
-- 77 customers ordered exactly once

-- Share of repeat customers: the numbers are typed in from the two results above.
SELECT ROUND((494 / (494 + 77)) * 100, 2) AS repeat_customer_percentage;
-- 86.51%

-- Same result, calculated from the data. (The join without "on" pairs every row with
-- every row. It works because of count(distinct ...), but the first version is simpler.)
with morethanone as
(
select customer_id, count(*)
from orders_staging2
where status = 'Delivered' and customer_status = 'Known Customer'
group by 1
having count(*)>1
order by 2
),
exactlyone as (
select customer_id, count(*)
from orders_staging2
where status = 'Delivered' and customer_status = 'Known Customer'
group by 1
having count(*)=1
)
select round(count(distinct m.customer_id)/(count(distinct m.customer_id)+count(distinct e.customer_id)) *100 ,2)as repeat_customer_percentage
from morethanone m
JOIN exactlyone e;

-- Customers with the most Delivered orders (limit 2 because two customers tie)
select customer_id, count(*)
from orders_staging2
where status ='Delivered'and customer_status = 'Known Customer'
group by 1
order by 2 desc
limit 2;
-- C0402 and C0329, 11 orders each
-- Note: the data is synthetic, so the high repeat rate is not a real-world finding.


-- ============================================================
-- 8. Top 3 products per year
-- ============================================================
-- Revenue per product per year. Unknown products and NULL dates are left out.
select p.product_id, p.product_name, year(o.order_date) as Year, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
join products_staging p
on p.product_id=oi.product_id
where o.status='Delivered' and oi.product_status = 'Known Product' and o.order_date is not null
group by Year, p.product_name, p.product_id
order by Year asc,4 desc;

-- Rank the products inside each year. partition by Year restarts the ranking every year.
with good_year as
(
select p.product_id, p.product_name, year(o.order_date) as Year, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
join products_staging p
on p.product_id=oi.product_id
where o.status='Delivered' and oi.product_status = 'Known Product' and o.order_date is not null
group by Year, p.product_name, p.product_id
order by Year asc,3 desc
)
select *, dense_rank() over (partition by Year order by Revenue_excluding_GST desc) as ranking
from good_year
order by ranking asc;

-- Keep only the top 3 per year. A second CTE is needed, because we cannot
-- filter on "ranking" in the same query that creates it.
with good_year as
(
select p.product_id, p.product_name, year(o.order_date) as Year, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
join products_staging p
on p.product_id=oi.product_id
where o.status='Delivered' and oi.product_status = 'Known Product' and o.order_date is not null
group by Year, p.product_name, p.product_id
order by Year asc,3 desc
),
good_company as
(
select *, dense_rank() over (partition by Year order by Revenue_excluding_GST desc) as ranking
from good_year
order by ranking asc
)
select *
from good_company
where ranking<=3;
-- 9 rows. Number one: 2024 Headlamp (8,347.44), 2025 Manuka Honey 500g (14,278.49),
-- 2026 NZ Map Poster (7,071.26). 2026 is a partial year (to 17 September).


-- ============================================================
-- 9. How much revenue rests on data problems?
-- ============================================================
-- Revenue (Delivered, excluding GST) affected by each problem found in cleaning.

-- Orders with an unknown customer
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join order_items_staging oi
on o.order_id=oi.order_id
where o.status= 'Delivered' and o.customer_status= 'Unknown Customer'
;
-- 5,863.92

-- Items with an unknown product
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and oi.product_status= 'Unknown Product'
;
-- 2,922.28

-- Orders with a NULL date
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' AND o.order_date IS NULL
;
-- 695.25

-- Each amount as a share of the 390,109.21 total (numbers typed in from the results above)
select
  round(5863.92 / 390109.21 * 100, 1) as unknown_customer_pct,
  round(2922.28 / 390109.21 * 100, 1) as unknown_product_pct,
  round(695.25  / 390109.21 * 100, 1) as null_date_pct;
-- 1.5, 0.7, 0.2

select
  round(5863.92 + 2922.28 + 695.25, 2) as total_affected,
  round((5863.92 + 2922.28 + 695.25) / 390109.21 * 100, 1) as total_affected_pct;
-- 9,481.45 = 2.4% of the revenue

-- The three amounts can only be added if no item sits in two groups. Check each pair.
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST, count(*)
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and oi.product_status= 'Unknown Product' and o.customer_status= 'Unknown Customer'
;
-- NULL, 0 (unknown product and unknown customer)

select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST, count(*)
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and o.order_date is null and o.customer_status= 'Unknown Customer'
;
-- NULL, 0 (NULL date and unknown customer)

select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST, count(*)
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and o.order_date is null and oi.product_status= 'Unknown Product'
;
-- NULL, 0 (NULL date and unknown product)
-- No overlap, so the total of 9,481.45 (2.4%) is valid.

-- Message for the stakeholder:
-- Delivered revenue excluding GST is 390,109.21, and the total itself is reliable.
-- About 2.4% of it (9,481.45) rests on records with missing customers, products or dates,
-- so the revenue by region, category and month is slightly understated.
-- 31 items with an impossible quantity could not be priced, so the true total may be a little
-- higher by an amount we can't measure.
-- Recommendation: ask the data owners why 30 customers and 10 products are missing from the source files.


-- ============================================================
-- 10. Payment methods
-- ============================================================
-- Number of orders per payment method
select payment_method, count(*)
from orders_staging2
group by payment_method
;
-- Credit Card 1082, Afterpay 590, PayPal 346, Bank Transfer 332, NULL 50 (not recorded)

-- Check: the counts add up to the 2400 orders
with a as
(
select payment_method, count(*) as c
from orders_staging2
group by payment_method
)
select sum(c) from a;
-- 2400

-- Share of orders. sum(ordercount) over () gives the column total, so no typed number is needed.
with shareorder as
(
select payment_method, count(*) as ordercount
from orders_staging2
group by payment_method
)
select *, round(ordercount/sum(ordercount)over ()*100,1) as share_per
from shareorder
group by 1;
-- Credit Card 45.1%, Afterpay 24.6%, PayPal 14.4%, Bank Transfer 13.8%, NULL 2.1%

-- Delivered revenue by payment method
select o.payment_method, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered'
group by 1
;
-- Credit Card 175,805.20, Afterpay 98,298.96, Bank Transfer 54,628.69, PayPal 54,143.30, NULL 7,233.07

-- Check: the five amounts add up to the total revenue
with a as
(
select o.payment_method, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered'
group by 1
)
select sum(Revenue_excluding_GST)
from a;
-- 390,109.22 (one cent of rounding from 390,109.21)
