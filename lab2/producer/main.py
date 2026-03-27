import csv
import json
import logging
import os
import time

from kafka import KafkaProducer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

KAFKA_BROKER = os.getenv("KAFKA_BROKER")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC")
SEND_INTERVAL = float(os.getenv("SEND_INTERVAL"))
DATA_PATH = os.getenv("DATA_PATH")


# Загружаем CSV-файл в список словарей
def load_dataset(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    logger.info("Загружено %d строк из %s", len(rows), path)
    return rows


# Циклическая отправка строк в Kafka
def send_rows(producer, rows):
    idx = 0
    while True:
        row = rows[idx]
        message = {
            "Region": row.get("Region", ""),
            "Country": row.get("Country", ""),
            "State": row.get("State", ""),
            "City": row.get("City", ""),
            "Month": int(row.get("Month", 0)),
            "Day": int(row.get("Day", 0)),
            "Year": int(row.get("Year", 0)),
            "AvgTemperature": float(row.get("AvgTemperature", 0)),
        }

        producer.send(KAFKA_TOPIC, value=message)

        if idx % 1000 == 0:
            logger.info(
                "Отправлено сообщение #%d: %s, %s",
                idx,
                message["City"],
                message["Country"],
            )

        idx += 1
        if idx >= len(rows):
            # Данные закончились, начинаем сначала
            logger.info("Датасет закончился, начинаем с начала")
            idx = 0

        time.sleep(SEND_INTERVAL)


if __name__ == "__main__":
    logger.info("Запуск продюсера")
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BROKER,
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
    )
    logger.info("Подключение к Kafka установлено")
    rows = load_dataset(DATA_PATH)
    send_rows(producer, rows)
