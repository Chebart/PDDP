\COPY products FROM '/data/products.csv' CSV HEADER;
\COPY website_sessions FROM '/data/website_sessions.csv' CSV HEADER;
\COPY website_pageviews FROM '/data/website_pageviews.csv' CSV HEADER;
\COPY orders FROM '/data/orders.csv' CSV HEADER;
\COPY order_items FROM '/data/order_items.csv' CSV HEADER;
\COPY order_item_refunds FROM '/data/order_item_refunds.csv' CSV HEADER;
