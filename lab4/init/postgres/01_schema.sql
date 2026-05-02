CREATE TABLE categories (
    category_id INT PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    name TEXT,
    email TEXT,
    city TEXT,
    created_at TIMESTAMP
);

CREATE TABLE products (
    product_id INT PRIMARY KEY,
    sku TEXT,
    title TEXT,
    category_id INT REFERENCES categories(category_id),
    base_price NUMERIC(10,2)
);

CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    customer_id INT REFERENCES customers(customer_id),
    order_ts TIMESTAMP,
    status TEXT,
    total_amount NUMERIC(12,2)
);

CREATE TABLE order_items (
    order_id INT REFERENCES orders(order_id),
    product_id INT REFERENCES products(product_id),
    qty INT,
    price NUMERIC(10,2)
);

COPY categories FROM '/data/csv/categories.csv' WITH (FORMAT csv, HEADER true);
COPY customers FROM '/data/csv/customers.csv' WITH (FORMAT csv, HEADER true);
COPY products FROM '/data/csv/products.csv' WITH (FORMAT csv, HEADER true);
COPY orders FROM '/data/csv/orders.csv' WITH (FORMAT csv, HEADER true);
COPY order_items FROM '/data/csv/order_items.csv' WITH (FORMAT csv, HEADER true);

CREATE INDEX ON orders(customer_id);
CREATE INDEX ON order_items(order_id);
CREATE INDEX ON order_items(product_id);
CREATE INDEX ON products(category_id);
