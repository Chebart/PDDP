DROP EXTERNAL TABLE IF EXISTS ext_gpfdist_products;
CREATE EXTERNAL TABLE ext_gpfdist_products (
    product_id   INT,
    created_at   TIMESTAMP,
    product_name VARCHAR(100)
)
LOCATION ('gpfdist://gpfdist:8080/products.csv')
FORMAT 'CSV' (HEADER);

DROP EXTERNAL TABLE IF EXISTS ext_gpfdist_website_sessions;
CREATE EXTERNAL TABLE ext_gpfdist_website_sessions (
    website_session_id BIGINT,
    created_at         TIMESTAMP,
    user_id            BIGINT,
    is_repeat_session  SMALLINT,
    utm_source         VARCHAR(50),
    utm_campaign       VARCHAR(50),
    utm_content        VARCHAR(50),
    device_type        VARCHAR(20),
    http_referer       VARCHAR(200)
)
LOCATION ('gpfdist://gpfdist:8080/website_sessions.csv')
FORMAT 'CSV' (HEADER);

DROP EXTERNAL TABLE IF EXISTS ext_gpfdist_orders;
CREATE EXTERNAL TABLE ext_gpfdist_orders (
    order_id           BIGINT,
    created_at         TIMESTAMP,
    website_session_id BIGINT,
    user_id            BIGINT,
    primary_product_id INT,
    items_purchased    SMALLINT,
    price_usd          NUMERIC(10,2),
    cogs_usd           NUMERIC(10,2)
)
LOCATION ('gpfdist://gpfdist:8080/orders.csv')
FORMAT 'CSV' (HEADER);

DROP EXTERNAL TABLE IF EXISTS ext_gpfdist_order_items;
CREATE EXTERNAL TABLE ext_gpfdist_order_items (
    order_item_id   BIGINT,
    created_at      TIMESTAMP,
    order_id        BIGINT,
    product_id      INT,
    is_primary_item SMALLINT,
    price_usd       NUMERIC(10,2),
    cogs_usd        NUMERIC(10,2)
)
LOCATION ('gpfdist://gpfdist:8080/order_items.csv')
FORMAT 'CSV' (HEADER);

DROP EXTERNAL TABLE IF EXISTS ext_gpfdist_order_item_refunds;
CREATE EXTERNAL TABLE ext_gpfdist_order_item_refunds (
    order_item_refund_id BIGINT,
    created_at           TIMESTAMP,
    order_item_id        BIGINT,
    order_id             BIGINT,
    refund_amount_usd    NUMERIC(10,2)
)
LOCATION ('gpfdist://gpfdist:8080/order_item_refunds.csv')
FORMAT 'CSV' (HEADER);