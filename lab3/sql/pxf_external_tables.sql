CREATE EXTENSION IF NOT EXISTS pxf;

DROP EXTERNAL TABLE IF EXISTS ext_products;
CREATE EXTERNAL TABLE ext_products (
    product_id   INT,
    created_at   TIMESTAMP,
    product_name VARCHAR(100)
)
LOCATION ('pxf://public.products?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

DROP EXTERNAL TABLE IF EXISTS ext_website_sessions;
CREATE EXTERNAL TABLE ext_website_sessions (
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
LOCATION ('pxf://public.website_sessions?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

DROP EXTERNAL TABLE IF EXISTS ext_website_pageviews;
CREATE EXTERNAL TABLE ext_website_pageviews (
    website_pageview_id BIGINT,
    created_at          TIMESTAMP,
    website_session_id  BIGINT,
    pageview_url        VARCHAR(100)
)
LOCATION ('pxf://public.website_pageviews?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

DROP EXTERNAL TABLE IF EXISTS ext_orders;
CREATE EXTERNAL TABLE ext_orders (
    order_id           BIGINT,
    created_at         TIMESTAMP,
    website_session_id BIGINT,
    user_id            BIGINT,
    primary_product_id INT,
    items_purchased    SMALLINT,
    price_usd          NUMERIC(10,2),
    cogs_usd           NUMERIC(10,2)
)
LOCATION ('pxf://public.orders?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

DROP EXTERNAL TABLE IF EXISTS ext_order_items;
CREATE EXTERNAL TABLE ext_order_items (
    order_item_id   BIGINT,
    created_at      TIMESTAMP,
    order_id        BIGINT,
    product_id      INT,
    is_primary_item SMALLINT,
    price_usd       NUMERIC(10,2),
    cogs_usd        NUMERIC(10,2)
)
LOCATION ('pxf://public.order_items?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

DROP EXTERNAL TABLE IF EXISTS ext_order_item_refunds;
CREATE EXTERNAL TABLE ext_order_item_refunds (
    order_item_refund_id BIGINT,
    created_at           TIMESTAMP,
    order_item_id        BIGINT,
    order_id             BIGINT,
    refund_amount_usd    NUMERIC(10,2)
)
LOCATION ('pxf://public.order_item_refunds?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');