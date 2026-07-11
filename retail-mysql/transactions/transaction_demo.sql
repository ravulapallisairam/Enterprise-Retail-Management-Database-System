-- ============================================================
-- Script: transaction_demo.sql
-- Purpose: Demonstrate transaction control (COMMIT/ROLLBACK/SAVEPOINT)
--          and explain ACID properties using this schema.
-- ============================================================
USE retail_enterprise_db;

-- ------------------------------------------------------------
-- ACID PROPERTIES, EXPLAINED WITH THIS SCHEMA
-- ------------------------------------------------------------
-- ATOMICITY   : sp_place_order() inserts an order header, an order_item,
--               and a payment as one unit. If any step fails (e.g. stock
--               check fails), the EXIT HANDLER rolls back everything —
--               you never end up with an order row but no payment row.
--
-- CONSISTENCY : CHECK constraints (quantity_on_hand >= 0, rating BETWEEN 1
--               AND 5, unit_price >= 0) and FOREIGN KEYs guarantee every
--               committed transaction leaves the database in a valid state
--               — e.g. an order_item can never reference a product that
--               doesn't exist, and inventory can never go negative.
--
-- ISOLATION   : InnoDB's default REPEATABLE READ isolation level, combined
--               with the `SELECT ... FOR UPDATE` row lock in sp_place_order,
--               prevents two concurrent customers from both "winning" the
--               last unit of stock — the second transaction blocks until
--               the first commits or rolls back, then re-reads fresh data.
--
-- DURABILITY  : Once COMMIT succeeds, InnoDB has written the change to its
--               redo log; the order survives a server crash immediately
--               after commit.
-- ------------------------------------------------------------

-- Example 1: Basic COMMIT
SET @wh := (SELECT warehouse_id FROM inventory WHERE product_id = 1 ORDER BY warehouse_id LIMIT 1);
START TRANSACTION;
    UPDATE inventory SET quantity_on_hand = quantity_on_hand + 25
    WHERE product_id = 1 AND warehouse_id = @wh;
COMMIT;

-- Example 2: ROLLBACK on a business-rule violation
-- (Note: a deduction big enough to go negative would be rejected outright
--  by the quantity_on_hand >= 0 CHECK constraint -- CONSISTENCY enforced
--  before the transaction can even be committed. Here we roll back a
--  syntactically valid change instead, to show ROLLBACK undoing work.)
START TRANSACTION;
    UPDATE inventory SET quantity_on_hand = quantity_on_hand - 25
    WHERE product_id = 1 AND warehouse_id = @wh;
    -- Suppose downstream validation (e.g. fraud check on the linked order)
    -- fails after this point -- discard the change entirely.
ROLLBACK;

-- Example 3: SAVEPOINT — partially undo a multi-step transaction
START TRANSACTION;
    UPDATE customers SET customer_segment = 'VIP' WHERE customer_id = 1;
    SAVEPOINT after_segment_update;

    UPDATE customers SET customer_segment = 'VIP' WHERE customer_id = 999999; -- no-op, doesn't exist
    -- Suppose downstream logic detects a problem specific to the second update only.
    ROLLBACK TO SAVEPOINT after_segment_update;

    -- The segment change for customer 1 is still pending here.
COMMIT;

SELECT customer_id, customer_segment FROM customers WHERE customer_id = 1;

-- Example 4: Concurrency-safe stock deduction (what sp_place_order does internally)
-- Session A:
--   START TRANSACTION;
--   SELECT quantity_on_hand FROM inventory WHERE product_id = 10 AND warehouse_id = 1 FOR UPDATE;
--   -- row is now locked; Session B's identical SELECT ... FOR UPDATE blocks here
--   UPDATE inventory SET quantity_on_hand = quantity_on_hand - 5 WHERE product_id = 10 AND warehouse_id = 1;
--   COMMIT;  -- lock released, Session B proceeds with the now-updated value
