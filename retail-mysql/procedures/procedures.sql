-- ============================================================
-- Script: procedures.sql
-- Purpose: Stored procedures for reporting and business operations
-- ============================================================
USE retail_enterprise_db;

DELIMITER $$

-- 1. Full order history + summary for a given customer
DROP PROCEDURE IF EXISTS sp_customer_order_report $$
CREATE PROCEDURE sp_customer_order_report(IN p_customer_id INT)
BEGIN
    SELECT c.customer_id, c.first_name, c.last_name, c.email, c.customer_segment,
           COUNT(DISTINCT o.order_id)         AS total_orders,
           COALESCE(SUM(o.total_amount), 0)   AS lifetime_value,
           COALESCE(AVG(o.total_amount), 0)   AS avg_order_value,
           MAX(o.order_date)                  AS last_order_date
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.customer_id AND o.order_status <> 'Cancelled'
    WHERE c.customer_id = p_customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.customer_segment;

    SELECT o.order_id, o.order_date, o.order_status, o.total_amount,
           COUNT(oi.order_item_id) AS item_count
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.customer_id = p_customer_id
    GROUP BY o.order_id, o.order_date, o.order_status, o.total_amount
    ORDER BY o.order_date DESC;
END $$

-- 2. Total revenue for a date range (only successfully paid, non-cancelled orders)
DROP PROCEDURE IF EXISTS sp_calculate_total_revenue $$
CREATE PROCEDURE sp_calculate_total_revenue(IN p_start_date DATE, IN p_end_date DATE)
BEGIN
    SELECT
        COUNT(DISTINCT o.order_id)        AS total_orders,
        SUM(o.subtotal)                   AS gross_subtotal,
        SUM(o.discount_amount)            AS total_discounts,
        SUM(o.tax_amount)                 AS total_tax,
        SUM(o.shipping_fee)               AS total_shipping,
        SUM(o.total_amount)               AS net_revenue
    FROM orders o
    WHERE o.order_status NOT IN ('Cancelled')
      AND DATE(o.order_date) BETWEEN p_start_date AND p_end_date;
END $$

-- 3. Place a new order atomically: header + items + inventory deduction + payment
--    Demonstrates transaction management (START TRANSACTION / COMMIT / ROLLBACK)
DROP PROCEDURE IF EXISTS sp_place_order $$
CREATE PROCEDURE sp_place_order(
    IN p_customer_id INT,
    IN p_product_id INT,
    IN p_quantity INT,
    IN p_warehouse_id INT,
    IN p_payment_method VARCHAR(30),
    OUT p_order_id INT,
    OUT p_status_message VARCHAR(200)
)
proc_body: BEGIN
    DECLARE v_available INT DEFAULT 0;
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_line_total DECIMAL(12,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status_message = 'ERROR: transaction rolled back';
        SET p_order_id = NULL;
    END;

    START TRANSACTION;

    SELECT quantity_on_hand INTO v_available
    FROM inventory
    WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id
    FOR UPDATE;

    IF v_available IS NULL OR v_available < p_quantity THEN
        ROLLBACK;
        SET p_status_message = 'FAILED: insufficient stock';
        SET p_order_id = NULL;
        LEAVE proc_body;
    END IF;

    SELECT unit_price INTO v_price FROM products WHERE product_id = p_product_id;
    SET v_line_total = v_price * p_quantity;

    INSERT INTO orders (customer_id, order_date, order_status, subtotal, tax_amount,
                         shipping_fee, discount_amount, total_amount)
    VALUES (p_customer_id, NOW(), 'Pending', v_line_total, ROUND(v_line_total * 0.08, 2),
            0, 0, ROUND(v_line_total * 1.08, 2));

    SET p_order_id = LAST_INSERT_ID();

    -- Note: inventory deduction is intentionally NOT done here. The
    -- trg_orderitem_after_insert trigger on order_items handles stock
    -- deduction automatically so there is a single source of truth for
    -- inventory changes, whether an order is placed via this procedure
    -- or by any other application code path that inserts order_items.
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_percent, line_total)
    VALUES (p_order_id, p_product_id, p_quantity, v_price, 0, v_line_total);

    INSERT INTO payments (order_id, payment_method, payment_status, amount, transaction_ref, payment_date)
    VALUES (p_order_id, p_payment_method, 'Success', ROUND(v_line_total * 1.08, 2), UUID(), NOW());

    COMMIT;
    SET p_status_message = 'SUCCESS: order placed';
END $$

-- 4. Restock a product at a warehouse (used by inventory management workflows)
DROP PROCEDURE IF EXISTS sp_restock_inventory $$
CREATE PROCEDURE sp_restock_inventory(IN p_product_id INT, IN p_warehouse_id INT, IN p_quantity INT)
BEGIN
    IF EXISTS (SELECT 1 FROM inventory WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id) THEN
        UPDATE inventory
        SET quantity_on_hand = quantity_on_hand + p_quantity,
            last_restock_date = CURDATE()
        WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id;
    ELSE
        INSERT INTO inventory (product_id, warehouse_id, quantity_on_hand, reorder_level,
                                reorder_quantity, last_restock_date)
        VALUES (p_product_id, p_warehouse_id, p_quantity, 20, 100, CURDATE());
    END IF;
END $$

DELIMITER ;
