-- ============================================================
-- Script: product_sales_analytics.sql
-- Purpose: Product performance + sales trend analytics
-- ============================================================
USE retail_enterprise_db;

-- 1. Best-selling products by units sold
SELECT p.product_id, p.product_name, cat.category_name,
       SUM(oi.quantity) AS units_sold,
       SUM(oi.line_total) AS revenue
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
GROUP BY p.product_id, p.product_name, cat.category_name
ORDER BY units_sold DESC
LIMIT 20;

-- 2. Low-performing products (bottom 20 by revenue, among products with at least 1 sale)
SELECT p.product_id, p.product_name,
       COALESCE(SUM(oi.quantity), 0) AS units_sold,
       COALESCE(SUM(oi.line_total), 0) AS revenue
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.product_id
LEFT JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
GROUP BY p.product_id, p.product_name
HAVING units_sold > 0
ORDER BY revenue ASC
LIMIT 20;

-- 3. Revenue by category (with % contribution to total)
SELECT cat.category_name,
       SUM(oi.line_total) AS category_revenue,
       ROUND(100 * SUM(oi.line_total) / SUM(SUM(oi.line_total)) OVER (), 2) AS pct_of_total
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
GROUP BY cat.category_name
ORDER BY category_revenue DESC;

-- 4. Monthly revenue trend
SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
       SUM(o.total_amount) AS monthly_revenue,
       COUNT(DISTINCT o.order_id) AS orders_count
FROM orders o
WHERE o.order_status <> 'Cancelled'
GROUP BY sales_month
ORDER BY sales_month;

-- 5. Month-over-month growth % using LAG()
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
           SUM(o.total_amount) AS revenue
    FROM orders o
    WHERE o.order_status <> 'Cancelled'
    GROUP BY sales_month
)
SELECT sales_month, revenue,
       LAG(revenue) OVER (ORDER BY sales_month) AS prev_month_revenue,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY sales_month))
             / NULLIF(LAG(revenue) OVER (ORDER BY sales_month), 0), 2) AS mom_growth_pct
FROM monthly
ORDER BY sales_month;

-- 6. Running total of revenue (cumulative) and 3-month moving average
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
           SUM(o.total_amount) AS revenue
    FROM orders o
    WHERE o.order_status <> 'Cancelled'
    GROUP BY sales_month
)
SELECT sales_month, revenue,
       SUM(revenue) OVER (ORDER BY sales_month ROWS UNBOUNDED PRECEDING) AS running_total,
       ROUND(AVG(revenue) OVER (ORDER BY sales_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3mo
FROM monthly
ORDER BY sales_month;

-- 7. Rank products within each category by revenue (ROW_NUMBER, RANK, DENSE_RANK)
WITH product_revenue AS (
    SELECT p.product_id, p.product_name, cat.category_name,
           SUM(oi.line_total) AS revenue
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN categories cat ON cat.category_id = p.category_id
    JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
    GROUP BY p.product_id, p.product_name, cat.category_name
),
ranked AS (
    SELECT category_name, product_name, revenue,
           ROW_NUMBER() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS row_num,
           RANK()       OVER (PARTITION BY category_name ORDER BY revenue DESC) AS rank_num,
           DENSE_RANK() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS dense_rank_num
    FROM product_revenue
)
-- MySQL has no QUALIFY clause, so the window-function filter is applied
-- in an outer WHERE against the CTE instead.
SELECT * FROM ranked WHERE row_num <= 3 ORDER BY category_name, row_num;

-- 8. Self join example: products from the same category priced within 10% of each other
SELECT p1.product_name AS product_a, p2.product_name AS product_b,
       p1.unit_price AS price_a, p2.unit_price AS price_b, p1.category_id
FROM products p1
JOIN products p2 ON p1.category_id = p2.category_id
    AND p1.product_id < p2.product_id
    AND ABS(p1.unit_price - p2.unit_price) <= (0.10 * p1.unit_price)
LIMIT 20;

-- 9. Recursive CTE: full category tree (top-level -> sub-categories)
WITH RECURSIVE category_tree AS (
    SELECT category_id, category_name, parent_category_id, 0 AS depth,
           CAST(category_name AS CHAR(500)) AS path
    FROM categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_category_id, ct.depth + 1,
           CONCAT(ct.path, ' > ', c.category_name)
    FROM categories c
    JOIN category_tree ct ON c.parent_category_id = ct.category_id
)
SELECT category_id, depth, path FROM category_tree ORDER BY path;
