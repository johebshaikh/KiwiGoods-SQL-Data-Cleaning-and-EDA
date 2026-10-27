-- ============================================================================
-- KIWIGOODS | SQL DATA CLEANING & EXPLORATORY DATA ANALYSIS
-- ============================================================================
-- Database: MySQL 8+ (window functions and common table expressions)
-- Project workflow: raw data exploration -> staging -> cleaning -> EDA
--
-- Source tables: raw_customers, raw_products, raw_orders, raw_order_items
-- Working tables: customers_staging, customers_staging2, products_staging,
--                 orders_staging, orders_staging2, order_items_staging
--
-- Reading guide:
--   1. The SQL statements below are preserved from the original analysis.
--   2. SELECT statements include exploratory checks and validation queries.
--   3. CREATE, INSERT, UPDATE, ALTER and DELETE statements modify tables;
--      review before running. This is a working analysis log, not an
--      idempotent script designed for repeated execution in one pass.
--   4. Row counts and revenue figures in comments are recorded observations,
--      not independently re-executed results.
--   5. GST-exclusive revenue uses GST-inclusive sale price / 1.15.
--   6. Data-quality categories may overlap; do not sum their revenue impacts
--      as though they represent distinct transactions.
--
-- IMPORTANT: Presentation-only edit. No original SQL statements were changed.
-- ============================================================================

-- ============================================================================
-- 00 | INITIAL DATA EXPLORATION
-- ============================================================================

select count(*)
from raw_order_items
;


-- ============================================================================
-- 01 | CREATE WORKING STAGING TABLES
-- Copy raw source tables into staging tables so cleaning does not overwrite raw data.
-- ============================================================================
-- Step 6: staging copies
-- Customer Staging
create table customers_staging
like raw_customers;

insert into customers_staging
select *
from raw_customers;

select *
from customers_staging;

-- 622 records

-- product Staging
create table products_staging
like raw_products;

insert into products_staging
select *
from raw_products;

select *
from products_staging;

-- 36 records

-- orders Staging

create table orders_staging
like raw_orders;

insert into orders_staging
select *
from raw_orders;

select *
from orders_staging;
-- 2430 records

-- orders Items Staging
create table order_items_staging
like raw_order_items;

insert into order_items_staging
select *
from raw_order_items;

select *
from order_items_staging;

-- 4640 records

show tables;

select count(customer_id)
from customers_staging;

select distinct(customer_id)
from customers_staging;

select count(distinct(customer_id))
from customers_staging;

-- Customer IDs that appear more than once, with how many times

select *,
row_number() over (partition by customer_id, first_name, last_name, email, phone, city, region, signup_date, loyalty_member) as row_num
FROM customers_staging;

with duplicate_cte As
(
select *,
row_number() over (partition by customer_id, first_name, last_name, email, phone, city, region, signup_date, loyalty_member) as row_num
FROM customers_staging
)
select *
from duplicate_cte
where row_num >1;


-- ============================================================================
-- 02 | DATA PROFILING AND QUALITY CHECKS
-- Explore duplicates, formatting inconsistencies, missing values, and orphan IDs.
-- ============================================================================
-- Question 3: the city column
-- Look at the city column in customers_staging.

-- Your query to list the distinct values.
-- What is wrong with them, in your own words.
-- How many different spellings of "Auckland" can you find?

select distinct(city)
from customers_staging
order by 1
;
-- 18 rows returned and auckland has three names

-- n MySQL ignores upper and lower case, so Auckland, AUCKLAND and auckland look like one value in our list.
-- Our three Auckland spellings (AKL, Auckland, Auckland ) are not the full set.

-- below query returns exact distinct values for alphabets if there is any upper or lower case used

select distinct city collate utf8mb4_bin
from customers_staging
order by 1;

-- Question 4: abbreviations
-- Count the rows that use an abbreviation instead of a city name. Write a query for AKL, CHCH and WLG and tell me:

-- How many rows it returns in total.

-- checking for AKL

select city, count(city) as row_found
from customers_staging
where city = 'AKL';

-- return 4 records

-- checking for CHCH

select city, count(city) as row_found
from customers_staging
where city = 'CHCH';

-- return 3 records

-- checking for WLG

select city, count(city) as row_found
from customers_staging
where city = 'WLG'
group by city;

-- return 6 records

-- The count for each abbreviation separately, if you can get it in one query.
select city, count(city) as row_found
from customers_staging
where city in ('AKL', 'CHCH', 'WLG')
group by 1 ;

-- 13 records in total (before removing duplicates)

-- Question 5: blank values in customers

-- Look at region and email in customers_staging.

select *
from customers_staging;
-- first checking for null

select *
from customers_staging
where region is null;

-- zero nulls

-- How many rows have a blank region?

select *
from customers_staging
where region is null or region ='';

-- or

select region, count(region) as blank_region
from customers_staging
where region is null or region =''
group by 1;

-- 73 blank regions

-- How many rows have a blank email?
-- first checking for null

select *
from customers_staging
where email is null;
-- zero nulls

select *
from customers_staging
where email is null or email ='';

-- or

select email, count(email) as blank_region
from customers_staging
where email is null or email =''
group by 1;

-- 46 blank emails

select count(*) from customers_staging where region is null;
select count(*) from customers_staging where region = '';

-- Question 6: invalid and inconsistent emails
-- Tell me:

select*
from customers_staging;

select*
from customers_staging
where customer_id in ('C0034','C0534');

select *
from customers_staging
where email not like '%@%'
and email != '';
-- 23 rows returned they should look like xyz@abc.com

-- EXTRA METHOD
-- 1. Emails with no @ sign (ignoring blank emails)
select email
from customers_staging
where email != ''
and email not like '%@%';

-- 2. Emails that contain uppercase letters.
-- The default comparison ignores case, so we add collate to make it case-sensitive.
select email
from customers_staging
where email != ''
and email collate utf8mb4_bin <> lower(email);

-- Counts only (change select email to select count(*))
select count(*)
from customers_staging
where email != ''
and email not like '%@%';

select count(*)
from customers_staging
where email <> ''
and email collate utf8mb4_bin <> lower(email);

select*
from customers_staging
where customer_id in ('C0034','C0534');

select *
from customers_staging
where email not like '%@%'
and email != '';
-- 23 rows returned they should look like xyz@abc.com

-- Hint if you need one: like '%@%' and not like '%@%' test for a character. For part 2,
-- remember what you learned about MySQL's default comparison and case. A query like email <> lower(email)
-- can return 0 rows for the wrong reason, so think about how to make the comparison case-sensitive.

-- Question 7: the orders table
-- for status column
select *
from orders_staging;

select distinct(status)
from orders_staging;

-- it has 4 rows and I can see all of them has first letter capital only delivered has small to updating now

select distinct status collate utf8mb4_bin
from orders_staging;

-- returned 10 rows fixing each now

-- Updating
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

select distinct(status)
from orders_staging;

-- for payment method column

select *
from orders_staging;

select payment_method
from orders_staging;

select distinct(payment_method)
from orders_staging;
-- it has 6 rows including null values

select *
from orders_staging
where payment_method is null ;

-- 24 rows are null

select *
from orders_staging
where payment_method ='' ;

-- 26 rows are blank

-- In one sentence, what is the difference between the text NULL and a real NULL?
-- In SQL, NULL represents a missing, unknown, or inapplicable value (the complete absence of data),
--  whereas REELS NULL is likely a typo or auto-correct for an empty string ('') or a literal string text like 'NULL',
-- which instead represent a known, stored value with zero characters or text

-- Question 8: the two date formats in orders_staging

select order_date
from orders_staging;

-- 25/07/2026 this the one format and the other one is 2024-11-13

-- Dates written day/month/year (with slashes)

select order_date
from orders_staging
where order_date like '%/%';
-- gives 2128 rows

-- Dates written year-month-day (with dashes)
select order_date
from orders_staging
where order_date like '%-%';
-- gives 302

-- Total rows, to check that the two counts add up
select count(*)
from orders_staging;

-- 2430

-- Question 9: impossible dates

select min(order_date), max(order_date)
from orders_staging;

-- '01/01/2024','31/12/2025' but why 2026 is not coming at max

select order_date
from orders_staging
where order_date like '%2030%';

-- 8 record returns
select order_date
from orders_staging
where order_date like '%2027%';

select order_date
from orders_staging
where order_date like '%2028%';

select order_date
from orders_staging
where order_date like '%2029%';

-- for 2027 to 2029 it returend 0 records

-- Question 10: orders with no customer

-- Write a query that finds the orders in orders_staging whose customer_id has no match in customers_staging. Tell me:

select *
from orders_staging;

select *
from customers_staging;

select *
from orders_staging o
left join customers_staging c
on o.customer_id=c.customer_id;

-- 2529 rows returns
select c.customer_id,o.customer_id
from orders_staging o
left join customers_staging c
on o.customer_id=c.customer_id
where c.customer_id is null;

-- 35 rows has null values that means 35 orders has no customers

-- row is not yet decided yet--

select*
from order_items_staging;

select distinct(quantity)
from order_items_staging;
-- 9 rows

select distinct(quantity) collate utf8mb4_bin
from order_items_staging
order by 1;
-- 9 rows

-- -1 and - 2 value looks wrong how the quantity will go in minus also i feel 0 is also something
-- to think about why the quantity be zero let me check putting where conditio if zero has all zero values

select *
from order_items_staging
where quantity = 0;

-- ok now im sure that zero is also wrong cz all zero quantity has a unit price at sale

-- How many rows have each wrong value? Write the query.

select *
from order_items_staging
where quantity = 0;

-- zero has 10 records

select *
from order_items_staging
where quantity = -1;

-- -1 has 9 records

select *
from order_items_staging
where quantity = -2;

-- -2 has 6 records

select *
from order_items_staging
where quantity in (-1,-2,0)
order by quantity;

select *
from order_items_staging
where quantity in (500, 999)
order by quantity;

-- 6 rows returned and there are 3 500 and 3 999

-- the unit price looks normal has for normal orders but for sure not normla for 999 or 500 quantity

-- also deleting is not an option cz it will impact the revenue however we can replace them to null
--  because that way the data set wont get harm cz if we do correct than on waht base we are going to do we dont have anything.

-- In a real shop, a negative quantity can mean a return or a refund, which would be legitimate data and not an error.
-- Test that idea with a join,

select o.quantity,os.status
from order_items_staging o
left join orders_staging os
on o.order_id=os.order_id
where o.quantity < 0
order by o.quantity;

-- How many rows it returns. (It's a number I can check.) --- 16 rows returned

-- Whether those rows belong to orders with the status Returned. If negative quantities meant returns,
-- you'd expect almost all of them there.

-- I can only see one negative value is returned else is either shipped or delivered but most of them is delivered

-- What that tells you: should the negative quantities be kept, or set to NULL?
-- It should be kept null cz negative order is delivered for lot of order that is something which does not make any sense

-- Question 12: items with no product
select *
from order_items_staging;

select max(product_id), min(product_id)
from order_items_staging;

select *
from products_staging;

select max(product_id), min(product_id)
from products_staging;

select *
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id;

-- return 4640 rows
select *
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id
where p.product_id is null;

-- 40 rows P094,P099,P093 - three of the unmatched

-- each product has there unique id when it comes for who erans most then cz of the null value like whatever oder s placed again the product is missing in the main product table that means will not get accurate value and the analsyis will go wrong.

-- Question 13: the loyalty_member column

select *
from customers_staging;

select distinct(loyalty_member)
from customers_staging;

select distinct (loyalty_member) collate utf8mb4_bin
from customers_staging;

-- 11 rows returned -- what think here is there should be only Yes and No else should be repalce to this however flase and empty should be update as well
-- not sure what it should be considered as we can see in further investigation or I beliver flase should be replace as NO and true should be replaced as Yes
-- only thing to be worried is null

select *
from customers_staging
where loyalty_member = '' or
loyalty_member is null;

-- 24 rows returned -- all of them are empty we can replace to null

-- Question 14: the signup_date column

select *
from customers_staging;

select signup_date
from customers_staging;

select signup_date
from customers_staging
where signup_date like '%/%';

-- slash format has 540 rows
-- it is a important format as nz ppl recognise these  format unlike USA Eurpoe etc.

select signup_date
from customers_staging
where signup_date like '%-%';

-- dash format has 82 rows returns

select count(signup_date)
from customers_staging;

-- adds up to exact number

select signup_date
from customers_staging
where signup_date like '%13/%';

-- Question 15: the phone column
select *
from customers_staging;

select distinct(phone)
from customers_staging;

-- +64214653004,0214108261,021-187-9784 I can see these three formats

select phone
from customers_staging
where phone like '+64%';

-- + sign has 28 rows

select phone
from customers_staging
where phone like '%-%';

-- dash has 33 rows

select phone
from customers_staging
where phone like '% %';

-- spaces one has 32 rows
-- As i can see lot of number starts with zero i would prefer that method isnatd of dash and +

-- Question 16: blank prices in order_items
-- How many rows are blank? Check both NULL and empty text, separately.

select *
from order_items_staging;

select unit_price_at_sale
from order_items_staging
where unit_price_at_sale is null;
-- No null values

select *
from order_items_staging
where unit_price_at_sale = '';
-- 120 empty values

-- Can these blanks be filled from somewhere else in the data? If yes, from where?

-- I dont think so but as you given a hint tha beans yes from prodct stageing abel through unt price

-- Does it matter that some rows might have no source to fill from? Think back to the 40 items with no matching product.
select *
from products_staging;

select *
from order_items_staging oi
left join products_staging p
on oi.product_id=p.product_id
where oi.unit_price_at_sale ='' and p.product_id is null;

-- zero records

-- Question 17: the products table

select*
from products_staging;

select distinct(category)
from products_staging;

-- return 8 rows

select distinct(category) collate utf8mb4_bin
from products_staging
order by 1;

-- total 10 rows

-- Which spellings are wrong? How would you fix them with Alex’s like method?
-- Write the pattern you’d use for the “Home” category as an example.

-- -- I am not running this at this moment

select *
from products_staging
where category like 'Home%';

update products_staging
set category =  'Home & Kitchen'
where category like 'Home%';

-- as I can see Gifts and Souvenirs can be replace or using like with Gifts & Souvenirs so asHome and Kitchen with Home & Kitchen,
-- Outdoor and Sport with  Outdoor & Sport, food & drink with Food & Drinkand  gifts & souvenirs with Gifts & Souvenirs therefore total will be 5 records

-- How many products have a blank cost_price? Check both NULL and empty text, separately.

select *
from products_staging;

select *
from products_staging
where cost_price ='';
-- 3 records

select *
from products_staging
where cost_price is Null;
-- returns zero records

select *
from products_staging
where cost_price ='' or cost_price is Null;

-- One decision is also open: for the 3 blank cost_price rows, can a cost be found anywhere else in the data?
-- And if not, what should the value be: NULL, 0 or something else? Give me your choice with one sentence of reasoning.
-- Think about what happens to a profit calculation if you put 0.

-- costprice cannot be found anywhere else and I beleive we can put null instead of zero beacuse if
-- e put zero thta means one product with a unit price where cost price become zero
-- than it is not correct we are saying we make that product with zero cost and deciding unit price based on whta ?

select order_id, count(*) from orders_staging group by order_id having count(*) > 1;

-- returned 30 rows
select * from products_staging where unit_price like '%$%';

-- returned 12 rows

select count(*) from orders_staging;

-- 2430


-- ============================================================================
-- 03 | DATA CLEANING AND STANDARDIZATION
-- Remove duplicate records, standardize fields, convert data types, and flag unmatched IDs.
-- ============================================================================
-- Day 2: Cleaning

-- Question 1: create the second staging table

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

select *
from customers_staging2;

INSERT customers_staging2
select *,
row_number() over (partition by customer_id, first_name, last_name, email, phone, city, region, signup_date, loyalty_member)
from customers_staging;

select *
from customers_staging2;
-- 622

SELECT *
FROM customers_staging2
where row_num >1;
-- there 22 duplicates

delete
from customers_staging2
where row_num > 1;

-- deleted

select count(*) from customers_staging2;

-- 600 records

select customer_id, count(*)
from customers_staging2
group by customer_id
having count(*) > 1;

-- zero records now

-- Question 2: the same job for orders is still open.

select*
from orders_staging;
-- 2430 records

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

select *
from orders_staging2;

-- 2430 records

select *
from orders_staging2
where row_num >1;

-- there are 30 duplicates

delete
from orders_staging2
where row_num >1;

-- zero duplicates
select*
from orders_staging2;

-- after delete the row count is 2400

-- Question 3: do the other two tables have duplicates?

select *
from order_items_staging;

# First let's check for duplicates

select *,
row_number() over (partition by item_id, order_id, product_id, quantity, unit_price_at_sale) as row_num
from order_items_staging;

-- Creating a CTE to check the rank which is greater than 2 tht means whatever is greater than 1 is a duplicate and we can remove that.

with duplicate_cte As
(
select *,
row_number() over (partition by item_id, order_id, product_id, quantity, unit_price_at_sale) as row_num
from order_items_staging
)
select *
from duplicate_cte
where row_num >1;

-- zero duplicates so not creating one more table named order_items_staging2

select *
from products_staging;

# First let's check for duplicates

select *,
row_number() over (partition by product_id, product_name, category, unit_price, cost_price, supplier) as row_num
from products_staging;

-- Creating a CTE to check the rank which is greater than 2 tht means whatever is greater than 1 is a duplicate and we can remove that.

with duplicate_cte As
(
select *,
row_number() over (partition by product_id, product_name, category, unit_price, cost_price, supplier) as row_num
from products_staging
)
select *
from duplicate_cte
where row_num >1;

-- zero duplicates so not creating one more table named oproducts_staging2

-- Question 4: fix the city column

select *
from customers_staging2;

select distinct(city)
from customers_staging2;

select distinct city collate utf8mb4_bin
from customers_staging2
order by 1;

select city, trim(city)
from customers_staging2;

update customers_staging2
set city = trim(city);
-- 11 rows effected

update customers_staging2
set city = 'Auckland'
where city in ('AKL', 'AUCKLAND','auckland');

-- 13 rows effected

update customers_staging2
set city = 'Christchurch'
where city in ('CHCH', 'CHRISTCHURCH','christchurch');

-- 6 rows effeted

update customers_staging2
set city = 'Dunedin'
where city in ('DUNEDIN','dunedin');
-- 2 rows effeted

update customers_staging2
set city = 'Hamilton'
where city in ('hamilton');

-- 3 rows effe ted

update customers_staging2
set city = 'Napier'
where city in ('NAPIER','napier');

-- 3 rows effected

update customers_staging2
set city = 'Nelson'
where city = 'NELSON';

-- 1 row effected

update customers_staging2
set city = 'Tauranga'
where city in ('TAURANGA','tauranga');

-- 3 rows effected

update customers_staging2
set city = 'Wellington'
where city in ('WLG', 'WELLINGTON','wellington');

-- 9 rows efcected
-- 2. Rows where city still has extra spaces
select city, length(city), length(trim(city))
from customers_staging2
where length(city) <> length(trim(city));

-- Question 5: fill the blank region

select *
from customers_staging2;

select region
from customers_staging2;

select *
from customers_staging2
where region is null or region ='';

update customers_staging2
set region = NULL
where region ='';

-- 70 rows effected

select *
from customers_staging2;

select t1.region,t2.region
from customers_staging2 t1
join customers_staging2 t2
on t1.city=t2.city
where t1.region is null
and t2.region is not null;

-- 6610 records returned

update customers_staging2 t1
join customers_staging2 t2
on t1.city=t2.city
set t1.region=t2.region
where t1.region is null
and t2.region is not null;
-- 70 recirds

-- Check: no blank regions should remain

select count(*)
from customers_staging2
where region is null or region = '';

-- 0

select city, region,count(region), count(city)
from customers_staging2
group by city, region
order by city;

-- Question 6: fix loyalty_member is next. In customers_staging2, use Alex’s like method to leave only Yes, No and NULL.
select *
from customers_staging2;

select distinct loyalty_member collate utf8mb4_bin
from customers_staging2;

update customers_staging2
set loyalty_member = 'No'
where loyalty_member in ('no','N','n','FALSE');

-- 264 rows effceted

update customers_staging2
set loyalty_member = 'Yes'
where loyalty_member in ('Y','yes','TRUE','y');
-- 273 rows effected

select count(*)
from customers_staging2
where loyalty_member is null or loyalty_member ='';

-- 23 rows effected

update customers_staging2
set loyalty_member = Null
where loyalty_member = '';

-- 23 effected

select count(*)
from customers_staging2
where loyalty_member = '';
-- zero count

select distinct loyalty_member collate utf8mb4_bin
from customers_staging2;

-- Question 7: blank emails
select *
from customers_staging2;

select *
from customers_staging2
where email ='';
-- 45 rows

select *
from customers_staging2
where email is null ;
-- zero

update customers_staging2
set email= Null
where email ='';

select count(*)
from customers_staging2
where email ='' ;
-- zero count

-- Question 8: the emails with “ at “ instead of “@”

select *
from customers_staging2
where email not like '%@%';

-- Preview: the broken emails next to the repaired version
select email, replace(email, ' at ', '@')
from customers_staging2
where email like '% at %';

-- The fix
update customers_staging2
set email = replace(email, ' at ', '@')
where email like '% at %';

-- Check: no email without an @ should remain (NULL emails are not counted by not like)
select *
from customers_staging2
where email not like '%@%';

-- preview

select count(*) from customers_staging2;                                     -- 600
select count(*) from customers_staging2 where row_num > 1;                   -- 0
select count(*) from customers_staging2 where region is null or region = ''; -- 0
select count(*) from customers_staging2 where email is null;                 -- 45
select count(*) from customers_staging2 where email like '%@ %';             -- 0
select count(*) from customers_staging2 where email like '% at %';           -- 0

-- Question 9: mixed upper and lower case in email

select *
from customers_staging2
;

select email, lower(email)
from customers_staging2;

update customers_staging2
set email = lower(email);

-- 36 records changed

-- Check: any email with an upper-case letter left? (case-sensitive comparison)
select count(*)
from customers_staging2
where email != lower(email);

-- zero

-- Question 10: phone numbers

select phone
from customers_staging2;

select distinct phone
from customers_staging2;

select phone
from customers_staging
where phone like '+64%';

-- + sign has 28 rows

select phone
from customers_staging
where phone like '%-%';

-- dash has 33 rows

select phone
from customers_staging
where phone like '% %';

-- spaces one has 32 rows

select phone,
replace(replace(replace(phone, ' ', ''), '-', ''), '+64', '0')
from customers_staging2
where phone like '% %' or phone like '%-%' or phone like '+64%';

update customers_staging2
set phone = replace(replace(replace(phone, ' ', ''),'-', ''), '+64', '0')
where phone like '% %' or phone like '%-%' or phone like '+64%';

-- 90 rows effected
-- Check: phones that are not 10 characters long

select phone
from customers_staging2
where length(phone) != 10;

-- Question 11: the signup_date column

-- Question 14: the signup_date column

-- changing now

-- Step 1: preview the slash dates (day first), nothing should be NULL

select signup_date, str_to_date(signup_date, '%d/%m/%Y')
from customers_staging2
where signup_date like '%/%';

-- 520 rows

-- Step 2: preview the dash dates (year first), nothing should be NULL

select signup_date, str_to_date(signup_date, '%Y-%m-%d')
from customers_staging2
where signup_date like '%-%';

-- 80 rows

-- Step 3: update the slash dates

update customers_staging2
set signup_date= str_to_date(signup_date, '%d/%m/%Y')
where signup_date like '%/%';

-- 520 rows changed

-- Step 4: update the dash dates

update customers_staging2
set signup_date = str_to_date(signup_date, '%Y-%m-%d')
where signup_date like '%-%';

-- 0 rows changed

-- Step 5: change the column type to a real date
alter table customers_staging2
modify column signup_date date;

-- checking the range

select min(signup_date), max(signup_date)
from customers_staging2;

-- '2023-01-02','2025-09-25'

-- Question 12: payment_method in orders_staging2

select payment_method
from orders_staging2;
-- 2400 records

select payment_method
from orders_staging2
where payment_method is null;
-- there are 24 real null values

select payment_method
from orders_staging2
where payment_method = '';

-- 26 rows

-- now fixing

select payment_method
from orders_staging2;

update orders_staging2
set payment_method = Null
where payment_method = '';

-- 26 rows efected

-- verifying

select payment_method
from orders_staging2
where payment_method = '';
-- zero rows

select payment_method
from orders_staging2
where payment_method is null;

-- 50 rows eff ted

-- Question 13: status in orders_staging2

select *
from orders_staging2;

select distinct status
from orders_staging2;

-- 4 rows returned

select distinct status collate utf8mb4_bin
from orders_staging2
group by status;

-- 4 rows'
-- Cancelled'
-- 'Delivered'
-- 'Returned'
-- 'Shipped'

-- nothing to left because on day 1 we have already fixed it

select status, count(*)
from orders_staging2
group by status;

-- 'Delivered','1931'
-- 'Returned','143'
-- 'Cancelled','172'
-- 'Shipped','154'

-- Question 14: order_date in orders_staging2

select *
from orders_staging2;

select order_date
from orders_staging2;
-- 2400 rows

select order_date
from orders_staging2
where order_date like '%/%';

-- slash format has 2104 rows

select order_date
from orders_staging2
where order_date like '%-%';

-- dash has 296 rows

select order_date
from orders_staging2
where order_date like '%2030%';

-- 8 rows has 2030

update orders_staging2
set order_date = Null
where order_date like '%2030%';

-- 8 rows effcetd

select order_date
from orders_staging2
where order_date is null;
-- 8 rows has null values now

-- converting slash date now

select order_date, str_to_date(order_date, '%d/%m/%Y')
from orders_staging2;

update orders_staging2
set order_date = str_to_date(order_date, '%d/%m/%Y')
where order_date like '%/%';

-- converting dash dates
update orders_staging2
set order_date = str_to_date(order_date, '%Y-%m-%d')
where order_date like '%-%';

-- altering now

alter table orders_staging2
modify column order_date date;

select *
from orders_staging2;

select min(order_date), max(order_date)
from orders_staging2;

-- '2024-01-01','2026-09-17'

-- Question 15: flag the orders with no customer

select customer_id
from customers_staging2
where customer_id is null;

select *
from customers_staging2;

select o.customer_id,c.customer_id
from orders_staging2 o
left join customers_staging2 c
on o.customer_id=c.customer_id
where c.customer_id is null;

alter table orders_staging2
add column customer_status text;

select *
from orders_staging2;

update orders_staging2
set customer_status = 'Known Customer'
where customer_status is Null;

select customer_status, count(*)
from orders_staging2
group by customer_status;

-- 2400 rcords

select o.customer_id,c.customer_id
from orders_staging2 o
left join customers_staging2 c
on o.customer_id=c.customer_id
where c.customer_id is null;

select o.customer_status, c.customer_id
from orders_staging2 o
left join customers_staging2 c
	on o.customer_id=c.customer_id
    where o.customer_status = 'Known Customer' and c.customer_id is null;

update orders_staging2 o
left join customers_staging2 c
	on o.customer_id=c.customer_id
    set o.customer_status = 'Unknown Customer'
    where c.customer_id is null;

select distinct customer_status, count(*)
from orders_staging2
group by customer_status;

select distinct customer_status collate utf8mb4_bin
from orders_staging2;

-- Question 16: quantity in order_items_staging

select *
from order_items_staging;

select distinct(quantity) collate utf8mb4_bin
from order_items_staging
order by 1;

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

alter table order_items_staging
modify column quantity Int;

select distinct(quantity) collate utf8mb4_bin
from order_items_staging
order by 1;

-- NULL'1''2''3''4'

-- Question 17: unit_price in products_staging

select *
from products_staging;

-- checking

select count(*)
from products_staging
where unit_price like '%$%'
;

select unit_price
from products_staging
where unit_price like '%$%'
;

-- fixing preview

select unit_price, replace(unit_price, '$','')
from products_staging
where unit_price like '%$%';

update products_staging
set unit_price= replace(unit_price, '$','')
where unit_price like '%$%';
-- 12 rows effected

-- verify
select count(*)
from products_staging
where unit_price like '%$%'
;

alter table products_staging
modify column unit_price decimal(10,2);
-- 36 rows effected

select min(unit_price) , max(unit_price)
from products_staging;

-- '9.00','159.45'

-- Question 18: category in products_staging

select *
from products_staging;

select distinct category collate utf8mb4_bin
from products_staging;

-- 10 rows returned

-- 'Home and Kitchen','Outdoor and Sport','food & drink','gifts & souvenirs','Gifts and Souvenirs' thesea re wrong spelling

-- Preview

select category
from products_staging
where category like 'Home%';
-- 8 rows returned

update products_staging
set category= 'Home & Kitchen'
where category like 'Home%';

update products_staging
set category = 'Outdoor & Sport'
where category like 'Outdoor%';

update products_staging
set category = 'Food & Drink'
where category like 'Food%';

update products_staging
set category = 'Gifts & Souvenirs'
where category like 'Gifts%';

-- Verify: expect 5 values
select distinct category collate utf8mb4_bin
from products_staging;

-- Question 19: cost_price in products_staging

select *
from products_staging;

select cost_price
from products_staging
where cost_price is null;

select count(*)
from products_staging
where cost_price is null;

-- zero

select count(*)
from products_staging
where cost_price = '';

-- 3

update products_staging
set cost_price = Null
where cost_price = '';
-- 3 row(s) affected Rows matched: 3  Changed: 3  Warnings: 0

alter table products_staging
modify column cost_price decimal(10,2);

-- 36 rows effcetd

select count(*)
from products_staging
where cost_price is Null ;

-- 3

select max(cost_price), min(cost_price)
from products_staging;

-- '82.72','4.38'

-- unit_price_at_sale in order_items_staging
select *
from order_items_staging;

select count(*)
from order_items_staging
where unit_price_at_sale ='';

-- 120

select count(*)
from order_items_staging
where unit_price_at_sale is null;

-- zero

update order_items_staging
set unit_price_at_sale = Null
where unit_price_at_sale ='';

-- 120 effcted

select count(*)
from order_items_staging
where unit_price_at_sale is null;

-- 120

select *
from order_items_staging;
select *
from products_staging;

select oi.unit_price_at_sale,p.unit_price, p.product_id
from order_items_staging oi
join products_staging p
	on oi.product_id=p.product_id
    where oi.unit_price_at_sale is null;
    -- 120 row(s) returned

select t1.unit_price_at_sale, t2.unit_price
from order_items_staging t1
JOIN products_staging t2
ON t1.product_id = t2.product_id
WHERE t1.unit_price_at_sale IS NULL
AND t2.unit_price IS NOT NULL;

update order_items_staging t1
JOIN products_staging t2
ON t1.product_id = t2.product_id
set t1.unit_price_at_sale = t2.unit_price
WHERE t1.unit_price_at_sale IS NULL
AND t2.unit_price IS NOT NULL;

select count(*)
from order_items_staging
where unit_price_at_sale is null;

-- 0

alter table order_items_staging
modify column unit_price_at_sale decimal(10,2);
-- 4640

select max(unit_price_at_sale), min(unit_price_at_sale)
from order_items_staging;
-- '159.45','9.00'

-- Question 21: flag the items with no product

select *
from order_items_staging;

select *
from products_staging;

select o.product_id, p.product_id
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id
where p.product_id is null  ;

-- 40 rows

alter table order_items_staging
add column product_status text;

select *
from order_items_staging;

update order_items_staging
set product_status = 'Known Product'
where product_status is Null;
-- 4640 effected

select o.product_id, p.product_id
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id
where p.product_id is null  ;

select o.product_id, p.product_id
from order_items_staging o
left join products_staging p
on o.product_id=p.product_id
where o.product_status = 'Known Product' and p.product_id is null ;

update order_items_staging o
left join products_staging p
on o.product_id=p.product_id
set o.product_status = 'Unknown Product'
where p.product_id is null;

-- 40 rows

select distinct product_status, count(*)
from order_items_staging
group by 1;

-- 'Known Product','4600'
-- 'Unknown Product','40'

select distinct product_status collate utf8mb4_bin
from order_items_staging;

-- 2 rows
-- Question 22: drop the helper columns

describe customers_staging2;
-- 10
 describe orders_staging2;
-- 8

alter table customers_staging2
drop column row_num;

select *
from customers_staging2;

alter table orders_staging2
drop column row_num;

select *
from orders_staging2;

describe customers_staging2;

-- 9
 describe orders_staging2;
 -- 7


-- ---------------------------------------------------------------------------
-- ANALYSIS 23
-- ---------------------------------------------------------------------------
 -- Question 23: the final check of the four clean tables

 select count(*)
 from customers_staging2;

 -- 600

 select count(*)
 from orders_staging2;
 -- 2400

 select count(*)
 from order_items_staging;
 -- 4640

 select count(*)
 from products_staging;
 -- 36

 describe customers_staging2;
describe orders_staging2;

-- shipping fee should be int

alter table orders_staging2
modify column shipping_fee decimal(10,2);

 select *
  from orders_staging2;

 describe order_items_staging;
  describe products_staging;

  select *
  from orders_staging2;


-- ============================================================================
-- 04 | EXPLORATORY DATA ANALYSIS
-- Analyze Delivered revenue excluding GST, product performance, customer behavior, and data quality.
-- ============================================================================
-- EDA (analysis)


-- ---------------------------------------------------------------------------
-- ANALYSIS 01
-- ---------------------------------------------------------------------------
-- EDA Question 1: the total value of all items

-- step 1
select *
from order_items_staging;

select round(sum(quantity * unit_price_at_sale),2) as Total_value
from order_items_staging;
-- total value of every item is 563804.97  before GST and before looking at order status.

-- step 2
select count(quantity * unit_price_at_sale)as Total_value
from order_items_staging;
-- 4609 beacuse there are 31 null values in quantity


-- ---------------------------------------------------------------------------
-- ANALYSIS 02
-- ---------------------------------------------------------------------------
-- EDA Question 2,

-- Step 1: value by order status

select *
from orders_staging2;
select *
from order_items_staging;

select o.status, round(sum(oi.quantity * oi.unit_price_at_sale),2) as Total_value
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
group by 1;


-- ---------------------------------------------------------------------------
-- ANALYSIS 03
-- ---------------------------------------------------------------------------
-- EDA Question 3,

-- Step 2: remove GST

-- In NZ, shop prices include GST at 15%, so the figures we’ve been adding up still contain tax.
--  Assume unit_price_at_sale is GST-inclusive. Revenue excluding GST is the price divided by 1.15.

select o.status, round(sum(oi.quantity * oi.unit_price_at_sale)/1.15 ,2) as Total_value
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status = 'Delivered'
group by 1;
-- So the iteme delivered with out gst is 390109.21
-- revenue (Delivered, excluding GST) = 390,109.21. The GST in those orders is 448,625.59 minus 390,109.21, which is 58,516.38.
-- so 58,516 is 15% gst.


-- ---------------------------------------------------------------------------
-- ANALYSIS 04
-- ---------------------------------------------------------------------------
-- EDA Question 4: revenue by category

select *
from order_items_staging;
select *
from orders_staging2;
select *
from products_staging;

select p.category,o.status,round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join order_items_staging oi
on oi.order_id=o.order_id
join products_staging p
on p.product_id=oi.product_id
where o.status = 'Delivered'
group by 1
order by Revenue_excluding_GST desc;

-- 'Outdoor & Sport','Delivered','97187.87'
-- 'Food & Drink','Delivered','85785.76'
-- 'Gifts & Souvenirs','Delivered','76114.45'
-- 'Home & Kitchen','Delivered','72183.80'
-- 'Beauty & Care','Delivered','55915.05'


-- ---------------------------------------------------------------------------
-- ANALYSIS 04
-- ---------------------------------------------------------------------------
-- Question 4, Step 3: prove it.
-- Instead of assuming the gap is those items, calculate it directly.
--  Write a query that gives the revenue (Delivered, excluding GST, rounded to two decimals) of the items flagged Unknown Product.

select *
from order_items_staging;
select *
from orders_staging2;

select oi.product_status,o.status, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and oi.product_status= 'Unknown Product'
group by 1;

-- 'Unknown Product','2922.28'


-- ---------------------------------------------------------------------------
-- ANALYSIS 05
-- ---------------------------------------------------------------------------
-- Question 5: revenue by region

-- Step 1

select *
from customers_staging2;
-- custid
select *
from orders_staging2;
-- orid, cutid
select *
from order_items_staging;
-- orderid, product id

select c.region,o.status, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join customers_staging2 c
on c.customer_id=o.customer_id
join order_items_staging oi
on oi.order_id=o.order_id
where o.status='Delivered'
group by 1
order by Revenue_excluding_GST desc;

-- 'Auckland','Delivered','125678.05'
-- 'Wellington','Delivered','70438.14'
-- 'Canterbury','Delivered','50544.37'
-- 'Otago','Delivered','45372.18'
-- 'Bay of Plenty','Delivered','30938.77'
-- 'Waikato','Delivered','28464.42'
-- 'Hawkes Bay','Delivered','14174.62'
-- 'Manawatu-Whanganui','Delivered','9983.96'
-- 'Nelson','Delivered','8650.79'


-- ---------------------------------------------------------------------------
-- ANALYSIS 05
-- ---------------------------------------------------------------------------
-- Question 5, Step 2: reconcile the total.

-- checking the sum of all nine regions
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

-- 384245.30

-- the gap is because of products which is not present in the product category

-- A query that proves it: the revenue (Delivered, excluding GST) of the orders flagged as an unknown customer. Does it equal the gap?

select *
from orders_staging2;
-- orid, cutid
select *
from order_items_staging;

select o.status,o.customer_status,round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join order_items_staging oi
on o.order_id=oi.order_id
where o.status= 'Delivered' and o.customer_status= 'Unknown Customer'
group by 1;

-- 'Delivered','Unknown Customer','5863.92'


-- ---------------------------------------------------------------------------
-- ANALYSIS 06
-- ---------------------------------------------------------------------------
-- EDA Question 6: monthly revenue and the rolling total

-- Step 1:monthly revenue for delivered status excluding gst with not null date values

select *
from order_items_staging oi
join orders_staging2 o
	on oi.order_id=o.order_id
    where o.order_date is not null;

select substring(o.order_date, 1,7) as Month, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
	on oi.order_id=o.order_id
    where o.order_date is not null and o.status= 'Delivered'
    group by Month
    order by Month;

-- total 33 months revnue of the first tow months are '2024-01','13293.17''2024-02','12278.05'

-- Step 2: rolling total

select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
	on oi.order_id=o.order_id
    where o.order_date is not null and o.status= 'Delivered'
    group by Month
    order by Month asc;

with rollling_total as
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
from rollling_total;

-- rolling total for the last month. - '2026-09','5455.69','389413.97'

-- Step 3:Find the Missing Revenue The monthly query excludes orders where order_date IS NULL.

select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
	on oi.order_id=o.order_id
    where o.order_date is null and o.status= 'Delivered'
    group by Month
    order by Month asc;

with rollling_total as
(
select substring(o.order_date, 1,7) as 'Month', round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
	on oi.order_id=o.order_id
    where o.order_date is null and o.status= 'Delivered'
    group by Month
    order by Month asc
)
select Month, Revenue_excluding_GST, sum(Revenue_excluding_GST) over (order by Month)
from rollling_total;

-- NULL,'695.25','695.25'

-- Proving the gap

select round(389413.97+ 695.25,2) as Prove;

-- 390109.22

-- OR

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
    (Select sum(Revenue_excluding_GST)from missing_revenue) as xyz;

-- 390109.22


-- ---------------------------------------------------------------------------
-- ANALYSIS 07
-- ---------------------------------------------------------------------------
-- EDA Question 7: repeat customers

-- 1. How many customers placed more than one Delivered order? Tell me the number.

-- for known customer and unknown customer
select *
from orders_staging2;

select customer_id, count(*)
from orders_staging2
where status = 'Delivered'
group by 1
having count(*)>1
order by 2;

-- 498 customers orderd mor ethan once

-- known customer
select *
from orders_staging2;

select customer_id, count(*)
from orders_staging2
where status = 'Delivered' and customer_status = 'Known Customer'
group by 1
having count(*)>1
order by 2;
-- 494

-- 2. How many customers placed exactly one? Tell me the number, and what percentage of buyers are repeat customers.

select customer_id, count(*)
from orders_staging2
where status = 'Delivered' and customer_status = 'Known Customer'
group by 1
having count(*)=1;

-- 77 customers excaltyly one

-- what percentage of buyers are repeat customers

SELECT ROUND((494 / (494 + 77)) * 100, 2) AS repeat_customer_percentage;
-- 86.51 percentage

-- Or

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

-- Which customer placed the most Delivered orders, and how many?

select customer_id, count(*)
from orders_staging2
where status ='Delivered'and customer_status = 'Known Customer'
group by 1
order by 2 desc
limit 2;

-- 'C0402','11''C0329','11'


-- ---------------------------------------------------------------------------
-- ANALYSIS 08
-- ---------------------------------------------------------------------------
-- EDA Question 8: top 3 products per year

-- 1. Write a query that gives each product’s revenue (Delivered, excluding GST) per year.

select *
from orders_staging2;
-- orderid
select *
from order_items_staging;
-- order id , productod
select *
from products_staging;

-- product id

select p.product_id, p.product_name, year(o.order_date) as Year, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join  orders_staging2 o
	on oi.order_id=o.order_id
join products_staging p
	on p.product_id=oi.product_id
    where o.status='Delivered' and oi.product_status = 'Known Product' and o.order_date is not null
    group by Year, p.product_name, p.product_id
    order by Year asc,4 desc;

-- Rank the products inside each year with dense_rank, using revenue, biggest first.

with good_year as
(
select p.product_id, p.product_name, year(o.order_date) as Year, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join  orders_staging2 o
	on oi.order_id=o.order_id
join products_staging p
	on p.product_id=oi.product_id
    where o.status='Delivered' and oi.product_status = 'Known Product' and o.order_date is not null
    group by Year, p.product_name, p.product_id
    order by Year asc,3 desc
)
select *, dense_rank() over	(partition by Year order by Revenue_excluding_GST desc) as ranking
from good_year
order by ranking asc;

-- Keep only the top 3 per year. Tell me how many rows come back, and the number-one product in each year.

with good_year as
(
select p.product_id, p.product_name, year(o.order_date) as Year, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join  orders_staging2 o
	on oi.order_id=o.order_id
join products_staging p
	on p.product_id=oi.product_id
    where o.status='Delivered' and oi.product_status = 'Known Product' and o.order_date is not null
    group by Year, p.product_name, p.product_id
    order by Year asc,3 desc
),
good_company as
(
select *, dense_rank() over	(partition by Year order by Revenue_excluding_GST desc) as ranking
from good_year
order by ranking asc
)
select *
from  good_company
where ranking<=3;

-- 'P015','Headlamp','2024','8347.44','1''P023','Manuka Honey 500g','2025','14278.49','1''P034','NZ Map Poster','2026','7071.26','1'
-- 'P018','Harakeke Hand Cream','2024','7771.83','2''P016','Dry Bag 20L','2025','9000.86','2''P027','Pinot Noir Vinegar','2026','5379.83','2'
-- 'P034','NZ Map Poster','2024','7487.22','3''P018','Harakeke Hand Cream','2025','7771.83','3''P018','Harakeke Hand Cream','2026','4996.17','3'


-- ---------------------------------------------------------------------------
-- ANALYSIS 09
-- ---------------------------------------------------------------------------
-- EDA Question 9: how much revenue rests on data problems

-- Step 1: Revenue from Unknown Customers

select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from orders_staging2 o
join order_items_staging oi
on o.order_id=oi.order_id
where o.status= 'Delivered' and o.customer_status= 'Unknown Customer'
;
-- 5863.92

-- Step 2: Revenue from Unknown Products
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and oi.product_status= 'Unknown Product'
;
-- 2922.28

-- Step 3: Revenue from NULL Dates

select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' AND o.order_date IS NULL
;
-- 695.25


-- ---------------------------------------------------------------------------
-- ANALYSIS 09
-- ---------------------------------------------------------------------------
-- EDA Question 9, Step 2: the percentages

-- The percentage for each of the three amounts, rounded to one decimal.

-- Each amount as a share of the Delivered revenue (excluding GST)
select
  round(5863.92 / 390109.21 * 100, 1) as unknown_customer_pct,
  round(2922.28 / 390109.21 * 100, 1) as unknown_product_pct,
  round(695.25  / 390109.21 * 100, 1) as null_date_pct;
-- '1.5','0.7','0.2'

-- The three added together, as an amount and as a percentage
select
  round(5863.92 + 2922.28 + 695.25, 2) as total_affected,
  round((5863.92 + 2922.28 + 695.25) / 390109.21 * 100, 1) as total_affected_pct;
-- '9481.45','2.4'

-- Step 3: check that the groups don’t overlap
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST, count(*)
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and oi.product_status= 'Unknown Product' and o.customer_status= 'Unknown Customer'
;

-- Step 3, second pair: unknown customer and NULL date
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST, count(*)
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and o.order_date is null and o.customer_status= 'Unknown Customer'
;
-- NULL,'0'

-- Step 3, last pair: unknown product and NULL date
select round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST, count(*)
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered' and o.order_date is null and oi.product_status= 'Unknown Product'
;
-- NULL,'0'

-- Step 4: what you’d tell the stakeholder

-- Delivered revenue excluding GST is 390,109.21, and the total itself is reliable.
-- About 2.4% of it (9,481.45) rests on records with missing customers, products or dates, so the revenue by region, category and
-- month is slightly understated. 31 items with an impossible quantity could not be priced, so the true total may be a little higher
-- by an amount we can’t measure. I recommend asking the data owners why 30 customers and 10 products are missing from the source files.


-- ---------------------------------------------------------------------------
-- ANALYSIS 10
-- ---------------------------------------------------------------------------
-- EDA Question 10: payment method share

-- Step 1: write a query that gives, for each payment method,
-- the number of orders in orders_staging2, with the biggest first. Tell me all the counts.
select *
from orders_staging2;

select payment_method, count(*)
from orders_staging2
group by payment_method
;

-- 'Credit Card','1082'
-- 'Bank Transfer','332'
-- 'Afterpay','590'
-- 'PayPal','346'
-- NULL,'50'

-- checking if it adds up to 2400
with a as
(
select payment_method, count(*) as c
from orders_staging2
group by payment_method
)
select sum(c) from a;

-- 2400


-- ---------------------------------------------------------------------------
-- ANALYSIS 10
-- ---------------------------------------------------------------------------
-- Question 10, Step 2: the share of orders

select *
from orders_staging2;

with shareorder as
(
select payment_method, count(*) as ordercount
from orders_staging2
group by payment_method
)
select *, round(ordercount/sum(ordercount)over ()*100,1) as share_per
from shareorder
group by 1;


-- ---------------------------------------------------------------------------
-- ANALYSIS 10
-- ---------------------------------------------------------------------------
-- Question 10, Step 3: revenue by payment method

select o.payment_method, round(sum(oi.quantity*oi.unit_price_at_sale)/1.15,2) as Revenue_excluding_GST
from order_items_staging oi
join orders_staging2 o
on oi.order_id=o.order_id
where o.status='Delivered'
group by 1
;

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

-- 390109.22
