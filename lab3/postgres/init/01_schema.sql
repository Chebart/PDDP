CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    product_name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS website_sessions (
    website_session_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    user_id BIGINT NOT NULL,
    is_repeat_session SMALLINT NOT NULL DEFAULT 0,
    utm_source VARCHAR(50),
    utm_campaign VARCHAR(50),
    utm_content VARCHAR(50),
    device_type VARCHAR(20),
    http_referer VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS website_pageviews (
    website_pageview_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    website_session_id BIGINT NOT NULL REFERENCES website_sessions(website_session_id),
    pageview_url VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
    order_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    website_session_id BIGINT NOT NULL REFERENCES website_sessions(website_session_id),
    user_id BIGINT NOT NULL,
    primary_product_id INT REFERENCES products(product_id),
    items_purchased SMALLINT NOT NULL DEFAULT 1,
    price_usd NUMERIC(10,2) NOT NULL,
    cogs_usd NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS order_items (
    order_item_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    order_id BIGINT NOT NULL REFERENCES orders(order_id),
    product_id INT NOT NULL REFERENCES products(product_id),
    is_primary_item SMALLINT NOT NULL DEFAULT 1,
    price_usd NUMERIC(10,2) NOT NULL,
    cogs_usd NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS order_item_refunds (
    order_item_refund_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    order_item_id BIGINT NOT NULL REFERENCES order_items(order_item_id),
    order_id BIGINT NOT NULL REFERENCES orders(order_id),
    refund_amount_usd NUMERIC(10,2) NOT NULL
);