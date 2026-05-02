SELECT
    o.order_id,
    o.customer_id,
    c.city,
    o.order_ts,
    o.status,
    o.total_amount,
    COALESCE(SUM(oi.qty), 0) AS items_cnt,
    COUNT(DISTINCT oi.product_id) AS distinct_products_cnt
FROM postgres.public.orders o
JOIN postgres.public.customers c ON c.customer_id = o.customer_id
LEFT JOIN postgres.public.order_items oi ON oi.order_id = o.order_id
GROUP BY
    o.order_id, o.customer_id, c.city, o.order_ts, o.status, o.total_amount
ORDER BY o.order_id;
