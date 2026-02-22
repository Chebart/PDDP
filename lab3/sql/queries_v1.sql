-- Q1: Revenue and profit by product
-- orders DISTRIBUTED BY (order_id), order_items DISTRIBUTED BY (order_id)
--   → orders↔order_items join is LOCAL
-- products DISTRIBUTED BY (product_id)
--   → order_items↔products causes BROADCAST MOTION (small table)
EXPLAIN (ANALYZE, VERBOSE, COSTS ON)
SELECT
    p.product_name,
    COUNT(DISTINCT o.order_id) AS num_orders,
    SUM(oi.price_usd) AS total_revenue,
    SUM(oi.cogs_usd) AS total_cogs,
    SUM(oi.price_usd - oi.cogs_usd) AS total_profit,
    ROUND(SUM(oi.price_usd - oi.cogs_usd) * 100.0 / NULLIF(SUM(oi.price_usd), 0), 2) AS margin_pct
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_name
ORDER BY total_revenue DESC;

-- Q2: Session-to-order conversion rate by UTM source and device type
-- website_sessions DISTRIBUTED BY (website_session_id)
-- orders DISTRIBUTED BY (order_id)
--   → join key website_session_id is not the dist key of orders
--   → REDISTRIBUTE MOTION on orders
EXPLAIN (ANALYZE, VERBOSE, COSTS ON)
SELECT
    ws.utm_source,
    ws.device_type,
    COUNT(DISTINCT ws.website_session_id) AS total_sessions,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0 / NULLIF(COUNT(DISTINCT ws.website_session_id), 0), 2) AS conversion_pct
FROM website_sessions ws
LEFT JOIN orders o ON o.website_session_id = ws.website_session_id
GROUP BY ws.utm_source, ws.device_type
ORDER BY total_sessions DESC;

-- Q3: Refund rate by product
-- order_items DISTRIBUTED BY (order_id)
-- order_item_refunds DISTRIBUTED BY (order_item_id) — intentional mismatch
--   → join on order_item_id causes REDISTRIBUTE MOTION on order_items
--   → products causes BROADCAST MOTION
EXPLAIN (ANALYZE, VERBOSE, COSTS ON)
SELECT
    p.product_name,
    COUNT(oi.order_item_id) AS items_sold,
    COUNT(r.order_item_refund_id) AS items_refunded,
    ROUND(COUNT(r.order_item_refund_id) * 100.0 / NULLIF(COUNT(oi.order_item_id), 0), 2) AS refund_rate_pct,
    COALESCE(SUM(r.refund_amount_usd), 0) AS total_refunded_usd
FROM products p
JOIN order_items oi ON oi.product_id = p.product_id
LEFT JOIN order_item_refunds r ON r.order_item_id = oi.order_item_id
GROUP BY p.product_name
ORDER BY refund_rate_pct DESC NULLS LAST;
