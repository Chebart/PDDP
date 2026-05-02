WITH stage_sessions AS (
    SELECT page, COUNT(DISTINCT session_id) AS sessions
    FROM hive.lake.clickstream
    WHERE page IN ('home', 'category', 'product', 'cart', 'checkout')
    GROUP BY page
),
stages(step, stage) AS (
    VALUES (1, 'home'), (2, 'category'), (3, 'product'), (4, 'cart'), (5, 'checkout')
),
joined AS (
    SELECT
        s.step,
        s.stage,
        COALESCE(ss.sessions, 0) AS sessions,
        LAG(COALESCE(ss.sessions, 0)) OVER (ORDER BY s.step) AS prev_sessions,
        FIRST_VALUE(COALESCE(ss.sessions, 0)) OVER (ORDER BY s.step) AS top_sessions
    FROM stages s
    LEFT JOIN stage_sessions ss ON ss.page = s.stage
)
SELECT
    step,
    stage,
    sessions,
    ROUND(sessions * 1.0 / NULLIF(prev_sessions, 0), 4) AS step_share,
    ROUND(sessions * 1.0 / NULLIF(top_sessions, 0), 4) AS share_of_home
FROM joined
ORDER BY step;

WITH cust AS (
    SELECT
        customer_id,
        BOOL_OR(page = 'home') AS h,
        BOOL_OR(page = 'category') AS c,
        BOOL_OR(page = 'product') AS p,
        BOOL_OR(page = 'cart') AS ca,
        BOOL_OR(page = 'checkout') AS ch
    FROM hive.lake.clickstream
    GROUP BY customer_id
),
funnel AS (
    SELECT
        COUNT_IF(h) AS home,
        COUNT_IF(h AND c) AS category,
        COUNT_IF(h AND c AND p) AS product,
        COUNT_IF(h AND c AND p AND ca) AS cart,
        COUNT_IF(h AND c AND p AND ca AND ch) AS checkout
    FROM cust
),
steps AS (
    SELECT step, stage, customers
    FROM funnel
    CROSS JOIN UNNEST(
        ARRAY[1, 2, 3, 4, 5],
        ARRAY['home', 'category', 'product', 'cart', 'checkout'],
        ARRAY[home, category, product, cart, checkout]
    ) AS t(step, stage, customers)
)
SELECT
    step,
    stage,
    customers,
    ROUND(customers * 1.0 / NULLIF(LAG(customers) OVER (ORDER BY step), 0), 4) AS step_retention,
    ROUND(customers * 1.0 / NULLIF(FIRST_VALUE(customers) OVER (ORDER BY step), 0), 4) AS overall_retention
FROM steps
ORDER BY step;
