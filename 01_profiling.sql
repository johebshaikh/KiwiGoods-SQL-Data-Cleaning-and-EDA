-- ============================================================
-- KiwiGoods: Step 1, Setup and Data Profiling
-- ============================================================
-- Goal: look at the raw data and find every problem BEFORE changing anything.
-- Nothing in this file changes the data, except the staging copies at the start.
--
-- Raw tables (imported as text, one per CSV file):
--   raw_customers (622 rows), raw_products (36), raw_orders (2430), raw_order_items (4640)
-- Tip: always import every column as text, then compare the row count with the file.
-- The wizard silently drops rows that do not fit a number type.

-- Check the raw import: expect 4640 rows
select count(*)
from raw_order_items;


-- ============================================================
-- 1. Staging copies
-- ============================================================
-- We never clean the raw tables. We copy each one and clean the copy.
-- "like" copies the structure, "insert ... select" copies the data.

create table customers_staging
like raw_customers;

insert into customers_staging
select *
from raw_customers;
-- 622 rows

create table products_staging
like raw_products;

insert into products_staging
select *
from raw_products;
-- 36 rows

create table orders_staging
like raw_orders;

insert into orders_staging
select *
from raw_orders;
-- 2430 rows

create table order_items_staging
like raw_order_items;

insert into order_items_staging
select *
from raw_order_items;
-- 4640 rows

show tables;


-- ============================================================
-- 2. CUSTOMERS: profiling
-- ============================================================

-- 2.1 Is customer_id unique?
-- 622 rows but fewer distinct IDs means some customers appear twice.
select count(customer_id)
from customers_staging;

select count(distinct(customer_id))
from customers_staging;
-- 600 distinct IDs, so 22 extra rows

-- Number every row inside each group of identical rows.
-- Row number 1 is the first copy, 2 or more are duplicates.
select *,
row_number() over (partition by customer_id, first_name, last_name, email, phone, city, region, signup_date, loyalty_member) as row_num
FROM customers_staging;

-- A CTE lets us filter on row_num. We keep only the duplicates.
with duplicate_cte As
(
select *,
row_number() over (partition by customer_id, first_name, last_name, email, phone, city, region, signup_date, loyalty_member) as row_num
FROM customers_staging
)
select *
from duplicate_cte
where row_num >1;
-- 22 duplicate rows, all identical copies

-- 2.2 City: spelling problems
-- A plain distinct ignores upper and lower case, so it hides some differences.
select distinct(city)
from customers_staging
order by 1;
-- 18 values, with trailing spaces (for example 'Auckland ') and abbreviations

-- collate utf8mb4_bin makes the comparison case-sensitive, so AUCKLAND and auckland show up.
select distinct city collate utf8mb4_bin
from customers_staging
order by 1;
-- 27 values (32 stored spellings once trailing spaces are counted too)

-- Abbreviations used instead of city names
select city, count(city) as row_found
from customers_staging
where city in ('AKL', 'CHCH', 'WLG')
group by 1 ;
-- AKL 4, CHCH 3, WLG 6 = 13 rows (before removing duplicates)

-- 2.3 Blank values: region and email
-- A missing value can be a real NULL or an empty text (''). Check both separately.
select *
from customers_staging
where region is null;
-- 0 real NULLs

select region, count(region) as blank_region
from customers_staging
where region is null or region =''
group by 1;
-- 73 blank regions (empty text)

select *
from customers_staging
where email is null;
-- 0 real NULLs

select email, count(email) as blank_email
from customers_staging
where email is null or email =''
group by 1;
-- 46 blank emails (empty text)

-- 2.4 Emails that are not valid
-- A valid email contains an @ sign.
select *
from customers_staging
where email not like '%@%'
and email != '';
-- 23 rows, all written like "name at example.co.nz" instead of "name@example.co.nz"

-- Extra check: emails that contain upper-case letters (needs the case-sensitive collate)
select count(*)
from customers_staging
where email <> ''
and email collate utf8mb4_bin <> lower(email);

-- 2.5 loyalty_member should only be Yes or No
select distinct (loyalty_member) collate utf8mb4_bin
from customers_staging;
-- 11 spellings: Y, y, Yes, yes, TRUE, N, n, No, no, FALSE and a blank

select *
from customers_staging
where loyalty_member = '' or
loyalty_member is null;
-- 24 blank rows, all empty text

-- 2.6 signup_date has two formats
select signup_date
from customers_staging
where signup_date like '%/%';
-- 540 rows, written day/month/year (NZ style), for example 13/03/2024

select signup_date
from customers_staging
where signup_date like '%-%';
-- 82 rows, written year-month-day, for example 2024-03-13

select count(signup_date)
from customers_staging;
-- 622 = 540 + 82, so every row uses one of the two formats

-- Proof that the slash dates are day-first: a first number above 12 cannot be a month.
select signup_date
from customers_staging
where signup_date like '%13/%';

-- 2.7 phone: four formats
select distinct(phone)
from customers_staging;
-- plain 0214108261, with +64, with dashes, with spaces

select phone
from customers_staging
where phone like '+64%';
-- 28 rows with +64

select phone
from customers_staging
where phone like '%-%';
-- 33 rows with dashes

select phone
from customers_staging
where phone like '% %';
-- 32 rows with spaces
-- Standard chosen: plain digits starting with 0


-- ============================================================
-- 3. ORDERS: profiling
-- ============================================================

-- 3.1 status
select distinct(status)
from orders_staging;
-- Only 4 values show, but case differences are hidden.

select distinct status collate utf8mb4_bin
from orders_staging;
-- 10 values: the 4 proper ones plus wrong spellings (these are fixed in the cleaning script)

-- 3.2 payment_method
select distinct(payment_method)
from orders_staging;
-- 6 values, including NULL and blank

select *
from orders_staging
where payment_method is null ;
-- 24 real NULLs (the file had the word NULL, which the import turned into real NULLs)

select *
from orders_staging
where payment_method ='' ;
-- 26 blank rows (empty text)

-- Difference: NULL means nothing is stored. The text 'NULL' is four letters stored as normal text.
-- "is null" finds the first, "= 'NULL'" finds the second.

-- 3.3 order_date has two formats
select order_date
from orders_staging
where order_date like '%/%';
-- 2128 rows, day/month/year, for example 25/07/2026

select order_date
from orders_staging
where order_date like '%-%';
-- 302 rows, year-month-day, for example 2024-11-13

select count(*)
from orders_staging;
-- 2430 = 2128 + 302

-- 3.4 Impossible dates
-- min and max on a text column sort like a dictionary, so they give wrong answers here.
select min(order_date), max(order_date)
from orders_staging;
-- '01/01/2024','31/12/2025' is wrong: 2026 dates exist, but text sorts them differently

select order_date
from orders_staging
where order_date like '%2030%';
-- 8 rows with the year 2030

select order_date
from orders_staging
where order_date like '%2027%';

select order_date
from orders_staging
where order_date like '%2028%';

select order_date
from orders_staging
where order_date like '%2029%';
-- 2027 to 2029: 0 rows each

-- 3.5 Duplicate orders
select order_id, count(*)
from orders_staging
group by order_id
having count(*) > 1;
-- 30 order IDs appear twice

-- 3.6 Orders whose customer does not exist
-- A left join keeps every order. If no customer is found, the customer columns are NULL.
select *
from orders_staging o
left join customers_staging c
on o.customer_id=c.customer_id;
-- 2529 rows, not 2430: the duplicate customers match twice, so some orders appear twice

select c.customer_id,o.customer_id
from orders_staging o
left join customers_staging c
on o.customer_id=c.customer_id
where c.customer_id is null;
-- 35 orders with no matching customer (decision: keep and flag them in the cleaning step)


-- ============================================================
-- 4. ORDER ITEMS: profiling
-- ============================================================

-- 4.1 quantity
select distinct(quantity) collate utf8mb4_bin
from order_items_staging
order by 1;
-- 9 values. Normal quantities are 1 to 4. Wrong values: 0, -1, -2, 500, 999

select *
from order_items_staging
where quantity = 0;
-- 10 rows

select *
from order_items_staging
where quantity = -1;
-- 9 rows

select *
from order_items_staging
where quantity = -2;
-- 6 rows

select *
from order_items_staging
where quantity in (-1,-2,0)
order by quantity;

select *
from order_items_staging
where quantity in (500, 999)
order by quantity;
-- 6 rows (3 with 500, 3 with 999). The prices look normal, so the quantity was mistyped.
-- Decision: set all 31 wrong values to NULL and keep the rows, so revenue is not lost.

-- Could a negative quantity be a legitimate return? Test it against the order status.
select o.quantity,os.status
from order_items_staging o
left join orders_staging os
on o.order_id=os.order_id
where o.quantity < 0
order by o.quantity;
-- 16 rows (15 items, one order is duplicated). Only 2 belong to Returned orders,
-- most are Delivered, so negatives are errors, not returns.

-- 4.2 Items whose product does not exist
select max(product_id), min(product_id)
from order_items_staging;

select max(product_id), min(product_id)
from products_staging;

select *
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id
where p.product_id is null;
-- 40 items with product IDs that are not in the product table (P09x)

-- 4.3 Blank sale prices
select unit_price_at_sale
from order_items_staging
where unit_price_at_sale is null;
-- 0 real NULLs

select *
from order_items_staging
where unit_price_at_sale = '';
-- 120 blank (empty text). They can be filled from the product price.

-- Can every blank be filled? Check that none of them belongs to an unknown product.
select *
from order_items_staging oi
left join products_staging p
on oi.product_id=p.product_id
where oi.unit_price_at_sale ='' and p.product_id is null;
-- 0 rows, so all 120 can be filled


-- ============================================================
-- 5. PRODUCTS: profiling
-- ============================================================

-- 5.1 Prices written with a $ sign
select * from products_staging where unit_price like '%$%';
-- 12 rows

-- 5.2 category spellings
select distinct(category)
from products_staging;
-- 8 values with a plain distinct

select distinct(category) collate utf8mb4_bin
from products_staging
order by 1;
-- 10 values. Wrong ones: 'Home and Kitchen', 'Outdoor and Sport', 'food & drink',
-- 'gifts & souvenirs', 'Gifts and Souvenirs'. Target: 5 categories.

-- 5.3 Blank cost_price
select *
from products_staging
where cost_price ='';
-- 3 rows (empty text)

select *
from products_staging
where cost_price is Null;
-- 0 real NULLs
-- Decision: set them to NULL, not 0, because 0 would claim the product costs nothing.
