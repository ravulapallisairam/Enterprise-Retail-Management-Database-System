-- ============================================================
-- Script: views.sql
-- Purpose: Reusable reporting views for dashboards/BI tools
-- ============================================================
USE retail_enterprise_db;

-- 1. Daily sales dashboard
CREATE OR REPLACE VIEW vw_sales_dashboard AS
SELECT
    DATE(o.order_date)                 AS sales_date,
    COUNT(DISTINCT o.order_id)         AS total_orders,
    COUNT(DISTINCT o.customer_id)      AS unique_customers,
    SUM(o.subtotal)                    AS gross_subtotal,
    SUM(o.discount_amount)             AS total_discounts,
    SUM(o.tax_amount)                  AS total_tax,
    SUM(o.total_amount)                AS net_revenue,
    ROUND(AVG(o.total_amount), 2)      AS avg_order_value
FROM orders o
WHERE o.order_status <> 'Cancelled'
GROUP BY DATE(o.order_date);

-- 2. Per-customer purchase history + lifetime value summary
CREATE OR REPLACE VIEW vw_customer_purchase_history AS
SELECT
    c.customer_id, c.first_name, c.last_name, c.email, c.customer_segment,
    COUNT(DISTINCT o.order_id)          AS total_orders,
    COALESCE(SUM(o.total_amount), 0)    AS lifetime_value,
    COALESCE(ROUND(AVG(o.total_amount), 2), 0) AS avg_order_value,
    MIN(o.order_date)                   AS first_order_date,
    MAX(o.order_date)                   AS last_order_date,
    DATEDIFF(CURDATE(), MAX(o.order_date)) AS days_since_last_order
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id AND o.order_status <> 'Cancelled'
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.customer_segment;

-- 3. Product performance: revenue, units sold, avg rating
CREATE OR REPLACE VIEW vw_product_performance AS
SELECT
    p.product_id, p.product_name, cat.category_name, s.supplier_name,
    p.unit_price,
    COALESCE(SUM(oi.quantity), 0)          AS units_sold,
    COALESCE(SUM(oi.line_total), 0)        AS total_revenue,
    COALESCE(ROUND(AVG(r.rating), 2), NULL) AS avg_rating,
    COUNT(DISTINCT r.review_id)             AS review_count
FROM products p
JOIN categories cat ON cat.category_id = p.category_id
JOIN suppliers s ON s.supplier_id = p.supplier_id
LEFT JOIN order_items oi ON oi.product_id = p.product_id
LEFT JOIN orders o ON o.order_id = oi.order_id AND o.order_status <> 'Cancelled'
LEFT JOIN reviews r ON r.product_id = p.product_id
GROUP BY p.product_id, p.product_name, cat.category_name, s.supplier_name, p.unit_price;

-- 4. Low-stock alert view (below reorder level)
CREATE OR REPLACE VIEW vw_low_stock_alert AS
SELECT
    p.product_id, p.product_name, w.warehouse_id, w.warehouse_name,
    i.quantity_on_hand, i.reorder_level, i.reorder_quantity,
    (i.reorder_level - i.quantity_on_hand) AS units_below_threshold
FROM inventory i
JOIN products p ON p.product_id = i.product_id
JOIN warehouses w ON w.warehouse_id = i.warehouse_id
WHERE i.quantity_on_hand <= i.reorder_level
  AND p.is_active = TRUE;

-- 5. Order fulfillment / delivery performance view
CREATE OR REPLACE VIEW vw_delivery_performance AS
SELECT
    s.shipment_id, o.order_id, o.customer_id, s.carrier, s.shipment_status,
    s.shipped_date, s.estimated_delivery_date, s.actual_delivery_date,
    CASE
        WHEN s.actual_delivery_date IS NOT NULL
        THEN DATEDIFF(s.actual_delivery_date, s.shipped_date)
        ELSE NULL
    END AS actual_transit_days,
    CASE
        WHEN s.actual_delivery_date IS NOT NULL AND s.actual_delivery_date > s.estimated_delivery_date
        THEN 'Late'
        WHEN s.actual_delivery_date IS NOT NULL
        THEN 'On Time'
        ELSE 'In Progress'
    END AS delivery_outcome
FROM shipments s
JOIN orders o ON o.order_id = s.order_id;
