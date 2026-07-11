# Enterprise Retail Management Database System

A production-grade MySQL 8.0 backend for a large retail/e-commerce company —
built and **validated end-to-end against a live MySQL server**, not just
hand-written SQL. Every script in this repo has actually been executed
against a 5,800-order / 18,800-order-item dataset; the EXPLAIN plans in
`optimization/optimization_report.sql` are real captured output, not
hypothetical examples.

---

## 1. Business Problem & Requirements

A retail company selling across multiple warehouses needs a single source
of truth for customers, catalog, inventory, orders, payments, shipping,
reviews, and returns — plus the analytics to run the business (top
customers, best sellers, inventory health, delivery SLAs, return rates).

**Users of the system:** e-commerce application backend, warehouse ops
staff, customer support, sales/finance analysts, BI dashboards.

**Functional requirements**
- Manage customer profiles, multiple addresses, and segmentation
- Maintain a multi-warehouse product catalog with supplier and category hierarchy
- Track per-warehouse stock levels with reorder thresholds
- Process multi-item orders with tax, discount, and shipping calculations
- Record payments (multiple methods, success/failure/refund states)
- Track shipments and delivery performance per carrier
- Support product reviews and return/refund workflows
- Produce sales, inventory, and operations analytics on demand

**Non-functional requirements**
- 3NF-normalized schema with enforced referential integrity
- Sub-second lookups on the hot paths (customer order history, product
  search, low-stock alerts) via targeted composite indexes
- Atomic order placement (no order without its payment, no oversold stock)
- Auditability of price and order-status changes

---

## 2. Architecture

**15 tables**, grouped into four domains:

| Domain | Tables |
|---|---|
| Catalog | `categories`, `suppliers`, `products` |
| People & Ops | `customers`, `customer_addresses`, `employees`, `warehouses` |
| Inventory | `inventory` |
| Transactions | `orders`, `order_items`, `payments`, `shipments`, `reviews`, `returns` |
| Governance | `audit_log` |

Full ER diagram: [`docs/ER_DIAGRAM.md`](docs/ER_DIAGRAM.md).

All tables are 3NF: every non-key column depends on the whole primary key
and nothing but the key (e.g. `order_items.line_total` is stored rather
than only derived, because it's a business fact captured at sale time —
unit price can change on `products` later without rewriting history).

---

## 3. Repository Structure

```
retail-mysql/
├── schema/
│   ├── 01_create_database.sql      -- DB creation, charset/collation
│   ├── 02_tables.sql               -- 15 tables, PK/FK/CHECK constraints
│   └── 03_indexes.sql              -- 27 performance indexes
├── scripts/
│   ├── generate_data.py            -- Phase 1: master data (customers, products, ...)
│   └── generate_transactions.py    -- Phase 2: orders, items, payments, shipments, reviews, returns
├── data/
│   └── seed_data.sql               -- mysqldump of the generated dataset (ready to import)
├── functions/functions.sql         -- 4 scalar functions
├── procedures/procedures.sql       -- 4 stored procedures (incl. transactional order placement)
├── triggers/triggers.sql           -- 5 triggers (auto inventory + audit logging)
├── views/views.sql                 -- 5 reporting views
├── transactions/transaction_demo.sql        -- COMMIT/ROLLBACK/SAVEPOINT + ACID walkthrough
├── optimization/optimization_report.sql     -- real before/after EXPLAIN case studies
├── analytics/
│   ├── customer_analytics.sql
│   ├── product_sales_analytics.sql
│   └── inventory_operations_analytics.sql
└── docs/
    └── ER_DIAGRAM.md
```

---

## 4. Setup (MySQL Workbench or CLI)

```bash
# 1. Schema
mysql -u root -p < schema/01_create_database.sql
mysql -u root -p < schema/02_tables.sql
mysql -u root -p < schema/03_indexes.sql

# 2a. Fastest: load the pre-generated dataset
mysql -u root -p retail_enterprise_db < data/seed_data.sql

# 2b. OR regenerate fresh (randomized but reproducible via fixed seeds)
pip install faker mysql-connector-python
python3 scripts/generate_data.py
python3 scripts/generate_transactions.py

# 3. Database objects
mysql -u root -p < functions/functions.sql
mysql -u root -p < procedures/procedures.sql
mysql -u root -p < triggers/triggers.sql
mysql -u root -p < views/views.sql
```

Then open any file under `analytics/` in MySQL Workbench and run it against
`retail_enterprise_db`.

---

## 5. Dataset Scale (actually generated, verified by `SELECT COUNT(*)`)

| Table | Rows | Spec minimum |
|---|---:|---:|
| customers | 1,500 | 1,000 |
| products | 650 | 500 |
| orders | 5,800 | 5,000 |
| order_items | 18,808 | 15,000 |
| reviews | 1,400 | 1,000 |
| suppliers | 120 | — |
| employees | 77 | — |
| warehouses | 12 | — |
| categories | 48 | — |
| inventory | 1,316 | — |
| payments | 5,800 | — |
| shipments | 4,939 | — |
| returns | 276 | — |

---

## 6. SQL Concept Coverage

- **Basic**: CREATE/INSERT/SELECT/UPDATE/DELETE throughout `schema/`, `scripts/`, `procedures/`
- **Filtering**: WHERE/LIKE/BETWEEN/IN/ORDER BY/LIMIT — see `analytics/*.sql`
- **Aggregation**: COUNT/SUM/AVG/MIN/MAX/GROUP BY/HAVING — every analytics file
- **Joins**: INNER, LEFT, self-join (`product_sales_analytics.sql` §8), multi-table joins (4-6 tables in `vw_product_performance`)
- **Advanced**: correlated subqueries + EXISTS/NOT EXISTS (`customer_analytics.sql` §6-7), CTEs, **recursive CTE** for the category tree (`product_sales_analytics.sql` §9)
- **Window functions**: ROW_NUMBER, RANK, DENSE_RANK, LAG, NTILE, running totals, 3-month moving average (`product_sales_analytics.sql` §5-7, `customer_analytics.sql` §5 RFM)
- **Views**: 5 views in `views/views.sql`
- **Stored procedures**: customer report, revenue calculator, **atomic order placement with rollback**, restock (`procedures/procedures.sql`)
- **Functions**: discount calculator, product revenue, customer lifetime value, age calculator (`functions/functions.sql`)
- **Triggers**: auto stock deduction on order, auto restock on cancellation, audit logging on price/status/deletion changes (`triggers/triggers.sql`)
- **Transactions**: START TRANSACTION/COMMIT/ROLLBACK/SAVEPOINT + ACID explained against this exact schema (`transactions/transaction_demo.sql`)
- **Performance**: 27 indexes, composite index design, `EXPLAIN` before/after with real row-count evidence, one deliberately *removed* redundant index (`optimization/optimization_report.sql`)

---

## 7. Design Decisions Worth Knowing in an Interview

- **`order_items.unit_price` and `line_total` are stored, not computed
  on read.** Prices change on `products` over time; an order must show
  what the customer actually paid, so the sale-time price is captured as
  a fact at insert time — this is intentional denormalization for
  historical accuracy, not an oversight.
- **Inventory deduction lives in a trigger (`trg_orderitem_after_insert`),
  not in application code or the `sp_place_order` procedure.** This was a
  real bug caught during testing: the procedure originally *also*
  decremented stock, causing a double-deduction. The fix keeps a single
  source of truth — any code path that inserts into `order_items`
  automatically gets correct stock accounting.
- **`idx_orderitems_product` was deliberately not created** because
  `idx_orderitems_product_order(product_id, order_id)` already serves
  `product_id`-only lookups via its leftmost column — a redundant index
  just doubles write cost for zero read benefit. See optimization report.
- **MySQL has no `QUALIFY` clause** (unlike Snowflake/BigQuery); the
  "top 3 products per category" query wraps the windowed CTE in an outer
  `WHERE` instead.
- **A same-table `UPDATE ... JOIN` referencing its own table in a
  subquery is rejected by MySQL** ("can't specify target table for
  update in FROM clause"). The cancel-and-restock trigger uses a cursor
  loop instead of a single correlated UPDATE for this reason.

---

## 8. Future Improvements

- Partition `orders`/`order_items` by year once historical volume grows past a few million rows
- Add a `low_stock_flag` generated column + trigger so low-stock scans use an index instead of a same-row column comparison (documented as a known limitation in the optimization report)
- Read replicas for the analytics workload to isolate it from the OLTP write path
- Materialized daily/monthly rollup tables if `vw_sales_dashboard` needs to serve a high-traffic dashboard directly
