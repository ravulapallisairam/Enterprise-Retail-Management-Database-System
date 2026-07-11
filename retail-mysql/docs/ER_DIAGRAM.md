# Entity-Relationship Diagram

Renders automatically on GitHub (Mermaid support built into GitHub's Markdown viewer).

```mermaid
erDiagram
    CATEGORIES ||--o{ CATEGORIES : "parent_category_id"
    CATEGORIES ||--o{ PRODUCTS : "categorizes"
    SUPPLIERS ||--o{ PRODUCTS : "supplies"
    EMPLOYEES ||--o{ EMPLOYEES : "manager_id"
    EMPLOYEES ||--o{ WAREHOUSES : "manages"
    EMPLOYEES ||--o{ ORDERS : "handles"
    WAREHOUSES ||--o{ INVENTORY : "stocks"
    WAREHOUSES ||--o{ SHIPMENTS : "ships_from"
    PRODUCTS ||--o{ INVENTORY : "tracked_in"
    PRODUCTS ||--o{ ORDER_ITEMS : "ordered_as"
    PRODUCTS ||--o{ REVIEWS : "reviewed_in"
    CUSTOMERS ||--o{ CUSTOMER_ADDRESSES : "has"
    CUSTOMERS ||--o{ ORDERS : "places"
    CUSTOMERS ||--o{ REVIEWS : "writes"
    CUSTOMERS ||--o{ RETURNS : "requests"
    CUSTOMER_ADDRESSES ||--o{ ORDERS : "ships_to / bills_to"
    ORDERS ||--o{ ORDER_ITEMS : "contains"
    ORDERS ||--o{ PAYMENTS : "paid_by"
    ORDERS ||--o{ SHIPMENTS : "fulfilled_by"
    ORDER_ITEMS ||--o{ REVIEWS : "reviewed_via"
    ORDER_ITEMS ||--o{ RETURNS : "returned_via"

    CATEGORIES {
        int category_id PK
        string category_name
        int parent_category_id FK
    }
    SUPPLIERS {
        int supplier_id PK
        string supplier_name
        string contact_email
        decimal rating
    }
    EMPLOYEES {
        int employee_id PK
        string first_name
        string last_name
        string job_title
        int manager_id FK
    }
    WAREHOUSES {
        int warehouse_id PK
        string warehouse_name
        int manager_id FK
    }
    PRODUCTS {
        int product_id PK
        string product_name
        int category_id FK
        int supplier_id FK
        decimal unit_price
        decimal cost_price
    }
    INVENTORY {
        int inventory_id PK
        int product_id FK
        int warehouse_id FK
        int quantity_on_hand
        int reorder_level
    }
    CUSTOMERS {
        int customer_id PK
        string first_name
        string last_name
        string email
        string customer_segment
    }
    CUSTOMER_ADDRESSES {
        int address_id PK
        int customer_id FK
        string address_type
        string city
    }
    ORDERS {
        int order_id PK
        int customer_id FK
        int employee_id FK
        datetime order_date
        string order_status
        decimal total_amount
    }
    ORDER_ITEMS {
        int order_item_id PK
        int order_id FK
        int product_id FK
        int quantity
        decimal line_total
    }
    PAYMENTS {
        int payment_id PK
        int order_id FK
        string payment_method
        string payment_status
    }
    SHIPMENTS {
        int shipment_id PK
        int order_id FK
        int warehouse_id FK
        string shipment_status
    }
    REVIEWS {
        int review_id PK
        int product_id FK
        int customer_id FK
        int order_item_id FK
        int rating
    }
    RETURNS {
        int return_id PK
        int order_item_id FK
        int customer_id FK
        string return_status
    }
    AUDIT_LOG {
        bigint audit_id PK
        string table_name
        string operation
        int record_id
    }
```

## Relationship summary

| Relationship | Cardinality | Notes |
|---|---|---|
| categories → categories | 1:M | self-referencing tree (parent/child) |
| suppliers → products | 1:M | one supplier ships many products |
| categories → products | 1:M | one category groups many products |
| employees → employees | 1:M | manager hierarchy |
| employees → warehouses | 1:M | one manager per warehouse |
| customers → customer_addresses | 1:M | multiple billing/shipping addresses |
| customers → orders | 1:M | order history |
| products / warehouses → inventory | M:N | resolved via inventory (composite unique key) |
| orders → order_items | 1:M | order line items |
| orders → payments | 1:M | supports partial/split payments |
| orders → shipments | 1:M | supports split shipments |
| order_items → reviews | 1:0..1 | review tied to a specific purchased line item |
| order_items → returns | 1:0..1 | return tied to a specific purchased line item |
