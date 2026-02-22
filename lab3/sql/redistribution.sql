CREATE TABLE orders_new (
    order_id           BIGINT        NOT NULL,
    created_at         TIMESTAMP     NOT NULL,
    website_session_id BIGINT        NOT NULL,
    user_id            BIGINT        NOT NULL,
    primary_product_id INT,
    items_purchased    SMALLINT      NOT NULL DEFAULT 1,
    price_usd          NUMERIC(10,2) NOT NULL,
    cogs_usd           NUMERIC(10,2) NOT NULL
)
DISTRIBUTED BY (website_session_id);

INSERT INTO orders_new SELECT * FROM orders;
DROP TABLE orders;
ALTER TABLE orders_new RENAME TO orders;

CREATE TABLE order_item_refunds_new (
    order_item_refund_id BIGINT        NOT NULL,
    created_at           TIMESTAMP     NOT NULL,
    order_item_id        BIGINT        NOT NULL,
    order_id             BIGINT        NOT NULL,
    refund_amount_usd    NUMERIC(10,2) NOT NULL
)
DISTRIBUTED BY (order_id);

INSERT INTO order_item_refunds_new SELECT * FROM order_item_refunds;
DROP TABLE order_item_refunds;
ALTER TABLE order_item_refunds_new RENAME TO order_item_refunds;
