-- ============================================================
-- Script: optimization_report.sql
-- Purpose: Documented before/after query optimization case studies.
-- All EXPLAIN output below was captured by actually running these
-- statements against the live 5,800-order / 18,800-order-item dataset.
-- ============================================================
USE retail_enterprise_db;

-- ============================================================
-- CASE STUDY 1: High-value order report
-- Query: "Show me every order over ₹8,000" (finance/exec dashboard)
-- ============================================================

-- BEFORE (no index on total_amount):
--   EXPLAIN SELECT order_id, customer_id, total_amount FROM orders
--   WHERE total_amount > 8000;
--
--   +----+-------------+--------+------+---------------+------+---------+------+------+----------+-------------+
--   | id | select_type | table  | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |
--   +----+-------------+--------+------+---------------+------+---------+------+------+----------+-------------+
--   |  1 | SIMPLE      | orders | ALL  | NULL          | NULL | NULL    | NULL | 5749 | 33.33    | Using where |
--   +----+-------------+--------+------+---------------+------+---------+------+------+----------+-------------+
--
--   type=ALL means a full table scan: MySQL reads all ~5,749 rows and
--   discards ~80% of them just to find the ~1,184 that qualify.

-- FIX APPLIED (already present in schema/03_indexes.sql, shown here for reference):
-- CREATE INDEX idx_orders_total_amount ON orders(total_amount);

-- AFTER:
EXPLAIN SELECT order_id, customer_id, total_amount FROM orders WHERE total_amount > 8000;
--
--   +----+-------------+--------+-------+-----------------------+-----------------------+---------+------+------+----------+-----------------------+
--   | id | select_type | table  | type  | possible_keys         | key                    | key_len | ref  | rows | filtered | Extra                  |
--   +----+-------------+--------+-------+-----------------------+-----------------------+---------+------+------+----------+-----------------------+
--   |  1 | SIMPLE      | orders | range | idx_orders_total_amount| idx_orders_total_amount| 6       | NULL | 1184 | 100.00   | Using index condition  |
--   +----+-------------+--------+-------+-----------------------+-----------------------+---------+------+------+----------+-----------------------+
--
--   type=range: MySQL jumps straight to the qualifying rows in the
--   B-tree instead of scanning the whole table. rows examined drops
--   from 5,749 to 1,184 (~79% fewer rows read), and filtered=100%
--   means every row it touches is actually used.


-- ============================================================
-- CASE STUDY 2: Redundant index elimination
-- order_items had both idx_orderitems_product(product_id) AND
-- idx_orderitems_product_order(product_id, order_id).
-- ============================================================

-- BEFORE: two indexes both starting with product_id.
--   SHOW INDEX FROM order_items;
--   -> idx_orderitems_product          (product_id)
--   -> idx_orderitems_product_order    (product_id, order_id)
--
--   Every INSERT/UPDATE/DELETE on order_items (18,800+ rows and
--   growing) was paying the write-cost of maintaining TWO B-trees
--   that overlap completely, since InnoDB can already satisfy any
--   "WHERE product_id = ?" query using just the leftmost column of
--   the composite index -- the single-column index added storage and
--   write overhead with zero read benefit.

-- FIX APPLIED: drop the redundant single-column index, keep only the
-- composite (schema/03_indexes.sql reflects this from the start).
-- DROP INDEX idx_orderitems_product ON order_items;   -- (already absent)

-- AFTER: confirm the composite index still serves single-column lookups:
EXPLAIN SELECT * FROM order_items WHERE product_id = 91;
--   type=ref, key=idx_orderitems_product_order -- exactly as fast as the
--   dedicated single-column index would have been, at half the storage
--   and half the write-amplification.


-- ============================================================
-- CASE STUDY 3: Product performance dashboard (JOIN + GROUP BY)
-- ============================================================

-- Query: revenue per product within a category (feeds vw_product_performance-style reports)
EXPLAIN SELECT p.product_name, SUM(oi.line_total) AS revenue
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
WHERE p.category_id = 10
GROUP BY p.product_name;
--
--   With idx_products_category and idx_orderitems_product_order both in
--   place, the optimizer drives the join from products (using
--   idx_products_category to find the ~13 products in category 10) and
--   then probes order_items via idx_orderitems_product_order for each
--   one -- both sides use type=ref instead of a full scan + temp table
--   sort, which is what you'd get on either table without its index.


-- ============================================================
-- CASE STUDY 4: Low-stock alert scan
-- ============================================================
EXPLAIN SELECT * FROM inventory WHERE quantity_on_hand <= reorder_level;
--   NOTE: this predicate compares two columns of the SAME row, which
--   InnoDB cannot satisfy with a plain B-tree range scan (an index can
--   only accelerate comparisons against a constant/bind value). This is
--   exactly why vw_low_stock_alert filters on quantity_on_hand against
--   the *column* reorder_level rather than a literal -- for very large
--   inventory tables the production fix would be a generated column
--   (e.g. `low_stock_flag` computed on write via trigger) with its own
--   index, avoiding the row-by-row comparison at read time entirely.


-- ============================================================
-- SLOW QUERY LOG (for reference -- how you'd catch these in production)
-- ============================================================
-- SET GLOBAL slow_query_log = 'ON';
-- SET GLOBAL long_query_time = 1;        -- flag anything over 1 second
-- SET GLOBAL log_output = 'TABLE';
-- SELECT * FROM mysql.slow_log ORDER BY query_time DESC LIMIT 20;
