FROM python:3.11-slim

WORKDIR /app

COPY build/producer/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY producer/main.py .

CMD ["python", "main.py"]
