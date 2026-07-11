#!/usr/bin/env python3
"""
Enterprise Retail DB - Transactional Data Generator (Phase 2)
Requires Phase 1 (generate_data.py) to have run already.

Scale targets:
  orders      >= 5000
  order_items >= 15000
  reviews     >= 1000
"""
import random
import datetime
import mysql.connector
from faker import Faker
fake = Faker()
Faker.seed(7)
random.seed(7)

conn = mysql.connector.connect(host="127.0.0.1", user="retail_app", password="RetailApp123!",
                                database="retail_enterprise_db")
conn.autocommit = False
cur = conn.cursor()

def batch_insert(sql, rows, batch_size=2000):
    for i in range(0, len(rows), batch_size):
        cur.executemany(sql, rows[i:i + batch_size])
    conn.commit()

cur.execute("SELECT customer_id, registration_date FROM customers")
customers = cur.fetchall()  # (id, reg_date)

cur.execute("SELECT address_id, customer_id FROM customer_addresses")
addr_by_customer = {}
for aid, cid in cur.fetchall():
    addr_by_customer.setdefault(cid, []).append(aid)

cur.execute("SELECT product_id, unit_price FROM products")
products = cur.fetchall()
product_price = {r[0]: float(r[1]) for r in products}
product_ids = list(product_price.keys())

cur.execute("SELECT employee_id FROM employees WHERE department='Sales'")
sales_emp_ids = [r[0] for r in cur.fetchall()] or [None]

cur.execute("SELECT warehouse_id FROM warehouses")
warehouse_ids = [r[0] for r in cur.fetchall()]

ORDER_COUNT = 5800
STATUS_WEIGHTS = [("Delivered", 60), ("Shipped", 12), ("Processing", 8),
                   ("Pending", 8), ("Cancelled", 7), ("Returned", 5)]
statuses, weights = zip(*STATUS_WEIGHTS)

PAY_METHODS = ["Credit Card", "Debit Card", "UPI", "Net Banking", "Wallet", "Cash on Delivery"]
CARRIERS = ["BlueDart", "DHL Express", "FedEx", "Delhivery", "India Post", "Ekart"]

today = datetime.date.today()

order_rows = []
order_item_plan = []   # list of (order_idx, product_id, qty, unit_price, discount_pct)
order_meta = []         # (customer_id, order_date, status)

for i in range(ORDER_COUNT):
    cid, reg_date = random.choice(customers)
    if isinstance(reg_date, datetime.date):
        start = reg_date
    else:
        start = today - datetime.timedelta(days=730)
    order_date = fake.date_time_between(start_date=start, end_date="now")
    status = random.choices(statuses, weights=weights, k=1)[0]

    n_items = random.choices([1, 2, 3, 4, 5, 6], weights=[15, 20, 22, 20, 13, 10], k=1)[0]
    chosen_products = random.sample(product_ids, min(n_items, len(product_ids)))

    items = []
    subtotal = 0.0
    for pid in chosen_products:
        qty = random.randint(1, 4)
        price = product_price[pid]
        disc = random.choice([0, 0, 0, 5, 10, 15, 20])
        line_total = round(qty * price * (1 - disc / 100), 2)
        subtotal += line_total
        items.append((pid, qty, price, disc, line_total))

    tax = round(subtotal * 0.08, 2)
    shipping_fee = 0.0 if subtotal > 75 else round(random.uniform(3, 12), 2)
    discount_amount = round(subtotal * random.choice([0, 0, 0, 0.05, 0.1]), 2)
    total = round(subtotal + tax + shipping_fee - discount_amount, 2)

    addr_list = addr_by_customer.get(cid, [])
    ship_addr = random.choice(addr_list) if addr_list else None
    bill_addr = random.choice(addr_list) if addr_list else None
    emp_id = random.choice(sales_emp_ids) if random.random() < 0.6 else None

    order_rows.append((cid, emp_id, order_date, status, ship_addr, bill_addr,
                        subtotal, tax, shipping_fee, discount_amount, total))
    order_item_plan.append(items)
    order_meta.append((cid, order_date, status))

batch_insert(
    """INSERT INTO orders (customer_id, employee_id, order_date, order_status, shipping_address_id,
       billing_address_id, subtotal, tax_amount, shipping_fee, discount_amount, total_amount)
       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
    order_rows)

cur.execute("SELECT order_id FROM orders ORDER BY order_id")
order_ids = [r[0] for r in cur.fetchall()]
print(f"Orders created: {len(order_ids)}")

# ------------------------------------------------------------------
# ORDER ITEMS (>= 15000)
# ------------------------------------------------------------------
item_rows = []
order_item_ids_by_order = {}
for oid, items in zip(order_ids, order_item_plan):
    for (pid, qty, price, disc, line_total) in items:
        item_rows.append((oid, pid, qty, price, disc, line_total))
batch_insert(
    """INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_percent, line_total)
       VALUES (%s,%s,%s,%s,%s,%s)""",
    item_rows)
print(f"Order items created: {len(item_rows)}")

cur.execute("SELECT order_item_id, order_id, product_id FROM order_items")
oi_rows = cur.fetchall()
items_by_order = {}
for oi_id, oid, pid in oi_rows:
    items_by_order.setdefault(oid, []).append((oi_id, pid))

# ------------------------------------------------------------------
# PAYMENTS (1 per order, status tied to order status)
# ------------------------------------------------------------------
pay_rows = []
for oid, (cid, odate, status) in zip(order_ids, order_meta):
    if status == "Cancelled":
        pstatus = random.choice(["Failed", "Refunded"])
    elif status == "Returned":
        pstatus = "Refunded"
    elif status == "Pending":
        pstatus = random.choice(["Pending", "Success"])
    else:
        pstatus = "Success"
    method = random.choice(PAY_METHODS)
    cur.execute("SELECT total_amount FROM orders WHERE order_id=%s", (oid,))
    amt = cur.fetchone()[0]
    pay_rows.append((oid, method, pstatus, amt, fake.uuid4(), odate))
batch_insert(
    """INSERT INTO payments (order_id, payment_method, payment_status, amount, transaction_ref, payment_date)
       VALUES (%s,%s,%s,%s,%s,%s)""",
    pay_rows)
print(f"Payments created: {len(pay_rows)}")

# ------------------------------------------------------------------
# SHIPMENTS (skip Pending/Cancelled orders)
# ------------------------------------------------------------------
ship_rows = []
for oid, (cid, odate, status) in zip(order_ids, order_meta):
    if status in ("Pending", "Cancelled"):
        continue
    wid = random.choice(warehouse_ids)
    shipped = odate + datetime.timedelta(days=random.randint(0, 2))
    est_delivery = shipped + datetime.timedelta(days=random.randint(2, 7))
    if status == "Delivered":
        sstatus = "Delivered"
        actual = shipped + datetime.timedelta(days=random.randint(2, 8))
    elif status == "Returned":
        sstatus = "Delivered"
        actual = shipped + datetime.timedelta(days=random.randint(2, 8))
    elif status == "Shipped":
        sstatus = random.choice(["In Transit", "Out for Delivery"])
        actual = None
    else:
        sstatus = "Preparing"
        actual = None
    ship_rows.append((oid, wid, random.choice(CARRIERS), fake.bothify(text="TRK########??"),
                       shipped, est_delivery.date(), actual, sstatus))
batch_insert(
    """INSERT INTO shipments (order_id, warehouse_id, carrier, tracking_number, shipped_date,
       estimated_delivery_date, actual_delivery_date, shipment_status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
    ship_rows)
print(f"Shipments created: {len(ship_rows)}")

# ------------------------------------------------------------------
# REVIEWS (>= 1000) - only for Delivered/Returned orders
# ------------------------------------------------------------------
eligible_orders = [oid for oid, (cid, odate, status) in zip(order_ids, order_meta)
                    if status in ("Delivered", "Returned")]
review_rows = []
titles_pos = ["Great value!", "Exceeded expectations", "Highly recommend", "Solid purchase", "Works perfectly"]
titles_neg = ["Not as described", "Disappointed", "Could be better", "Average product", "Had issues"]
target_reviews = 1400
attempts = 0
seen_review_keys = set()
while len(review_rows) < target_reviews and attempts < target_reviews * 3:
    attempts += 1
    oid = random.choice(eligible_orders)
    items = items_by_order.get(oid)
    if not items:
        continue
    oi_id, pid = random.choice(items)
    key = (pid, oi_id)
    if key in seen_review_keys:
        continue
    seen_review_keys.add(key)
    # get customer id for this order
    cur.execute("SELECT customer_id, order_date FROM orders WHERE order_id=%s", (oid,))
    cid, odate = cur.fetchone()
    rating = random.choices([5, 4, 3, 2, 1], weights=[40, 28, 15, 10, 7], k=1)[0]
    title = random.choice(titles_pos) if rating >= 4 else random.choice(titles_neg)
    review_rows.append((pid, cid, oi_id, rating, title, fake.paragraph(nb_sentences=3),
                         odate + datetime.timedelta(days=random.randint(3, 20)), True))

batch_insert(
    """INSERT INTO reviews (product_id, customer_id, order_item_id, rating, review_title,
       review_text, review_date, is_verified_purchase) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
    review_rows)
print(f"Reviews created: {len(review_rows)}")

# ------------------------------------------------------------------
# RETURNS - for orders with status Returned
# ------------------------------------------------------------------
return_reasons = ["Item damaged on arrival", "Wrong item received", "Size/fit issue",
                   "No longer needed", "Item defective", "Better price found elsewhere"]
returned_orders = [oid for oid, (cid, odate, status) in zip(order_ids, order_meta) if status == "Returned"]
return_rows = []
for oid in returned_orders:
    items = items_by_order.get(oid, [])
    if not items:
        continue
    oi_id, pid = random.choice(items)
    cur.execute("SELECT customer_id, order_date, total_amount FROM orders WHERE order_id=%s", (oid,))
    cid, odate, total = cur.fetchone()
    ret_status = random.choice(["Refunded", "Completed", "Approved"])
    ret_date = odate + datetime.timedelta(days=random.randint(5, 15))
    processed = ret_date + datetime.timedelta(days=random.randint(1, 5)) if ret_status != "Requested" else None
    return_rows.append((oi_id, cid, random.choice(return_reasons), ret_status,
                         round(float(total) * random.uniform(0.3, 1.0), 2), ret_date, processed))
batch_insert(
    """INSERT INTO returns (order_item_id, customer_id, return_reason, return_status,
       refund_amount, return_date, processed_date) VALUES (%s,%s,%s,%s,%s,%s,%s)""",
    return_rows)
print(f"Returns created: {len(return_rows)}")

conn.commit()
cur.close()
conn.close()
print("PHASE 2 (transactional data) complete.")
