-- ============================================================
-- Script: 02_tables.sql
-- Purpose: Core table definitions (3NF normalized)
-- ============================================================
USE retail_enterprise_db;

-- 1. CATEGORIES (self-referencing for parent/child category tree)
CREATE TABLE categories (
    category_id     INT AUTO_INCREMENT PRIMARY KEY,
    category_name   VARCHAR(100) NOT NULL,
    parent_category_id INT NULL,
    description     VARCHAR(500),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_category_id)
        REFERENCES categories(category_id) ON DELETE SET NULL,
    CONSTRAINT uq_category_name UNIQUE (category_name)
) ENGINE=InnoDB;

-- 2. SUPPLIERS
CREATE TABLE suppliers (
    supplier_id     INT AUTO_INCREMENT PRIMARY KEY,
    supplier_name   VARCHAR(150) NOT NULL,
    contact_email   VARCHAR(150) NOT NULL,
    contact_phone   VARCHAR(20),
    address_line1   VARCHAR(200),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100) NOT NULL,
    postal_code     VARCHAR(20),
    rating          DECIMAL(2,1) DEFAULT 0.0 CHECK (rating BETWEEN 0 AND 5),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_supplier_email UNIQUE (contact_email)
) ENGINE=InnoDB;

-- 3. EMPLOYEES (self-referencing for manager hierarchy)
CREATE TABLE employees (
    employee_id     INT AUTO_INCREMENT PRIMARY KEY,
    first_name      VARCHAR(60) NOT NULL,
    last_name       VARCHAR(60) NOT NULL,
    email           VARCHAR(150) NOT NULL,
    phone           VARCHAR(20),
    hire_date       DATE NOT NULL,
    job_title       VARCHAR(100) NOT NULL,
    department      VARCHAR(80) NOT NULL,
    salary          DECIMAL(10,2) NOT NULL CHECK (salary >= 0),
    manager_id      INT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_employee_manager FOREIGN KEY (manager_id)
        REFERENCES employees(employee_id) ON DELETE SET NULL,
    CONSTRAINT uq_employee_email UNIQUE (email)
) ENGINE=InnoDB;

-- 4. WAREHOUSES
CREATE TABLE warehouses (
    warehouse_id    INT AUTO_INCREMENT PRIMARY KEY,
    warehouse_name  VARCHAR(120) NOT NULL,
    address_line1   VARCHAR(200),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100) NOT NULL,
    postal_code     VARCHAR(20),
    capacity_units  INT NOT NULL DEFAULT 0,
    manager_id      INT NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_warehouse_manager FOREIGN KEY (manager_id)
        REFERENCES employees(employee_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 5. CUSTOMERS
CREATE TABLE customers (
    customer_id       INT AUTO_INCREMENT PRIMARY KEY,
    first_name        VARCHAR(60) NOT NULL,
    last_name         VARCHAR(60) NOT NULL,
    email             VARCHAR(150) NOT NULL,
    phone             VARCHAR(20),
    date_of_birth     DATE,
    gender            ENUM('Male','Female','Other','Prefer not to say') DEFAULT 'Prefer not to say',
    registration_date DATE NOT NULL,
    customer_segment  ENUM('New','Regular','VIP','Churned') NOT NULL DEFAULT 'New',
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_customer_email UNIQUE (email)
) ENGINE=InnoDB;

-- 6. CUSTOMER_ADDRESSES (1 customer -> many addresses)
CREATE TABLE customer_addresses (
    address_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id     INT NOT NULL,
    address_type    ENUM('Billing','Shipping','Both') NOT NULL DEFAULT 'Both',
    address_line1   VARCHAR(200) NOT NULL,
    address_line2   VARCHAR(200),
    city            VARCHAR(100) NOT NULL,
    state           VARCHAR(100),
    country         VARCHAR(100) NOT NULL,
    postal_code     VARCHAR(20) NOT NULL,
    is_default      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_address_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 7. PRODUCTS
CREATE TABLE products (
    product_id      INT AUTO_INCREMENT PRIMARY KEY,
    product_name    VARCHAR(200) NOT NULL,
    category_id     INT NOT NULL,
    supplier_id     INT NOT NULL,
    sku             VARCHAR(50) NOT NULL,
    description     VARCHAR(1000),
    unit_price      DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    cost_price      DECIMAL(10,2) NOT NULL CHECK (cost_price >= 0),
    weight_kg       DECIMAL(6,2) DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_product_category FOREIGN KEY (category_id)
        REFERENCES categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT fk_product_supplier FOREIGN KEY (supplier_id)
        REFERENCES suppliers(supplier_id) ON DELETE RESTRICT,
    CONSTRAINT uq_product_sku UNIQUE (sku)
) ENGINE=InnoDB;

-- 8. INVENTORY (per product per warehouse)
CREATE TABLE inventory (
    inventory_id      INT AUTO_INCREMENT PRIMARY KEY,
    product_id        INT NOT NULL,
    warehouse_id      INT NOT NULL,
    quantity_on_hand   INT NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    reorder_level     INT NOT NULL DEFAULT 10,
    reorder_quantity  INT NOT NULL DEFAULT 50,
    last_restock_date DATE,
    updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE CASCADE,
    CONSTRAINT fk_inventory_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES warehouses(warehouse_id) ON DELETE CASCADE,
    CONSTRAINT uq_inventory_product_warehouse UNIQUE (product_id, warehouse_id)
) ENGINE=InnoDB;

-- 9. ORDERS
CREATE TABLE orders (
    order_id            INT AUTO_INCREMENT PRIMARY KEY,
    customer_id         INT NOT NULL,
    employee_id         INT NULL,
    order_date          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    order_status        ENUM('Pending','Processing','Shipped','Delivered','Cancelled','Returned') NOT NULL DEFAULT 'Pending',
    shipping_address_id INT NULL,
    billing_address_id  INT NULL,
    subtotal            DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    shipping_fee        DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount_amount     DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_order_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_employee FOREIGN KEY (employee_id)
        REFERENCES employees(employee_id) ON DELETE SET NULL,
    CONSTRAINT fk_order_ship_addr FOREIGN KEY (shipping_address_id)
        REFERENCES customer_addresses(address_id) ON DELETE SET NULL,
    CONSTRAINT fk_order_bill_addr FOREIGN KEY (billing_address_id)
        REFERENCES customer_addresses(address_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 10. ORDER_ITEMS
CREATE TABLE order_items (
    order_item_id    INT AUTO_INCREMENT PRIMARY KEY,
    order_id         INT NOT NULL,
    product_id       INT NOT NULL,
    quantity         INT NOT NULL CHECK (quantity > 0),
    unit_price       DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_percent DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (discount_percent BETWEEN 0 AND 100),
    line_total       DECIMAL(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_orderitem_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_orderitem_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 11. PAYMENTS
CREATE TABLE payments (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    order_id        INT NOT NULL,
    payment_method  ENUM('Credit Card','Debit Card','UPI','Net Banking','Wallet','Cash on Delivery') NOT NULL,
    payment_status  ENUM('Pending','Success','Failed','Refunded') NOT NULL DEFAULT 'Pending',
    amount          DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
    transaction_ref VARCHAR(100),
    payment_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 12. SHIPMENTS
CREATE TABLE shipments (
    shipment_id           INT AUTO_INCREMENT PRIMARY KEY,
    order_id              INT NOT NULL,
    warehouse_id          INT NOT NULL,
    carrier               VARCHAR(80) NOT NULL,
    tracking_number       VARCHAR(100),
    shipped_date          DATETIME NULL,
    estimated_delivery_date DATE NULL,
    actual_delivery_date  DATETIME NULL,
    shipment_status       ENUM('Preparing','In Transit','Out for Delivery','Delivered','Delayed','Lost') NOT NULL DEFAULT 'Preparing',
    CONSTRAINT fk_shipment_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_shipment_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES warehouses(warehouse_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 13. REVIEWS
CREATE TABLE reviews (
    review_id           INT AUTO_INCREMENT PRIMARY KEY,
    product_id          INT NOT NULL,
    customer_id         INT NOT NULL,
    order_item_id       INT NULL,
    rating              TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_title        VARCHAR(150),
    review_text         VARCHAR(2000),
    review_date         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_review_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE CASCADE,
    CONSTRAINT fk_review_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE CASCADE,
    CONSTRAINT fk_review_orderitem FOREIGN KEY (order_item_id)
        REFERENCES order_items(order_item_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 14. RETURNS
CREATE TABLE returns (
    return_id       INT AUTO_INCREMENT PRIMARY KEY,
    order_item_id   INT NOT NULL,
    customer_id     INT NOT NULL,
    return_reason   VARCHAR(300) NOT NULL,
    return_status   ENUM('Requested','Approved','Rejected','Refunded','Completed') NOT NULL DEFAULT 'Requested',
    refund_amount   DECIMAL(10,2) NOT NULL DEFAULT 0,
    return_date     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_date  DATETIME NULL,
    CONSTRAINT fk_return_orderitem FOREIGN KEY (order_item_id)
        REFERENCES order_items(order_item_id) ON DELETE CASCADE,
    CONSTRAINT fk_return_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 15. AUDIT_LOG (populated by triggers)
CREATE TABLE audit_log (
    audit_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name      VARCHAR(64) NOT NULL,
    operation       ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id       INT NOT NULL,
    changed_by      VARCHAR(100) DEFAULT (CURRENT_USER()),
    change_time     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_value       JSON NULL,
    new_value       JSON NULL
) ENGINE=InnoDB;
