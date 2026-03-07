ALTER TABLE orders
    SET WITH (REORGANIZE=TRUE)
    DISTRIBUTED BY (website_session_id);

ALTER TABLE order_item_refunds
    SET WITH (REORGANIZE=TRUE)
    DISTRIBUTED BY (order_id);
