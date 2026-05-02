SELECT
    cat.category_id,
    cat.name AS category_name,
    SUM(oi.qty * oi.price) AS revenue,
    COUNT(DISTINCT oi.order_id) AS orders_with_category,
    COUNT(DISTINCT p.product_id) AS products_sold
FROM postgres.public.order_items oi
JOIN postgres.public.products p ON p.product_id = oi.product_id
JOIN postgres.public.categories cat ON cat.category_id = p.category_id
GROUP BY cat.category_id, cat.name
ORDER BY revenue DESC
LIMIT 10;
