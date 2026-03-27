import logging
import os

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    avg,
    col,
    count,
    from_json,
    udf,
)
from pyspark.sql.types import (
    DoubleType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

KAFKA_BROKER = os.getenv("KAFKA_BROKER")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC")
PG_HOST = os.getenv("POSTGRES_HOST")
PG_PORT = os.getenv("POSTGRES_PORT")
PG_DB = os.getenv("POSTGRES_DB")
PG_USER = os.getenv("POSTGRES_USER")
PG_PASSWORD = os.getenv("POSTGRES_PASSWORD")
JDBC_URL = f"jdbc:postgresql://{PG_HOST}:{PG_PORT}/{PG_DB}"

SCHEMA = StructType([
    StructField("Region", StringType()),
    StructField("Country", StringType()),
    StructField("State", StringType()),
    StructField("City", StringType()),
    StructField("Month", IntegerType()),
    StructField("Day", IntegerType()),
    StructField("Year", IntegerType()),
    StructField("AvgTemperature", DoubleType()),
])


# Конвертация температуры из Фаренгейта в Цельсий
@udf(DoubleType())
def fahrenheit_to_celsius(temp_f):
    if temp_f is None:
        return None
    return round((temp_f - 32) * 5.0 / 9.0, 2)

# Запись DataFrame в таблицу PostgreSQL через JDBC
def write_to_postgres(df, table):
    df.write \
        .format("jdbc") \
        .option("url", JDBC_URL) \
        .option("dbtable", table) \
        .option("user", PG_USER) \
        .option("password", PG_PASSWORD) \
        .option("driver", "org.postgresql.Driver") \
        .mode("append") \
        .save()


def process_batch(batch_df, batch_id):
    if batch_df.isEmpty():
        return

    logger.info("Обработка батча #%d, строк: %d", batch_id, batch_df.count())

    VALID_REGIONS = ["Europe", "Asia", "Africa"]
    # Фильтрация: убираем невалидные температуры и оставляем только нужные регионы
    filtered = batch_df.filter(
        (col("AvgTemperature") > -60) & col("Region").isin(VALID_REGIONS)
    )

    if filtered.isEmpty():
        logger.info("Батч #%d: после фильтрации не осталось данных", batch_id)
        return

    # Применяем UDF для конвертации температуры
    enriched = filtered.withColumn(
        "avg_temperature_c", fahrenheit_to_celsius(col("AvgTemperature"))
    )

    # Сохраняем обогащённые записи в таблицу city_temperatures
    city_df = enriched.select(
        col("Region").alias("region"),
        col("Country").alias("country"),
        col("State").alias("state"),
        col("City").alias("city"),
        col("Month").alias("month"),
        col("Day").alias("day"),
        col("Year").alias("year"),
        col("AvgTemperature").alias("avg_temperature_f"),
        col("avg_temperature_c"),
    )
    write_to_postgres(city_df, "city_temperatures")

    # Агрегация: средняя температура по региону и стране
    agg_df = enriched.groupBy("Region", "Country").agg(
        avg("avg_temperature_c").alias("avg_temp_celsius"),
        count("*").alias("record_count"),
    )
    agg_df = agg_df.select(
        col("Region").alias("region"),
        col("Country").alias("country"),
        col("avg_temp_celsius"),
        col("record_count"),
    )
    write_to_postgres(agg_df, "avg_temperatures")

    logger.info("Батч #%d успешно обработан", batch_id)


if __name__ == "__main__":
    logger.info("Запуск Spark-приложения")

    spark = SparkSession.builder \
        .appName("TemperatureStreaming") \
        .getOrCreate()

    spark.sparkContext.setLogLevel("WARN")

    # Чтение потока данных из Kafka
    raw_stream = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_BROKER) \
        .option("subscribe", KAFKA_TOPIC) \
        .option("startingOffsets", "earliest") \
        .option("failOnDataLoss", "false") \
        .load()

    # Парсинг JSON-сообщений из Kafka
    parsed_stream = raw_stream.select(
        from_json(col("value").cast("string"), SCHEMA).alias("data")
    ).select("data.*")

    # Запускаем стриминговый запрос с обработкой батчами
    query = parsed_stream.writeStream \
        .foreachBatch(process_batch) \
        .outputMode("update") \
        .option("checkpointLocation", "/tmp/spark-checkpoint") \
        .trigger(processingTime="10 seconds") \
        .start()

    logger.info("Стриминговый запрос запущен, ожидаем данные...")
    query.awaitTermination()
