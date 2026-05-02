WITH stage_sessions AS (
    SELECT page, COUNT(DISTINCT session_id) AS sessions
    FROM hive.lake.clickstream
    WHERE page IN ('home', 'category', 'product', 'cart', 'checkout')
    GROUP BY page
),
stages AS (
    SELECT 1 AS step, 'home' AS stage UNION ALL
    SELECT 2, 'category' UNION ALL
    SELECT 3, 'product' UNION ALL
    SELECT 4, 'cart' UNION ALL
    SELECT 5, 'checkout'
),
joined AS (
    SELECT
        s.step,
        s.stage,
        COALESCE(ss.sessions, 0) AS sessions,
        LAG(COALESCE(ss.sessions, 0)) OVER (ORDER BY s.step) AS prev_sessions,
        FIRST_VALUE(COALESCE(ss.sessions, 0))
            OVER (ORDER BY s.step ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS top_sessions
    FROM stages s
    LEFT JOIN stage_sessions ss ON ss.page = s.stage
)
SELECT
    step,
    stage,
    sessions,
    ROUND(sessions * 1.0 / NULLIF(prev_sessions, 0), 4) AS step_share,
    ROUND(sessions * 1.0 / NULLIF((SELECT sessions FROM joined WHERE step = 1), 0), 4) AS share_of_home
FROM joined
ORDER BY step;

WITH cust AS (
    SELECT
        customer_id,
        MAX(CASE WHEN page = 'home' THEN 1 ELSE 0 END) AS h,
        MAX(CASE WHEN page = 'category' THEN 1 ELSE 0 END) AS c,
        MAX(CASE WHEN page = 'product' THEN 1 ELSE 0 END) AS p,
        MAX(CASE WHEN page = 'cart' THEN 1 ELSE 0 END) AS ca,
        MAX(CASE WHEN page = 'checkout' THEN 1 ELSE 0 END) AS ch
    FROM hive.lake.clickstream
    GROUP BY customer_id
),
funnel AS (
    SELECT
        SUM(h) AS home,
        SUM(CASE WHEN h = 1 AND c = 1 THEN 1 ELSE 0 END) AS category,
        SUM(CASE WHEN h = 1 AND c = 1 AND p = 1 THEN 1 ELSE 0 END) AS product,
        SUM(CASE WHEN h = 1 AND c = 1 AND p = 1 AND ca = 1 THEN 1 ELSE 0 END) AS cart,
        SUM(CASE WHEN h = 1 AND c = 1 AND p = 1 AND ca = 1 AND ch = 1 THEN 1 ELSE 0 END) AS checkout
    FROM cust
),
stages AS (
    SELECT 1 AS step, 'home' AS stage, home AS customers, CAST(NULL AS BIGINT) AS prev FROM funnel UNION ALL
    SELECT 2, 'category', category, home FROM funnel UNION ALL
    SELECT 3, 'product', product, category FROM funnel UNION ALL
    SELECT 4, 'cart', cart, product FROM funnel UNION ALL
    SELECT 5, 'checkout', checkout, cart FROM funnel
)
SELECT
    step,
    stage,
    customers,
    ROUND(customers * 1.0 / NULLIF(prev, 0), 4) AS step_retention,
    ROUND(customers * 1.0 / NULLIF((SELECT home FROM funnel), 0), 4) AS overall_retention
FROM stages
ORDER BY step;
