-- ============================================================
-- KiwiGoods: Step 2, Data Cleaning
-- ============================================================
-- Goal: fix every problem found in 01_profiling.sql.
-- Method for each problem: check, fix, verify.
-- Rule: preview with a select BEFORE running an update, and read the
-- "rows changed" number to confirm the update did what was expected.
--
-- Order matters:
--   1. remove duplicates first (they inflate joins)
--   2. standardize text (city before region)
--   3. fix blanks and impossible values
--   4. convert data types
--   5. drop helper columns
-- Expected row counts are written next to each step.

-- ============================================================
-- 0. Status fixes made on orders_staging during profiling
-- ============================================================
-- MySQL ignores upper and lower case when comparing text, so these conditions
-- match every spelling (returned, RETURNED, Returned...). Each update writes
-- one correct spelling over all of them.
update orders_staging
set status = 'Returned'
where status = 'returned' and status = 'RETURNED';

update orders_staging
set status = 'Shipped'
where status = 'SHIPPED' and status = 'shipped';

update orders_staging
set status = 'Delivered'
where status ='delivered';

update orders_staging
set status = 'Cancelled'
where status in ('CANCELLED', 'cancelled');

-- Verify: 4 values (case-sensitive check)
select distinct status collate utf8mb4_bin
from orders_staging;


-- ============================================================
-- 1. CUSTOMERS
-- ============================================================

-- 1.1 Remove duplicates
-- MySQL cannot delete from a CTE, so we build a second table that has an
-- extra column (row_num) and delete from that table.
CREATE TABLE `customers_staging2` (
  `customer_id` text,
  `first_name` text,
  `last_name` text,
  `email` text,
  `phone` text,
  `city` text,
  `region` text,
  `signup_date` text,
  `loyalty_member` text,
  `row_num` INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT customers_staging2
select *,
row_number() over (partition by customer_id, first_name, last_name, email, phone, city, region, signup_date, loyalty_member)
from customers_staging;
-- 622 rows

SELECT *
FROM customers_staging2
where row_num >1;
-- 22 duplicates

delete
from customers_staging2
where row_num > 1;

select count(*) from customers_staging2;
-- 600 rows

-- Independent check: no customer ID should appear twice now
select customer_id, count(*)
from customers_staging2
group by customer_id
having count(*) > 1;
-- 0 rows

-- 1.2 City: one spelling per city
-- Remove trailing spaces first
select city, trim(city)
from customers_staging2;

update customers_staging2
set city = trim(city);
-- 11 rows changed

-- Then one update per city. "in (...)" lists the wrong spellings,
-- including the abbreviations AKL, CHCH and WLG.
update customers_staging2
set city = 'Auckland'
where city in ('AKL', 'AUCKLAND','auckland');
-- 13 rows changed

update customers_staging2
set city = 'Christchurch'
where city in ('CHCH', 'CHRISTCHURCH','christchurch');
-- 6 rows changed

update customers_staging2
set city = 'Dunedin'
where city in ('DUNEDIN','dunedin');
-- 2 rows changed

update customers_staging2
set city = 'Hamilton'
where city in ('hamilton');
-- 3 rows changed

update customers_staging2
set city = 'Napier'
where city in ('NAPIER','napier');
-- 3 rows changed

update customers_staging2
set city = 'Nelson'
where city = 'NELSON';
-- 1 row changed

update customers_staging2
set city = 'Tauranga'
where city in ('TAURANGA','tauranga');
-- 3 rows changed

update customers_staging2
set city = 'Wellington'
where city in ('WLG', 'WELLINGTON','wellington');
-- 9 rows changed

-- Verify: 10 values, then no city with extra spaces
select distinct city collate utf8mb4_bin
from customers_staging2
order by 1;

select city, length(city), length(trim(city))
from customers_staging2
where length(city) <> length(trim(city));
-- 0 rows

-- 1.3 Region: fill the blanks from the city
-- Step 1: empty text becomes a real NULL
update customers_staging2
set region = NULL
where region ='';
-- 70 rows changed

-- Step 2: preview. t1 = row with a missing region, t2 = another row of the same city with a region.
-- (Each city belongs to exactly one region, so the match is safe.)
select t1.region,t2.region
from customers_staging2 t1
join customers_staging2 t2
on t1.city=t2.city
where t1.region is null
and t2.region is not null;
-- 6610 rows (one blank row matches many rows of its city, which is normal)

-- Step 3: the fix, copying t2's region into t1
update customers_staging2 t1
join customers_staging2 t2
on t1.city=t2.city
set t1.region=t2.region
where t1.region is null
and t2.region is not null;
-- 70 rows changed

-- Verify: no blank regions, and one region per city
select count(*)
from customers_staging2
where region is null or region = '';
-- 0

select city, region,count(region), count(city)
from customers_staging2
group by city, region
order by city;
-- 10 rows, one region per city

-- 1.4 loyalty_member: only Yes, No or NULL
update customers_staging2
set loyalty_member = 'No'
where loyalty_member in ('no','N','n','FALSE');
-- 264 rows changed

update customers_staging2
set loyalty_member = 'Yes'
where loyalty_member in ('Y','yes','TRUE','y');
-- 273 rows changed

-- Blanks become NULL (unknown), not 'No'
update customers_staging2
set loyalty_member = Null
where loyalty_member = '';
-- 23 rows changed

select distinct loyalty_member collate utf8mb4_bin
from customers_staging2;
-- 3 values: Yes, No, NULL

-- 1.5 Email
-- Blank emails become NULL (there is no other source to fill them from)
update customers_staging2
set email= Null
where email ='';
-- 45 rows changed

-- Emails written "name at example.co.nz": replace the word " at " (with spaces) by @.
-- The spaces around "at" matter, so names such as Patel are not touched.
select email, replace(email, ' at ', '@')
from customers_staging2
where email like '% at %';
-- 23 rows

update customers_staging2
set email = replace(email, ' at ', '@')
where email like '% at %';
-- 23 rows changed

-- Verify: no email without an @ remains
select *
from customers_staging2
where email not like '%@%';
-- 0 rows

-- Emails are stored in lower case
update customers_staging2
set email = lower(email);
-- 36 rows changed

select count(*)
from customers_staging2
where email != lower(email);
-- 0
-- Note: the plain comparison ignores case, so it cannot prove this. The case-sensitive
-- version (email collate utf8mb4_bin <> lower(email)) is the real check.

-- 1.6 Phone: one format, 10 plain digits starting with 0
-- replace() is nested: remove spaces, then dashes, then change +64 to 0.
select phone,
replace(replace(replace(phone, ' ', ''), '-', ''), '+64', '0')
from customers_staging2
where phone like '% %' or phone like '%-%' or phone like '+64%';

update customers_staging2
set phone = replace(replace(replace(phone, ' ', ''),'-', ''), '+64', '0')
where phone like '% %' or phone like '%-%' or phone like '+64%';
-- 90 rows changed

-- Verify: every phone has 10 characters
select phone
from customers_staging2
where length(phone) != 10;
-- 0 rows

-- 1.7 signup_date: two formats, converted one at a time
-- Never run one str_to_date over the whole column: rows in the other format would become NULL.
-- Preview each format first. Nothing should be NULL.
select signup_date, str_to_date(signup_date, '%d/%m/%Y')
from customers_staging2
where signup_date like '%/%';
-- 520 rows (day first)

select signup_date, str_to_date(signup_date, '%Y-%m-%d')
from customers_staging2
where signup_date like '%-%';
-- 80 rows (year first)

update customers_staging2
set signup_date= str_to_date(signup_date, '%d/%m/%Y')
where signup_date like '%/%';
-- 520 rows changed

update customers_staging2
set signup_date = str_to_date(signup_date, '%Y-%m-%d')
where signup_date like '%-%';
-- 0 rows changed: these rows were already in the year-month-day form

-- Change the column from text to a real date
alter table customers_staging2
modify column signup_date date;

select min(signup_date), max(signup_date)
from customers_staging2;
-- '2023-01-02','2025-09-25'

-- 1.8 Drop the helper column (it was only needed to find the duplicates)
alter table customers_staging2
drop column row_num;


-- ============================================================
-- 2. ORDERS
-- ============================================================

-- 2.1 Remove duplicates (same method as customers)
CREATE TABLE `orders_staging2` (
  `order_id` text,
  `customer_id` text,
  `order_date` text,
  `status` text,
  `payment_method` text,
  `shipping_fee` text,
  `row_num` INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

Insert orders_staging2
select *,
row_number() over (partition by order_id, customer_id, order_date, status, payment_method, shipping_fee)
from orders_staging;
-- 2430 rows

select *
from orders_staging2
where row_num >1;
-- 30 duplicates

delete
from orders_staging2
where row_num >1;
-- 2400 rows left

-- 2.2 payment_method: blank (empty text) becomes NULL
update orders_staging2
set payment_method = Null
where payment_method = '';
-- 26 rows changed

select payment_method
from orders_staging2
where payment_method = '';
-- 0 rows

select payment_method
from orders_staging2
where payment_method is null;
-- 50 rows (24 from the file + 26 from this fix)

-- 2.3 status: already clean, because staging2 was filled from the fixed staging table
select distinct status collate utf8mb4_bin
from orders_staging2;
-- 4 values

select status, count(*)
from orders_staging2
group by status;
-- Delivered 1931, Returned 143, Cancelled 172, Shipped 154 = 2400

-- 2.4 order_date
-- First set the 8 impossible dates (year 2030) to NULL, while the column is still text.
-- The row stays, so its revenue is not lost.
update orders_staging2
set order_date = Null
where order_date like '%2030%';
-- 8 rows changed

-- Then convert each format with its own update (day first for the slashes)
select order_date, str_to_date(order_date, '%d/%m/%Y')
from orders_staging2;

update orders_staging2
set order_date = str_to_date(order_date, '%d/%m/%Y')
where order_date like '%/%';
-- 2096 rows changed (2104 slash rows minus the 8 set to NULL)

update orders_staging2
set order_date = str_to_date(order_date, '%Y-%m-%d')
where order_date like '%-%';
-- 0 rows changed: these were already in year-month-day form

alter table orders_staging2
modify column order_date date;

select min(order_date), max(order_date)
from orders_staging2;
-- '2024-01-01','2026-09-17'

-- 2.5 Flag the orders whose customer does not exist (keep them, so revenue is not lost)
alter table orders_staging2
add column customer_status text;

-- Everyone starts as a known customer
update orders_staging2
set customer_status = 'Known Customer'
where customer_status is Null;
-- 2400 rows changed

-- Preview the unmatched orders with a left join
select o.customer_id,c.customer_id
from orders_staging2 o
left join customers_staging2 c
on o.customer_id=c.customer_id
where c.customer_id is null;
-- 35 rows

-- Mark them
update orders_staging2 o
left join customers_staging2 c
on o.customer_id=c.customer_id
set o.customer_status = 'Unknown Customer'
where c.customer_id is null;
-- 35 rows changed

select distinct customer_status, count(*)
from orders_staging2
group by customer_status;
-- Known Customer 2365, Unknown Customer 35

select distinct customer_status collate utf8mb4_bin
from orders_staging2;
-- 2 values

-- 2.6 Drop the helper column
alter table orders_staging2
drop column row_num;

-- 2.7 shipping_fee: money needs cents, so DECIMAL and not INT (INT would round 5.9 to 6)
alter table orders_staging2
modify column shipping_fee decimal(10,2);


-- ============================================================
-- 3. PRODUCTS
-- ============================================================

-- 3.1 Duplicates check: none found, so no second table is needed
with duplicate_cte As
(
select *,
row_number() over (partition by product_id, product_name, category, unit_price, cost_price, supplier) as row_num
from products_staging
)
select *
from duplicate_cte
where row_num >1;
-- 0 rows

-- 3.2 unit_price: remove the $ sign, then convert to a number
select unit_price, replace(unit_price, '$','')
from products_staging
where unit_price like '%$%';

update products_staging
set unit_price= replace(unit_price, '$','')
where unit_price like '%$%';
-- 12 rows changed

select count(*)
from products_staging
where unit_price like '%$%';
-- 0

alter table products_staging
modify column unit_price decimal(10,2);

select min(unit_price) , max(unit_price)
from products_staging;
-- '9.00','159.45'

-- 3.3 category: 10 spellings become 5.
-- like 'Home%' finds every spelling that starts with Home; the update writes one correct name.
update products_staging
set category= 'Home & Kitchen'
where category like 'Home%';
-- 4 rows changed (8 matched)

update products_staging
set category = 'Outdoor & Sport'
where category like 'Outdoor%';
-- 2 rows changed

update products_staging
set category = 'Food & Drink'
where category like 'Food%';
-- 1 row changed

update products_staging
set category = 'Gifts & Souvenirs'
where category like 'Gifts%';
-- 3 rows changed

select distinct category collate utf8mb4_bin
from products_staging;
-- 5 values

-- 3.4 cost_price: blanks become NULL BEFORE the type change
-- (an empty text cannot become a number, and 0 would claim the product costs nothing)
update products_staging
set cost_price = Null
where cost_price = '';
-- 3 rows changed

alter table products_staging
modify column cost_price decimal(10,2);

select count(*)
from products_staging
where cost_price is Null ;
-- 3

select max(cost_price), min(cost_price)
from products_staging;
-- '82.72','4.38'


-- ============================================================
-- 4. ORDER ITEMS
-- ============================================================

-- 4.1 Duplicates check: none found
with duplicate_cte As
(
select *,
row_number() over (partition by item_id, order_id, product_id, quantity, unit_price_at_sale) as row_num
from order_items_staging
)
select *
from duplicate_cte
where row_num >1;
-- 0 rows

-- 4.2 quantity: the 31 impossible values become NULL, then convert to INT
-- Counts per value: 0 = 10, -1 = 9, -2 = 6, 500 = 3, 999 = 3
select quantity, count(*)
from order_items_staging
where quantity in (0,-1,-2,500,999)
group by quantity;

select count(*)
from order_items_staging
where quantity in (0,-1,-2,500,999);
-- 31

update order_items_staging
set quantity = Null
where quantity in (0,-1,-2,500,999);
-- 31 rows changed

alter table order_items_staging
modify column quantity Int;

select distinct(quantity) collate utf8mb4_bin
from order_items_staging
order by 1;
-- NULL, 1, 2, 3, 4

-- 4.3 unit_price_at_sale: fill the blanks from the product price
-- Step 1: empty text becomes a real NULL
update order_items_staging
set unit_price_at_sale = Null
where unit_price_at_sale ='';
-- 120 rows changed

-- Step 2: preview. Each item with a missing price is paired with its product.
select t1.unit_price_at_sale, t2.unit_price
from order_items_staging t1
JOIN products_staging t2
ON t1.product_id = t2.product_id
WHERE t1.unit_price_at_sale IS NULL
AND t2.unit_price IS NOT NULL;
-- 120 rows

-- Step 3: the fix
update order_items_staging t1
JOIN products_staging t2
ON t1.product_id = t2.product_id
set t1.unit_price_at_sale = t2.unit_price
WHERE t1.unit_price_at_sale IS NULL
AND t2.unit_price IS NOT NULL;
-- 120 rows changed

select count(*)
from order_items_staging
where unit_price_at_sale is null;
-- 0

alter table order_items_staging
modify column unit_price_at_sale decimal(10,2);

select max(unit_price_at_sale), min(unit_price_at_sale)
from order_items_staging;
-- '159.45','9.00'

-- 4.4 Flag the items whose product does not exist (keep them, so revenue is not lost)
alter table order_items_staging
add column product_status text;

-- Everyone starts as a known product
update order_items_staging
set product_status = 'Known Product'
where product_status is Null;
-- 4640 rows changed

-- Preview the unmatched items
select o.product_id, p.product_id
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id
where p.product_id is null  ;
-- 40 rows

-- Mark them
update order_items_staging o
left join products_staging p
on o.product_id=p.product_id
set o.product_status = 'Unknown Product'
where p.product_id is null;
-- 40 rows changed

select distinct product_status, count(*)
from order_items_staging
group by 1;
-- Known Product 4600, Unknown Product 40

select distinct product_status collate utf8mb4_bin
from order_items_staging;
-- 2 values


-- ============================================================
-- 5. FINAL CHECK
-- ============================================================
select count(*) from customers_staging2;   -- 600
select count(*) from orders_staging2;      -- 2400
select count(*) from order_items_staging;  -- 4640
select count(*) from products_staging;     -- 36

-- Column counts: customers 9 (row_num dropped), orders 7 (6 original columns + customer_status)
describe customers_staging2;
describe orders_staging2;
describe order_items_staging;
describe products_staging;
