-- ============================================================
-- Script: inventory_operations_analytics.sql
-- Purpose: Inventory + operations business intelligence queries
-- ============================================================
USE retail_enterprise_db;

-- 1. Low-stock products (reorder needed) across all warehouses
SELECT * FROM vw_low_stock_alert ORDER BY units_below_threshold DESC LIMIT 30;

-- 2. Inventory turnover ratio per product (units sold / avg stock on hand)
WITH sold AS (
    SELECT oi.product_id, SUM(oi.quantity) AS units_sold
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
    GROUP BY oi.product_id
),
stock AS (
    SELECT product_id, AVG(quantity_on_hand) AS avg_stock
    FROM inventory
    GROUP BY product_id
)
SELECT p.product_id, p.product_name,
       COALESCE(s.units_sold, 0) AS units_sold,
       COALESCE(st.avg_stock, 0) AS avg_stock_on_hand,
       ROUND(COALESCE(s.units_sold, 0) / NULLIF(st.avg_stock, 0), 2) AS turnover_ratio
FROM products p
LEFT JOIN sold s ON s.product_id = p.product_id
LEFT JOIN stock st ON st.product_id = p.product_id
ORDER BY turnover_ratio DESC
LIMIT 30;

-- 3. Warehouse-level stock summary
SELECT w.warehouse_id, w.warehouse_name,
       COUNT(i.product_id) AS distinct_products,
       SUM(i.quantity_on_hand) AS total_units,
       SUM(CASE WHEN i.quantity_on_hand <= i.reorder_level THEN 1 ELSE 0 END) AS products_below_reorder
FROM warehouses w
JOIN inventory i ON i.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY total_units DESC;

-- 4. Delivery performance: on-time vs late %
SELECT
    delivery_outcome,
    COUNT(*) AS shipment_count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM vw_delivery_performance
WHERE delivery_outcome <> 'In Progress'
GROUP BY delivery_outcome;

-- 5. Average transit time per carrier
SELECT carrier,
       COUNT(*) AS shipments,
       ROUND(AVG(actual_transit_days), 2) AS avg_transit_days
FROM vw_delivery_performance
WHERE actual_transit_days IS NOT NULL
GROUP BY carrier
ORDER BY avg_transit_days ASC;

-- 6. Return rate: % of delivered order items that were returned
SELECT
    (SELECT COUNT(*) FROM returns) AS total_returns,
    (SELECT COUNT(*) FROM order_items oi
        JOIN orders o ON o.order_id = oi.order_id
        WHERE o.order_status IN ('Delivered','Returned')) AS total_delivered_items,
    ROUND(100.0 * (SELECT COUNT(*) FROM returns) /
        (SELECT COUNT(*) FROM order_items oi
            JOIN orders o ON o.order_id = oi.order_id
            WHERE o.order_status IN ('Delivered','Returned')), 2) AS return_rate_pct;

-- 7. Return reasons breakdown
SELECT return_reason, COUNT(*) AS occurrences,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM returns
GROUP BY return_reason
ORDER BY occurrences DESC;

-- 8. Payment success rate by method
SELECT payment_method,
       COUNT(*) AS total_attempts,
       SUM(CASE WHEN payment_status = 'Success' THEN 1 ELSE 0 END) AS successful,
       ROUND(100 * SUM(CASE WHEN payment_status = 'Success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate_pct
FROM payments
GROUP BY payment_method
ORDER BY success_rate_pct DESC;

-- 9. Profit analysis: revenue vs cost vs margin per product (top 20 by margin)
SELECT p.product_id, p.product_name,
       SUM(oi.line_total) AS revenue,
       SUM(oi.quantity * p.cost_price) AS total_cost,
       SUM(oi.line_total) - SUM(oi.quantity * p.cost_price) AS gross_profit,
       ROUND(100 * (SUM(oi.line_total) - SUM(oi.quantity * p.cost_price)) / NULLIF(SUM(oi.line_total), 0), 2) AS margin_pct
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
GROUP BY p.product_id, p.product_name
ORDER BY gross_profit DESC
LIMIT 20;
