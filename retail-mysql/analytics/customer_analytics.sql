-- ============================================================
-- Script: customer_analytics.sql
-- Purpose: Customer-focused business intelligence queries
-- ============================================================
USE retail_enterprise_db;

-- 1. Top 20 customers by total spending
SELECT c.customer_id, c.first_name, c.last_name, c.customer_segment,
       SUM(o.total_amount) AS total_spent,
       COUNT(o.order_id)   AS order_count
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id AND o.order_status <> 'Cancelled'
GROUP BY c.customer_id, c.first_name, c.last_name, c.customer_segment
ORDER BY total_spent DESC
LIMIT 20;

-- 2. Customer lifetime value (CLV) using the reusable function, ranked
SELECT c.customer_id, c.first_name, c.last_name,
       fn_customer_lifetime_value(c.customer_id) AS clv,
       RANK() OVER (ORDER BY fn_customer_lifetime_value(c.customer_id) DESC) AS clv_rank
FROM customers c
ORDER BY clv DESC
LIMIT 20;

-- 3. Inactive / at-risk customers: no order in the last 180 days but have ordered before
SELECT c.customer_id, c.first_name, c.last_name, c.email,
       MAX(o.order_date) AS last_order_date,
       DATEDIFF(CURDATE(), MAX(o.order_date)) AS days_inactive
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email
HAVING days_inactive > 180
ORDER BY days_inactive DESC
LIMIT 50;

-- 4. Repeat buyers: customers with more than one order
SELECT c.customer_id, c.first_name, c.last_name,
       COUNT(o.order_id) AS total_orders
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id AND o.order_status <> 'Cancelled'
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(o.order_id) > 1
ORDER BY total_orders DESC
LIMIT 50;

-- 5. RFM Segmentation (Recency, Frequency, Monetary) using window functions + CTEs
WITH rfm_base AS (
    SELECT
        c.customer_id,
        DATEDIFF(CURDATE(), MAX(o.order_date)) AS recency_days,
        COUNT(o.order_id)                       AS frequency,
        SUM(o.total_amount)                     AS monetary
    FROM customers c
    JOIN orders o ON o.customer_id = c.customer_id AND o.order_status <> 'Cancelled'
    GROUP BY c.customer_id
),
rfm_scored AS (
    SELECT
        customer_id, recency_days, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- more recent = higher score
        NTILE(5) OVER (ORDER BY frequency ASC)      AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm_base
)
SELECT
    customer_id, recency_days, frequency, monetary, r_score, f_score, m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN (r_score + f_score + m_score) >= 13 THEN 'Champion'
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Loyal'
        WHEN (r_score + f_score + m_score) >= 7  THEN 'Potential'
        WHEN (r_score + f_score + m_score) >= 4  THEN 'At Risk'
        ELSE 'Lost'
    END AS rfm_segment
FROM rfm_scored
ORDER BY rfm_total DESC
LIMIT 50;

-- 6. Customer purchase frequency using a correlated subquery + EXISTS
SELECT c.customer_id, c.first_name, c.last_name
FROM customers c
WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id
      AND o.order_status = 'Delivered'
    GROUP BY o.customer_id
    HAVING COUNT(*) >= 3
)
LIMIT 20;

-- 7. Customers who have NEVER placed an order (NOT EXISTS)
SELECT c.customer_id, c.first_name, c.last_name, c.registration_date
FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
)
LIMIT 20;
