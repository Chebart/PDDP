CREATE SCHEMA IF NOT EXISTS hive.lake
WITH (location = 's3a://lake/');

DROP TABLE IF EXISTS hive.lake.clickstream;
CREATE TABLE hive.lake.clickstream (
    dt            VARCHAR,
    session_id    VARCHAR,
    customer_id   VARCHAR,
    page          VARCHAR,
    product_id    VARCHAR,
    duration_sec  VARCHAR
)
WITH (
    format = 'CSV',
    skip_header_line_count = 1,
    external_location = 's3a://lake/clickstream/'
);

DROP TABLE IF EXISTS hive.lake.product_media_metadata;
CREATE TABLE hive.lake.product_media_metadata (
    product_id   VARCHAR,
    image_path   VARCHAR,
    manual_path  VARCHAR,
    updated_at   VARCHAR
)
WITH (
    format = 'CSV',
    skip_header_line_count = 1,
    external_location = 's3a://lake/product_media_metadata/'
);
