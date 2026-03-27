CREATE TABLE IF NOT EXISTS city_temperatures (
    id SERIAL PRIMARY KEY,
    region VARCHAR(100),
    country VARCHAR(100),
    state VARCHAR(100),
    city VARCHAR(200),
    month INT,
    day INT,
    year INT,
    avg_temperature_f DOUBLE PRECISION,
    avg_temperature_c DOUBLE PRECISION,
    batch_time TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS avg_temperatures (
    id SERIAL PRIMARY KEY,
    region VARCHAR(100),
    country VARCHAR(100),
    avg_temp_celsius DOUBLE PRECISION,
    record_count BIGINT,
    batch_time TIMESTAMP DEFAULT NOW()
);
