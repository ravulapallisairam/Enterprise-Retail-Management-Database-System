-- ============================================================
-- Script: triggers.sql
-- Purpose: Automatic inventory updates + audit logging
-- ============================================================
USE retail_enterprise_db;

DELIMITER $$

-- 1. When a new order_item is inserted, decrement stock in the first warehouse
--    that carries the product and has enough stock (simple allocation strategy).
DROP TRIGGER IF EXISTS trg_orderitem_after_insert $$
CREATE TRIGGER trg_orderitem_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE v_warehouse_id INT;

    SELECT warehouse_id INTO v_warehouse_id
    FROM inventory
    WHERE product_id = NEW.product_id AND quantity_on_hand >= NEW.quantity
    ORDER BY quantity_on_hand DESC
    LIMIT 1;

    IF v_warehouse_id IS NOT NULL THEN
        UPDATE inventory
        SET quantity_on_hand = quantity_on_hand - NEW.quantity
        WHERE product_id = NEW.product_id AND warehouse_id = v_warehouse_id;
    END IF;
END $$

-- 2. If an order is cancelled after items were allocated, restock the first
--    warehouse holding that product (simple restock-on-cancel strategy).
DROP TRIGGER IF EXISTS trg_order_after_update_cancel $$
CREATE TRIGGER trg_order_after_update_cancel
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    -- MySQL does not allow updating a table while selecting from the same
    -- table in one statement, so we loop row-by-row via a cursor instead
    -- of a single UPDATE...JOIN...subquery.
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_product_id INT;
    DECLARE v_qty INT;
    DECLARE v_target_warehouse INT;
    DECLARE cur_items CURSOR FOR
        SELECT product_id, quantity FROM order_items WHERE order_id = NEW.order_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    IF NEW.order_status = 'Cancelled' AND OLD.order_status <> 'Cancelled' THEN
        OPEN cur_items;
        read_loop: LOOP
            FETCH cur_items INTO v_product_id, v_qty;
            IF v_done = 1 THEN
                LEAVE read_loop;
            END IF;

            SELECT warehouse_id INTO v_target_warehouse
            FROM inventory
            WHERE product_id = v_product_id
            ORDER BY quantity_on_hand ASC
            LIMIT 1;

            IF v_target_warehouse IS NOT NULL THEN
                UPDATE inventory
                SET quantity_on_hand = quantity_on_hand + v_qty
                WHERE product_id = v_product_id AND warehouse_id = v_target_warehouse;
            END IF;
        END LOOP;
        CLOSE cur_items;
    END IF;
END $$

-- 3. Audit log: capture every UPDATE on products (price changes are business-critical)
DROP TRIGGER IF EXISTS trg_products_after_update_audit $$
CREATE TRIGGER trg_products_after_update_audit
AFTER UPDATE ON products
FOR EACH ROW
BEGIN
    IF NOT (OLD.unit_price <=> NEW.unit_price) OR NOT (OLD.is_active <=> NEW.is_active) THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value)
        VALUES (
            'products', 'UPDATE', NEW.product_id,
            JSON_OBJECT('unit_price', OLD.unit_price, 'is_active', OLD.is_active),
            JSON_OBJECT('unit_price', NEW.unit_price, 'is_active', NEW.is_active)
        );
    END IF;
END $$

-- 4. Audit log: capture every order status change
DROP TRIGGER IF EXISTS trg_orders_after_update_audit $$
CREATE TRIGGER trg_orders_after_update_audit
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF NOT (OLD.order_status <=> NEW.order_status) THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value)
        VALUES (
            'orders', 'UPDATE', NEW.order_id,
            JSON_OBJECT('order_status', OLD.order_status),
            JSON_OBJECT('order_status', NEW.order_status)
        );
    END IF;
END $$

-- 5. Audit log: log every customer deletion (soft-delete pattern also encouraged in app layer)
DROP TRIGGER IF EXISTS trg_customers_before_delete_audit $$
CREATE TRIGGER trg_customers_before_delete_audit
BEFORE DELETE ON customers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_value)
    VALUES ('customers', 'DELETE', OLD.customer_id,
            JSON_OBJECT('email', OLD.email, 'first_name', OLD.first_name, 'last_name', OLD.last_name));
END $$

DELIMITER ;
