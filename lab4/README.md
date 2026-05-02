# Лабораторная работа №4
## Принципы работы с Trino

---

## 1. Введение

Trino — распределённый query engine, который выполняет SQL-запросы поверх нескольких разнотипных источников через подключаемые коннекторы. Вместо ETL и копирования данных в единое хранилище Trino читает каждый источник «на месте» и объединяет результаты в памяти.

Цель работы — развернуть три хранилища (Postgres, MongoDB, MinIO), подключить их к Trino и решить аналитические задачи запросами, которые напрямую джойнят таблицы из разных каталогов.

---

## 2. Датасет

Данные описывают один интернет-магазин, разбитый по трём хранилищам:

| Хранилище | Данные |
|-----------|--------|
| **Postgres** | Справочники (`categories`, `customers`, `products`) + транзакции (`orders`, `order_items`) |
| **MongoDB** | Коллекция `shop.events` — поведенческие события: просмотры, добавления в корзину, поиск, покупки |
| **MinIO** | `clickstream.csv` — сессионный веб-лог; `product_media_metadata.csv` — пути к медиафайлам |

MongoDB `payload` хранится как вложенный BSON-документ, а не как строка: `load.py` вызывает `json.loads()` на поле CSV и передаёт результат в pymongo как dict. Это позволяет в Trino обращаться к полям напрямую: `payload.q`, `payload.geo.city` — без `JSON_EXTRACT`.

Данные MinIO регистрируются в Trino через **Hive Metastore Service (HMS)**. HMS требует реляционного backing store; используется тот же Postgres-экземпляр с отдельной базой `metastore`.

---

## 3. Структура проекта

```
lab4/
├── .env
├── docker-compose.yml
├── data/
│   ├── postgres/
│   ├── mongodb/
│   └── minio/
├── init/
│   ├── postgres/
│   │   ├── 00_metastore_db.sql
│   │   └── 01_schema.sql
│   └── mongodb/load.py
├── trino/
│   ├── etc/catalog/
│   └── hms/
└── sql/
    ├── 00_create_external_tables.sql
    ├── 01_orders_mart.sql
    ├── 02_top_categories.sql
    ├── 03_customer_funnel.sql
    ├── 04_search_top20.sql
    └── 05_clickstream_funnel.sql
```

---

## 4. Развёртывание

```bash
# Поднять стек (первый старт HMS занимает ~90 с — schematool инициализирует схему в Postgres)
docker compose up -d --build

# Зарегистрировать внешние таблицы Hive над MinIO
docker exec -i lab4-trino trino -f /dev/stdin < sql/00_create_external_tables.sql

# Запустить задания
docker exec -i lab4-trino trino -f /dev/stdin < sql/01_orders_mart.sql
docker exec -i lab4-trino trino -f /dev/stdin < sql/02_top_categories.sql
docker exec -i lab4-trino trino -f /dev/stdin < sql/03_customer_funnel.sql
docker exec -i lab4-trino trino -f /dev/stdin < sql/04_search_top20.sql
docker exec -i lab4-trino trino -f /dev/stdin < sql/05_clickstream_funnel.sql
```

Наиболее нетривиальный конфиг — `trino/etc/catalog/hive.properties`:

```properties
connector.name=hive
hive.metastore=thrift
hive.metastore.uri=thrift://hive-metastore:9083
hive.non-managed-table-writes-enabled=true
fs.native-s3.enabled=true
s3.endpoint=http://minio:9000
s3.region=us-east-1
s3.path-style-access=true
s3.aws-access-key=minio
s3.aws-secret-key=minio12345
```

`fs.native-s3.enabled=true` подключает встроенный S3-клиент Trino вместо Hadoop S3A. С версии 393 файловый метастор удалён — обязателен HMS через `hive.metastore=thrift`. Пути таблиц используют `s3a://` для совместимости с Hadoop FS на стороне HMS.

---

## 5. Задания

### Задание 1. Витрина заказов

```sql
SELECT
    o.order_id,
    o.customer_id,
    c.city,
    o.order_ts,
    o.status,
    o.total_amount,
    COALESCE(SUM(oi.qty), 0) AS items_cnt,
    COUNT(DISTINCT oi.product_id) AS distinct_products_cnt
FROM postgres.public.orders o
JOIN postgres.public.customers c ON c.customer_id = o.customer_id
LEFT JOIN postgres.public.order_items oi ON oi.order_id = o.order_id
GROUP BY
    o.order_id, o.customer_id, c.city, o.order_ts, o.status, o.total_amount
ORDER BY o.order_id;
```

Витрина собирает в одной строке всё, что нужно знать о заказе: основные поля из `orders`, город покупателя из `customers` и количество позиций из `order_items`. Город живёт в отдельной таблице `customers`, поэтому без JOIN его не получить. `order_items` подключён через LEFT JOIN — заказ попадёт в результат, даже если у него пока нет позиций; `COALESCE` заменяет NULL на 0 в таких случаях.

---

### Задание 2. Топ-10 категорий по выручке

```sql
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
```

Выручку считаем как `qty * price` из `order_items` — там зафиксирована цена на момент продажи, а не текущая цена из `products`. Чтобы от позиции заказа добраться до категории, нужно пройти через `products` (там есть `category_id`), отсюда два JOIN. `COUNT(DISTINCT order_id)` нужен потому, что один заказ может содержать несколько позиций одной категории — без DISTINCT они все посчитались бы как отдельные заказы.

---

### Задание 3. Метрики пользователей + конверсия по городам

```sql
WITH events_agg AS (
    SELECT customer_id,
        COUNT_IF(event_type = 'view') AS view_cnt,
        COUNT_IF(event_type = 'add_to_cart') AS add_to_cart_cnt
    FROM mongodb.shop.events
    GROUP BY customer_id
),
orders_agg AS (
    SELECT customer_id,
        COUNT(*) AS orders_cnt,
        SUM(total_amount) AS total_amount
    FROM postgres.public.orders
    GROUP BY customer_id
)
SELECT c.customer_id, c.city,
    COALESCE(e.view_cnt, 0) AS view_cnt,
    COALESCE(e.add_to_cart_cnt, 0) AS add_to_cart_cnt,
    COALESCE(o.orders_cnt, 0) AS orders_cnt,
    COALESCE(o.total_amount, 0) AS total_amount
FROM postgres.public.customers c
LEFT JOIN events_agg e ON e.customer_id = c.customer_id
LEFT JOIN orders_agg o ON o.customer_id = c.customer_id
ORDER BY c.customer_id;
```

`events_agg` считает просмотры и добавления в корзину из MongoDB, `orders_agg` — заказы из Postgres, а финальный SELECT соединяет всё через `customers`. Trino сам отправляет каждый CTE в нужный коннектор и объединяет результаты в памяти. LEFT JOIN нужен, потому что не у каждого покупателя есть и события в MongoDB, и заказы в Postgres — без него такие покупатели просто пропали бы из результата.

Второй запрос в файле считает конверсию «просмотр → покупка» по городам. `DISTINCT` в CTE `viewers` и `buyers` нужен, чтобы покупатель с сотней просмотров считался как один человек, а не как сто.

---

### Задание 4. Топ-20 поисковых запросов

```sql
WITH searches AS (
    SELECT customer_id,
        LOWER(CAST(payload.q AS varchar)) AS query
    FROM mongodb.shop.events
    WHERE event_type = 'search' AND payload.q IS NOT NULL
),
top20 AS (
    SELECT query, COUNT(*) AS searches_cnt
    FROM searches
    GROUP BY query
    ORDER BY searches_cnt DESC, query ASC
    LIMIT 20
),
search_users AS (
    SELECT DISTINCT s.query, s.customer_id
    FROM searches s
    JOIN top20 t ON t.query = s.query
)
SELECT t.query, t.searches_cnt,
    COUNT(DISTINCT su.customer_id) AS searchers,
    COUNT(DISTINCT o.order_id) AS orders_by_searchers,
    COALESCE(SUM(o.total_amount), 0) AS revenue_by_searchers
FROM top20 t
LEFT JOIN search_users su ON su.query = t.query
LEFT JOIN postgres.public.orders o
       ON o.customer_id = su.customer_id
      AND o.status IN ('paid', 'shipped', 'delivered')
GROUP BY t.query, t.searches_cnt
ORDER BY t.searches_cnt DESC;
```

MongoDB хранит поисковый запрос в поле `q` внутри вложенного документа `payload`. Trino разворачивает его автоматически — обращаемся просто как `payload.q`, без `JSON_EXTRACT`.

В сортировке `top20` добавлен `query ASC` как второй критерий: если у нескольких запросов одинаковое количество поисков, порядок между ними фиксируется по алфавиту. Это важно, потому что Trino вычисляет CTE заново при каждом обращении — без фиксированного порядка `LIMIT 20` каждый раз отдаёт разный набор строк и JOIN ничего не находит.

---

### Задание 5. Воронка по clickstream

В датасете каждый `session_id` встречается только на одной странице, поэтому классическую воронку «пользователь перешёл с home на category» по сессиям не построить. Реализованы два варианта.

**Первый — по сессиям.** `stage_sessions` считает, сколько уникальных сессий было на каждой странице. `stages` задаёт фиксированный порядок шагов через `VALUES` — это нужно, чтобы оконные функции правильно определяли «предыдущий» и «первый» шаг. В `joined` к каждому шагу через LEFT JOIN подтягивается количество сессий: `LAG` берёт значение предыдущего шага для `step_share`, `FIRST_VALUE` — значение home для `share_of_home`. JOIN сделан от `stages` к `stage_sessions`, а не наоборот — чтобы шаги не пропадали, если по какой-то странице данных нет.

```sql
WITH stage_sessions AS (
    SELECT page, COUNT(DISTINCT session_id) AS sessions
    FROM hive.lake.clickstream
    WHERE page IN ('home', 'category', 'product', 'cart', 'checkout')
    GROUP BY page
),
stages(step, stage) AS (
    VALUES (1, 'home'), (2, 'category'), (3, 'product'), (4, 'cart'), (5, 'checkout')
),
joined AS (
    SELECT s.step, s.stage,
        COALESCE(ss.sessions, 0) AS sessions,
        LAG(COALESCE(ss.sessions, 0)) OVER (ORDER BY s.step) AS prev_sessions,
        FIRST_VALUE(COALESCE(ss.sessions, 0)) OVER (ORDER BY s.step) AS top_sessions
    FROM stages s
    LEFT JOIN stage_sessions ss ON ss.page = s.stage
)
SELECT step, stage, sessions,
    ROUND(sessions * 1.0 / NULLIF(prev_sessions, 0), 4) AS step_share,
    ROUND(sessions * 1.0 / NULLIF(top_sessions, 0), 4) AS share_of_home
FROM joined ORDER BY step;
```

**Второй — по покупателям.** Связующий ключ — `customer_id`: у одного покупателя могут быть сессии на разных страницах. В `cust` все сессии покупателя сворачиваются в одну строку флагами через `BOOL_OR` — был ли он хоть раз на каждой странице. В `funnel` `COUNT_IF` считает, сколько покупателей прошли каждый шаг последовательно: на category попадают только те, у кого флаг home тоже true. `CROSS JOIN UNNEST` разворачивает широкую строку `funnel` в пять строк — по одной на шаг, без UNION ALL. Финальный SELECT считает `step_retention` через `LAG` и `overall_retention` через `FIRST_VALUE`.

```sql
WITH cust AS (
    SELECT customer_id,
        BOOL_OR(page = 'home') AS h,
        BOOL_OR(page = 'category') AS c,
        BOOL_OR(page = 'product') AS p,
        BOOL_OR(page = 'cart') AS ca,
        BOOL_OR(page = 'checkout') AS ch
    FROM hive.lake.clickstream
    GROUP BY customer_id
),
funnel AS (
    SELECT
        COUNT_IF(h) AS home,
        COUNT_IF(h AND c) AS category,
        COUNT_IF(h AND c AND p) AS product,
        COUNT_IF(h AND c AND p AND ca) AS cart,
        COUNT_IF(h AND c AND p AND ca AND ch) AS checkout
    FROM cust
),
steps AS (
    SELECT step, stage, customers
    FROM funnel
    CROSS JOIN UNNEST(
        ARRAY[1, 2, 3, 4, 5],
        ARRAY['home', 'category', 'product', 'cart', 'checkout'],
        ARRAY[home, category, product, cart, checkout]
    ) AS t(step, stage, customers)
)
SELECT step, stage, customers,
    ROUND(customers * 1.0 / NULLIF(LAG(customers) OVER (ORDER BY step), 0), 4) AS step_retention,
    ROUND(customers * 1.0 / NULLIF(FIRST_VALUE(customers) OVER (ORDER BY step), 0), 4) AS overall_retention
FROM steps ORDER BY step;
```
