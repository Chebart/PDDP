-- Row count and percentage per segment for each table
WITH seg_counts AS (
    SELECT 'products' AS tbl, gp_segment_id, COUNT(*) AS rows FROM products GROUP BY gp_segment_id
    UNION ALL
    SELECT 'website_sessions', gp_segment_id, COUNT(*) FROM website_sessions GROUP BY gp_segment_id
    UNION ALL
    SELECT 'website_pageviews', gp_segment_id, COUNT(*) FROM website_pageviews GROUP BY gp_segment_id
    UNION ALL
    SELECT 'orders', gp_segment_id, COUNT(*) FROM orders GROUP BY gp_segment_id
    UNION ALL
    SELECT 'order_items', gp_segment_id, COUNT(*) FROM order_items GROUP BY gp_segment_id
    UNION ALL
    SELECT 'order_item_refunds', gp_segment_id, COUNT(*) FROM order_item_refunds GROUP BY gp_segment_id
),
totals AS (
    SELECT tbl, SUM(rows) AS total FROM seg_counts GROUP BY tbl
)
SELECT
    sc.tbl,
    sc.gp_segment_id AS segment,
    sc.rows,
    ROUND(sc.rows * 100.0 / t.total, 2) AS pct
FROM seg_counts sc
JOIN totals t USING (tbl)
ORDER BY tbl, segment;

-- Skew coefficient: (max - min) / avg * 100, values > 10 indicate notable skew
WITH seg_counts AS (
    SELECT 'products' AS tbl, gp_segment_id, COUNT(*) AS rows FROM products GROUP BY gp_segment_id
    UNION ALL
    SELECT 'website_sessions', gp_segment_id, COUNT(*) FROM website_sessions GROUP BY gp_segment_id
    UNION ALL
    SELECT 'orders', gp_segment_id, COUNT(*) FROM orders GROUP BY gp_segment_id
    UNION ALL
    SELECT 'order_items', gp_segment_id, COUNT(*) FROM order_items GROUP BY gp_segment_id
    UNION ALL
    SELECT 'order_item_refunds', gp_segment_id, COUNT(*) FROM order_item_refunds GROUP BY gp_segment_id
)
SELECT
    tbl,
    MIN(rows) AS min_rows,
    MAX(rows) AS max_rows,
    ROUND(AVG(rows), 1) AS avg_rows,
    ROUND((MAX(rows) - MIN(rows)) * 100.0 / NULLIF(AVG(rows), 0), 2) AS skew_pct
FROM seg_counts
GROUP BY tbl
ORDER BY skew_pct DESC;
