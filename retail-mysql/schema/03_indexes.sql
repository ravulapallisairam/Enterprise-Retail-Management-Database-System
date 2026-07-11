-- ============================================================
-- Script: 03_indexes.sql
-- Purpose: Performance indexes beyond PK/UNIQUE constraints
-- ============================================================
USE retail_enterprise_db;

-- Customers: lookups by name, segment, activity
CREATE INDEX idx_customers_name ON customers(last_name, first_name);
CREATE INDEX idx_customers_segment ON customers(customer_segment);
CREATE INDEX idx_customers_registration_date ON customers(registration_date);

-- Products: category/supplier filtering, price range queries
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_supplier ON products(supplier_id);
CREATE INDEX idx_products_price ON products(unit_price);
CREATE INDEX idx_products_active_category ON products(is_active, category_id);

-- Orders: the hottest table -- composite indexes for common report queries
-- (idx_orders_customer_date's leftmost column already serves plain
-- customer_id lookups, so no separate single-column index is needed)
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_orders_status ON orders(order_status);
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_orders_date_status ON orders(order_date, order_status);
-- Added after query-profiling high-value-order reports (see
-- optimization/optimization_report.sql): turns a full table scan into
-- an index range scan for WHERE total_amount > <threshold> queries.
CREATE INDEX idx_orders_total_amount ON orders(total_amount);

-- Order items: joins back to orders/products constantly
CREATE INDEX idx_orderitems_order ON order_items(order_id);
CREATE INDEX idx_orderitems_product_order ON order_items(product_id, order_id);
-- NOTE: a separate single-column idx_orderitems_product(product_id) was
-- deliberately NOT created here -- it would be fully redundant with the
-- composite index above, since InnoDB can use a composite index's
-- leftmost column(s) exactly like a single-column index. See
-- optimization/optimization_report.sql for the before/after evidence.

-- Inventory: low stock scans
CREATE INDEX idx_inventory_product ON inventory(product_id);
CREATE INDEX idx_inventory_warehouse ON inventory(warehouse_id);
CREATE INDEX idx_inventory_low_stock ON inventory(quantity_on_hand, reorder_level);

-- Payments
CREATE INDEX idx_payments_order ON payments(order_id);
CREATE INDEX idx_payments_status ON payments(payment_status);
CREATE INDEX idx_payments_date ON payments(payment_date);

-- Shipments
CREATE INDEX idx_shipments_order ON shipments(order_id);
CREATE INDEX idx_shipments_status ON shipments(shipment_status);

-- Reviews: product rating lookups
-- (idx_reviews_rating's leftmost column already serves plain product_id lookups)
CREATE INDEX idx_reviews_customer ON reviews(customer_id);
CREATE INDEX idx_reviews_rating ON reviews(product_id, rating);

-- Returns
CREATE INDEX idx_returns_customer ON returns(customer_id);
CREATE INDEX idx_returns_status ON returns(return_status);

-- Audit log
CREATE INDEX idx_audit_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_time ON audit_log(change_time);
