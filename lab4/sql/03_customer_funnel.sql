WITH events_agg AS (
    SELECT
        customer_id,
        COUNT_IF(event_type = 'view') AS view_cnt,
        COUNT_IF(event_type = 'add_to_cart') AS add_to_cart_cnt
    FROM mongodb.shop.events
    GROUP BY customer_id
),
orders_agg AS (
    SELECT
        customer_id,
        COUNT(*) AS orders_cnt,
        SUM(total_amount) AS total_amount
    FROM postgres.public.orders
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.city,
    COALESCE(e.view_cnt, 0) AS view_cnt,
    COALESCE(e.add_to_cart_cnt, 0) AS add_to_cart_cnt,
    COALESCE(o.orders_cnt, 0) AS orders_cnt,
    COALESCE(o.total_amount, 0) AS total_amount
FROM postgres.public.customers c
LEFT JOIN events_agg e ON e.customer_id = c.customer_id
LEFT JOIN orders_agg o ON o.customer_id = c.customer_id
ORDER BY c.customer_id;

WITH viewers AS (
    SELECT DISTINCT c.city, c.customer_id
    FROM postgres.public.customers c
    JOIN mongodb.shop.events e
      ON e.customer_id = c.customer_id
     AND e.event_type = 'view'
),
buyers AS (
    SELECT DISTINCT c.city, c.customer_id
    FROM postgres.public.customers c
    JOIN postgres.public.orders o
      ON o.customer_id = c.customer_id
     AND o.status IN ('paid', 'shipped', 'delivered')
),
city_metrics AS (
    SELECT city, COUNT(*) AS viewers
    FROM viewers
    GROUP BY city
),
city_buyers AS (
    SELECT city, COUNT(*) AS buyers
    FROM buyers
    GROUP BY city
)
SELECT
    cm.city,
    cm.viewers,
    COALESCE(cb.buyers, 0) AS buyers,
    ROUND(COALESCE(cb.buyers, 0) * 1.0 / NULLIF(cm.viewers, 0), 4) AS conversion_rate
FROM city_metrics cm
LEFT JOIN city_buyers cb ON cb.city = cm.city
ORDER BY conversion_rate DESC NULLS LAST;
