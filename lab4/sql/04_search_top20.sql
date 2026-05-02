WITH searches AS (
    SELECT
        customer_id,
        LOWER(CAST(payload.q AS varchar)) AS query
    FROM mongodb.shop.events
    WHERE event_type = 'search'
      AND payload.q IS NOT NULL
),
top20 AS (
    SELECT query, COUNT(*) AS searches_cnt
    FROM searches
    GROUP BY query
    ORDER BY searches_cnt DESC, query ASC
    LIMIT 20
),
search_users AS (
    SELECT DISTINCT s.query, s.customer_id
    FROM searches s
    JOIN top20 t ON t.query = s.query
)
SELECT
    t.query,
    t.searches_cnt,
    COUNT(DISTINCT su.customer_id) AS searchers,
    COUNT(DISTINCT o.order_id) AS orders_by_searchers,
    COALESCE(SUM(o.total_amount), 0) AS revenue_by_searchers
FROM top20 t
LEFT JOIN search_users su ON su.query = t.query
LEFT JOIN postgres.public.orders o
       ON o.customer_id = su.customer_id
      AND o.status IN ('paid', 'shipped', 'delivered')
GROUP BY t.query, t.searches_cnt
ORDER BY t.searches_cnt DESC;
