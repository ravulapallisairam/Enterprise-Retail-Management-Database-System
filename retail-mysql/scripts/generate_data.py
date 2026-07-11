#!/usr/bin/env python3
"""
Enterprise Retail DB - Realistic Data Generator
Populates retail_enterprise_db with production-scale, referentially-correct data.

Scale targets (from project spec):
  customers   >= 1000
  products    >= 500
  orders      >= 5000
  order_items >= 15000
  reviews     >= 1000
"""
import random
import datetime
import mysql.connector
from faker import Faker

fake = Faker()
Faker.seed(42)
random.seed(42)

conn = mysql.connector.connect(host="127.0.0.1", user="retail_app", password="RetailApp123!",
                                database="retail_enterprise_db")
conn.autocommit = False
cur = conn.cursor()

def batch_insert(sql, rows, batch_size=2000):
    for i in range(0, len(rows), batch_size):
        cur.executemany(sql, rows[i:i + batch_size])
    conn.commit()

# ------------------------------------------------------------------
# 1. CATEGORIES (top-level + sub-categories)
# ------------------------------------------------------------------
top_categories = ["Electronics", "Fashion", "Home & Kitchen", "Beauty & Personal Care",
                   "Sports & Outdoors", "Books & Stationery", "Toys & Games",
                   "Grocery", "Automotive", "Health & Wellness"]
sub_map = {
    "Electronics": ["Mobiles", "Laptops", "Audio", "Cameras", "Accessories"],
    "Fashion": ["Men's Clothing", "Women's Clothing", "Footwear", "Watches", "Bags"],
    "Home & Kitchen": ["Furniture", "Kitchenware", "Home Decor", "Lighting"],
    "Beauty & Personal Care": ["Skincare", "Haircare", "Makeup", "Fragrances"],
    "Sports & Outdoors": ["Fitness Equipment", "Outdoor Gear", "Cycling", "Team Sports"],
    "Books & Stationery": ["Fiction", "Non-Fiction", "Office Supplies", "Notebooks"],
    "Toys & Games": ["Action Figures", "Board Games", "Educational Toys"],
    "Grocery": ["Snacks", "Beverages", "Staples"],
    "Automotive": ["Car Accessories", "Bike Accessories", "Tools"],
    "Health & Wellness": ["Supplements", "Medical Devices", "Personal Hygiene"],
}

cat_rows = []
for c in top_categories:
    cat_rows.append((c, None, f"{c} department", True))
batch_insert(
    "INSERT INTO categories (category_name, parent_category_id, description, is_active) VALUES (%s,%s,%s,%s)",
    cat_rows)

cur.execute("SELECT category_id, category_name FROM categories")
top_ids = {name: cid for cid, name in cur.fetchall()}

sub_rows = []
for top, subs in sub_map.items():
    for s in subs:
        sub_rows.append((s, top_ids[top], f"{s} under {top}", True))
batch_insert(
    "INSERT INTO categories (category_name, parent_category_id, description, is_active) VALUES (%s,%s,%s,%s)",
    sub_rows)

cur.execute("SELECT category_id FROM categories WHERE parent_category_id IS NOT NULL")
leaf_category_ids = [r[0] for r in cur.fetchall()]
print(f"Categories created: {len(top_categories) + len(sub_rows)}")

# ------------------------------------------------------------------
# 2. SUPPLIERS
# ------------------------------------------------------------------
SUPPLIER_COUNT = 120
sup_rows = []
for _ in range(SUPPLIER_COUNT):
    sup_rows.append((
        fake.company(), fake.company_email(), fake.phone_number()[:20],
        fake.street_address(), fake.city(), fake.state(), fake.country(),
        fake.postcode(), round(random.uniform(2.5, 5.0), 1), True
    ))
batch_insert(
    """INSERT INTO suppliers (supplier_name, contact_email, contact_phone, address_line1,
       city, state, country, postal_code, rating, is_active) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    sup_rows)
cur.execute("SELECT supplier_id FROM suppliers")
supplier_ids = [r[0] for r in cur.fetchall()]
print(f"Suppliers created: {len(supplier_ids)}")

# ------------------------------------------------------------------
# 3. EMPLOYEES (hierarchy: execs -> managers -> staff)
# ------------------------------------------------------------------
departments = ["Sales", "Warehouse Operations", "Customer Support", "Procurement", "IT", "Finance"]
titles_by_level = {
    0: ["Chief Operating Officer"],
    1: ["Department Manager"],
    2: ["Team Lead"],
    3: ["Associate", "Executive", "Analyst"],
}
emp_rows = []
# level 0: 1 COO
emp_rows.append((fake.first_name(), fake.last_name(), fake.unique.company_email(),
                  fake.phone_number()[:20], fake.date_between(start_date="-8y", end_date="-5y"),
                  "Chief Operating Officer", "Executive", 250000, None, True))
batch_insert(
    """INSERT INTO employees (first_name, last_name, email, phone, hire_date, job_title,
       department, salary, manager_id, is_active) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    emp_rows)
cur.execute("SELECT employee_id FROM employees")
coo_id = cur.fetchall()[0][0]

manager_ids = []
emp_rows = []
for dept in departments:
    emp_rows.append((fake.first_name(), fake.last_name(), fake.unique.company_email(),
                      fake.phone_number()[:20], fake.date_between(start_date="-6y", end_date="-3y"),
                      "Department Manager", dept, random.randint(90000, 140000), coo_id, True))
batch_insert(
    """INSERT INTO employees (first_name, last_name, email, phone, hire_date, job_title,
       department, salary, manager_id, is_active) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    emp_rows)
cur.execute("SELECT employee_id, department FROM employees WHERE job_title='Department Manager'")
dept_manager = {dept: eid for eid, dept in cur.fetchall()}

STAFF_COUNT = 70
emp_rows = []
for _ in range(STAFF_COUNT):
    dept = random.choice(departments)
    emp_rows.append((fake.first_name(), fake.last_name(), fake.unique.company_email(),
                      fake.phone_number()[:20], fake.date_between(start_date="-4y", end_date="-1M"),
                      random.choice(["Associate", "Executive", "Analyst", "Team Lead"]), dept,
                      random.randint(35000, 85000), dept_manager[dept], True))
batch_insert(
    """INSERT INTO employees (first_name, last_name, email, phone, hire_date, job_title,
       department, salary, manager_id, is_active) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    emp_rows)
cur.execute("SELECT employee_id FROM employees")
employee_ids = [r[0] for r in cur.fetchall()]
print(f"Employees created: {len(employee_ids)}")

# ------------------------------------------------------------------
# 4. WAREHOUSES
# ------------------------------------------------------------------
wh_rows = []
warehouse_cities = [fake.city() for _ in range(12)]
for city in warehouse_cities:
    wh_rows.append((f"{city} Distribution Center", fake.street_address(), city,
                     fake.state(), fake.country(), fake.postcode(),
                     random.randint(20000, 100000), random.choice(employee_ids)))
batch_insert(
    """INSERT INTO warehouses (warehouse_name, address_line1, city, state, country,
       postal_code, capacity_units, manager_id) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
    wh_rows)
cur.execute("SELECT warehouse_id FROM warehouses")
warehouse_ids = [r[0] for r in cur.fetchall()]
print(f"Warehouses created: {len(warehouse_ids)}")

# ------------------------------------------------------------------
# 5. PRODUCTS  (>= 500)
# ------------------------------------------------------------------
PRODUCT_COUNT = 650
adjectives = ["Premium", "Classic", "Pro", "Ultra", "Compact", "Deluxe", "Essential", "Smart", "Eco", "Portable"]
nouns_by_cat_hint = ["Series", "Edition", "Kit", "Set", "Model", "Collection"]
prod_rows = []
used_skus = set()
for i in range(PRODUCT_COUNT):
    cat_id = random.choice(leaf_category_ids)
    sup_id = random.choice(supplier_ids)
    name = f"{random.choice(adjectives)} {fake.word().capitalize()} {random.choice(nouns_by_cat_hint)} {random.randint(100,999)}"
    sku = f"SKU-{fake.unique.bothify(text='??####').upper()}"
    cost = round(random.uniform(5, 800), 2)
    price = round(cost * random.uniform(1.25, 2.2), 2)
    prod_rows.append((name, cat_id, sup_id, sku, fake.sentence(nb_words=12),
                       price, cost, round(random.uniform(0.1, 25), 2), True))
batch_insert(
    """INSERT INTO products (product_name, category_id, supplier_id, sku, description,
       unit_price, cost_price, weight_kg, is_active) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    prod_rows)
cur.execute("SELECT product_id, unit_price FROM products")
product_rows_db = cur.fetchall()
product_ids = [r[0] for r in product_rows_db]
product_price = {r[0]: float(r[1]) for r in product_rows_db}
print(f"Products created: {len(product_ids)}")

# ------------------------------------------------------------------
# 6. INVENTORY (each product stocked in 1-3 warehouses)
# ------------------------------------------------------------------
inv_rows = []
seen_pairs = set()
for pid in product_ids:
    n_wh = random.randint(1, 3)
    chosen = random.sample(warehouse_ids, n_wh)
    for wid in chosen:
        if (pid, wid) in seen_pairs:
            continue
        seen_pairs.add((pid, wid))
        qty = random.randint(0, 500)
        inv_rows.append((pid, wid, qty, random.randint(10, 40), random.randint(50, 150),
                          fake.date_between(start_date="-90d", end_date="today")))
batch_insert(
    """INSERT INTO inventory (product_id, warehouse_id, quantity_on_hand, reorder_level,
       reorder_quantity, last_restock_date) VALUES (%s,%s,%s,%s,%s,%s)""",
    inv_rows)
print(f"Inventory rows created: {len(inv_rows)}")

# ------------------------------------------------------------------
# 7. CUSTOMERS (>= 1000)
# ------------------------------------------------------------------
CUSTOMER_COUNT = 1500
cust_rows = []
segments = ["New", "Regular", "Regular", "VIP", "Churned"]
for _ in range(CUSTOMER_COUNT):
    reg_date = fake.date_between(start_date="-4y", end_date="today")
    cust_rows.append((fake.first_name(), fake.last_name(), fake.unique.email(),
                       fake.phone_number()[:20],
                       fake.date_of_birth(minimum_age=18, maximum_age=70),
                       random.choice(["Male", "Female", "Other", "Prefer not to say"]),
                       reg_date, random.choice(segments), True))
batch_insert(
    """INSERT INTO customers (first_name, last_name, email, phone, date_of_birth, gender,
       registration_date, customer_segment, is_active) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    cust_rows)
cur.execute("SELECT customer_id, registration_date FROM customers")
cust_db = cur.fetchall()
customer_ids = [r[0] for r in cust_db]
customer_regdate = {r[0]: r[1] for r in cust_db}
print(f"Customers created: {len(customer_ids)}")

# ------------------------------------------------------------------
# 8. CUSTOMER ADDRESSES (1-2 per customer)
# ------------------------------------------------------------------
addr_rows = []
for cid in customer_ids:
    n = random.choice([1, 1, 2])
    for j in range(n):
        addr_rows.append((cid, random.choice(["Billing", "Shipping", "Both"]),
                           fake.street_address(), fake.secondary_address() if random.random() < 0.3 else None,
                           fake.city(), fake.state(), fake.country(), fake.postcode(),
                           j == 0))
batch_insert(
    """INSERT INTO customer_addresses (customer_id, address_type, address_line1, address_line2,
       city, state, country, postal_code, is_default) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    addr_rows)
cur.execute("SELECT address_id, customer_id FROM customer_addresses")
addr_by_customer = {}
for aid, cid in cur.fetchall():
    addr_by_customer.setdefault(cid, []).append(aid)
print(f"Addresses created: {len(addr_rows)}")

conn.commit()
print("PHASE 1 (master data) complete.")
