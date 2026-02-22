DROP TABLE IF EXISTS order_item_refunds CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS website_pageviews CASCADE;
DROP TABLE IF EXISTS website_sessions CASCADE;
DROP TABLE IF EXISTS products CASCADE;

CREATE TABLE products (
    product_id INT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    product_name VARCHAR(100) NOT NULL
)
DISTRIBUTED BY (product_id);

CREATE TABLE website_sessions (
    website_session_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    user_id BIGINT NOT NULL,
    is_repeat_session SMALLINT NOT NULL DEFAULT 0,
    utm_source VARCHAR(50),
    utm_campaign VARCHAR(50),
    utm_content VARCHAR(50),
    device_type VARCHAR(20),
    http_referer VARCHAR(200)
)
DISTRIBUTED BY (website_session_id);

CREATE TABLE website_pageviews (
    website_pageview_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    website_session_id BIGINT NOT NULL,
    pageview_url VARCHAR(100) NOT NULL
)
DISTRIBUTED BY (website_session_id);

CREATE TABLE orders (
    order_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    website_session_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    primary_product_id INT,
    items_purchased SMALLINT NOT NULL DEFAULT 1,
    price_usd NUMERIC(10,2) NOT NULL,
    cogs_usd NUMERIC(10,2) NOT NULL
)
DISTRIBUTED BY (order_id);

CREATE TABLE order_items (
    order_item_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    order_id BIGINT NOT NULL,
    product_id INT NOT NULL,
    is_primary_item SMALLINT NOT NULL DEFAULT 1,
    price_usd NUMERIC(10,2) NOT NULL,
    cogs_usd NUMERIC(10,2) NOT NULL
)
DISTRIBUTED BY (order_id);

CREATE TABLE order_item_refunds (
    order_item_refund_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    order_item_id BIGINT NOT NULL,
    order_id BIGINT NOT NULL,
    refund_amount_usd NUMERIC(10,2) NOT NULL
)
DISTRIBUTED BY (order_item_id);

-- Load from PXF external tables
INSERT INTO products SELECT * FROM ext_products;
INSERT INTO website_sessions SELECT * FROM ext_website_sessions;
INSERT INTO website_pageviews SELECT * FROM ext_website_pageviews;
INSERT INTO orders SELECT * FROM ext_orders;
INSERT INTO order_items SELECT * FROM ext_order_items;
INSERT INTO order_item_refunds SELECT * FROM ext_order_item_refunds;
