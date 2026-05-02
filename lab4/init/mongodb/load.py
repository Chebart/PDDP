import csv
import json
import os
import sys
from datetime import datetime

from pymongo import MongoClient

URI = os.environ.get("MONGO_URI", "mongodb://root:root@mongodb:27017/?authSource=admin")
CSV_PATH = "/csv/events.csv"

client = MongoClient(URI)
db = client["shop"]
events = db["events"]
events.drop()
db.drop_collection("_schema")

docs = []
with open(CSV_PATH, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            payload = json.loads(row["payload"]) if row.get("payload") else {}
        except json.JSONDecodeError:
            payload = {}
            
        docs.append({
            "_id":         row["_id"],
            "event_ts":    datetime.fromisoformat(row["event_ts"]),
            "customer_id": int(row["customer_id"]),
            "session_id":  row["session_id"],
            "event_type":  row["event_type"],
            "payload":     payload,
        })

if docs:
    events.insert_many(docs)

print(f"inserted {events.count_documents({})} events into shop.events", file=sys.stderr)
