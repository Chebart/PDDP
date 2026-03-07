# Лабораторная работа №3
## MPP-архитектура и моделирование данных в Greenplum

---

## 1. Введение

**Вариант**: 1 — источник данных PostgreSQL

Цель работы — получить практический опыт работы с Greenplum: интеграция с внешним хранилищем через PXF, обоснованный выбор ключей дистрибьюции, анализ перекоса данных по сегментам и оптимизация запросов через изменение стратегии распределения. Усложнённый вариант включает запуск gpfdist внутри контейнера gpmaster и загрузку данных из CSV-файлов в обход JDBC.

---

## 2. Датасет

**Источник**: [Maven Analytics Data Playground](https://mavenanalytics.io/data-playground) · тег: **Multiple Table**

Датасет Maven Fuzzy Factory представляет транзакционные данные интернет-магазина игрушек: сессии пользователей, просмотры страниц, заказы, позиции и возвраты.

| Таблица | Строк (примерно) | Описание |
|---------|-----------------|----------|
| `products` | 4 | Каталог товаров |
| `website_sessions` | ~472 000 | Сессии с UTM-параметрами и типом устройства |
| `website_pageviews` | ~1 188 000 | Просмотры страниц в рамках сессий |
| `orders` | ~32 000 | Заказы, привязанные к сессиям |
| `order_items` | ~36 000 | Позиции заказов (товар, цена, себестоимость) |
| `order_item_refunds` | ~1 700 | Возвраты по позициям заказов |

![ER-диаграмма датасета](<plots/PDDP(lab3).png>)

---

## 3. Структура папок

```
lab3/
├── .env                               # параметры подключения и пароли
├── docker-compose.yml
├── README.md
├── data/                              # CSV-файлы датасета (скачиваются скриптом)
├── gpfdist/
│   ├── Dockerfile
│   └── start.sh                       # запускает gpfdist -d /data/csv -p 8080
├── greenplum/
│   ├── config/
│   │   ├── gpinitsystem_config
│   │   └── hostfile_gpinitsystem
│   └── ssh/                           # SSH-ключи (генерируются скриптом)
├── plots/
│   ├── distribution_analysis.py       # строит гистограммы распределения
│   └── PDDP(lab3).png                 # ER-диаграмма
├── postgres/
│   └── init/
│       ├── 01_schema.sql              # создание таблиц в PostgreSQL
│       └── 02_load_csv.sql            # загрузка CSV в PostgreSQL
├── pxf/
│   └── jdbc_postgres_config.xml       # шаблон jdbc-site.xml (с переменными окружения)
├── scripts/
│   ├── download_data.sh               # скачивает датасет в data/
│   ├── generate_ssh_keys.sh           # генерирует SSH-ключи для GP-кластера
│   ├── setup.sh                       # точка входа: полный пайплайн запуска
│   └── setup_pxf.sh                   # настройка PXF внутри gpmaster
└── sql/
    ├── pxf_external_tables.sql        # CREATE EXTERNAL TABLE через PXF
    ├── gp_tables.sql                  # нативные GP-таблицы v1 + INSERT из ext_*
    ├── distribution_analysis.sql      # строки и skew по сегментам
    ├── queries_v1.sql                 # EXPLAIN ANALYZE до перераспределения
    ├── redistribution.sql             # перераспределение orders и order_item_refunds
    ├── queries_v2.sql                 # EXPLAIN ANALYZE после перераспределения
    └── gpfdist_external_table.sql     # CREATE EXTERNAL TABLE через gpfdist
```

---

## 4. Запуск

**Требования:** Docker Engine, docker-compose, `python3`.

```bash
# Создать и активировать виртуальное окружение с зависимостями
python3 -m venv env
source env/bin/activate
pip install psycopg2-binary matplotlib

# Выдать права на выполнение скриптам (один раз после клонирования)
chmod +x scripts/*.sh

# Запустить полный пайплайн
./scripts/setup.sh
```

`setup.sh` последовательно:
1. Скачивает датасет Maven Fuzzy Factory в `data/`
2. Генерирует SSH-ключи для GP-кластера
3. Поднимает `postgres`, `gpsegment1`, `gpsegment2`, ждёт готовности Postgres, затем поднимает `gpmaster`
4. Запускает `setup_pxf.sh` внутри `gpmaster`: генерирует `jdbc-site.xml` из шаблона, скачивает JDBC-драйвер PostgreSQL 42.7.1, выполняет `pxf cluster sync`
5. Создаёт external tables (PXF) и нативные GP-таблицы с начальными ключами дистрибьюции

Данные в Postgres загружаются автоматически при старте контейнера через скрипты из `postgres/init/`. Все параметры и пароли вынесены в `.env`; ни один файл в репозитории не содержит жёстко прописанных паролей.

### Переменные окружения (.env)

Перед первым запуском убедитесь, что `.env` заполнен:

| Переменная | Описание |
|------------|----------|
| `GREENPLUM_PASSWORD` | Пароль пользователя `gpadmin` в Greenplum |
| `GP_DATABASE` | Имя базы данных в Greenplum |
| `POSTGRES_USER` | Пользователь PostgreSQL |
| `POSTGRES_PASSWORD` | Пароль пользователя PostgreSQL |
| `POSTGRES_DB` | Имя базы данных в PostgreSQL |
| `POSTGRES_HOST` | Hostname контейнера PostgreSQL (должен совпадать с `hostname` в docker-compose) |
| `PXF_JDBC_FETCH_SIZE` | Размер батча при чтении через JDBC |
| `GPFDIST_PORT` | Порт gpfdist, проброшенный на хост (используется только при включённом gpfdist-сервисе) |

---

## 5. Загрузка данных через PXF

### Проверка данных в PostgreSQL

```bash
docker exec -i postgres_source psql -U postgres -d toystore \
  -c "SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC;"
```

### Проверка статуса PXF

```bash
docker exec gpmaster bash -c \
  "source /usr/local/greenplum-db/greenplum_path.sh && \
   export PXF_BASE=/data/pxf && pxf cluster status"
```

### Создание внешних таблиц

Каждая таблица Postgres доступна через `EXTERNAL TABLE` с профилем `Jdbc` и сервером `postgres`. `setup_pxf.sh` записывает конфигурацию в `$PXF_BASE/servers/postgres/jdbc-site.xml` и синхронизирует её на все сегменты — именно оттуда PXF-агент на каждом сегменте берёт параметры подключения к PostgreSQL.

```sql
CREATE EXTERNAL TABLE ext_orders (
    order_id           BIGINT,
    created_at         TIMESTAMP,
    website_session_id BIGINT,
    user_id            BIGINT,
    primary_product_id INT,
    items_purchased    SMALLINT,
    price_usd          NUMERIC(10,2),
    cogs_usd           NUMERIC(10,2)
)
LOCATION ('pxf://public.orders?PROFILE=Jdbc&SERVER=postgres')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');
```

Полный набор — `sql/pxf_external_tables.sql`.

### Создание нативных таблиц и загрузка данных

`sql/gp_tables.sql` создаёт нативные GP-таблицы с ключами дистрибьюции v1 и сразу загружает данные через `INSERT INTO ... SELECT * FROM ext_*`.

```bash
docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore < sql/pxf_external_tables.sql
docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore < sql/gp_tables.sql
```

---

## 6. Анализ распределения данных

### Выбор ключей дистрибьюции (v1)

| Таблица | Ключ | Обоснование |
|---------|------|-------------|
| `products` | `product_id` | Суррогатный PK. Всего 4 строки — skew неизбежен, но для микро-таблицы оптимизатор выбирает Broadcast при JOIN |
| `website_sessions` | `website_session_id` | Высокая кардинальность (~472K) — минимальный skew |
| `website_pageviews` | `website_session_id` | Ко-локация с `website_sessions` → JOIN по `session_id` локальный |
| `orders` | `order_id` | Высокая кардинальность, равномерный хеш |
| `order_items` | `order_id` | Ко-локация с `orders` → JOIN и агрегации по заказу локальны (Q1) |
| `order_item_refunds` | `order_item_id` | Намеренное несовпадение с `order_items` — демонстрирует Redistribute Motion в Q3 |

### Запуск анализа

```bash
# Распределение строк и коэффициент skew по всем таблицам:
docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore < sql/distribution_analysis.sql

# Построить гистограммы до перераспределения (запускается на хосте из venv):
python3 plots/distribution_analysis.py v1
```

`distribution_analysis.sql` выводит количество строк и процент на каждом сегменте, а также коэффициент skew:

```
skew_pct = (max_rows − min_rows) / avg_rows × 100
```

Значение `skew_pct < 10 %` считается приемлемым. `distribution_analysis.py` подключается к Greenplum через порт 5432 и сохраняет `plots/distribution_v1.png`. Каждая панель — одна таблица, пунктирная линия — идеальное распределение 50/50.

### Фактические результаты (v1)

| Таблица | seg 0 | seg 1 | skew_pct | Комментарий |
|---------|-------|-------|----------|-------------|
| `website_sessions` | 236 511 (50.02 %) | 236 360 (49.98 %) | **0.06 %** | Практически идеальное распределение |
| `website_pageviews` | 593 999 (49.99 %) | 594 125 (50.01 %) | **~0 %** | Аналогично |
| `orders` | 16 127 (49.91 %) | 16 186 (50.09 %) | **0.37 %** | Хорошее равномерное распределение |
| `order_items` | 19 955 (49.86 %) | 20 070 (50.14 %) | **0.57 %** | Хорошее равномерное распределение |
| `order_item_refunds` | 895 (51.70 %) | 836 (48.30 %) | **6.82 %** | Небольшой skew из-за малого объёма |
| `products` | 3 (75.00 %) | 1 (25.00 %) | **100 %** | Ожидаемо для 4 строк (хеш 3/1) — оптимизатор выбирает Broadcast |

---

## 7. Оптимизация запросов и анализ Motion

В плане Greenplum (`EXPLAIN ANALYZE`) важны следующие узлы:

| Тип Motion | Описание |
|------------|----------|
| **Redistribute Motion N:N** | Строки перераспределяются между сегментами по новому ключу хеша; стоимость пропорциональна объёму |
| **Broadcast Motion N:N** | Вся таблица копируется на каждый сегмент; дёшево для малых таблиц |
| *(нет Motion)* | Данные уже на нужных сегментах, JOIN локальный — оптимально |

### Q1 — Выручка и маржа по продуктам (v1)

```sql
SELECT p.product_name,
       COUNT(DISTINCT o.order_id)                                                          AS num_orders,
       SUM(oi.price_usd)                                                                   AS total_revenue,
       SUM(oi.cogs_usd)                                                                    AS total_cogs,
       SUM(oi.price_usd - oi.cogs_usd)                                                    AS total_profit,
       ROUND(SUM(oi.price_usd - oi.cogs_usd) * 100.0 / NULLIF(SUM(oi.price_usd), 0), 2) AS margin_pct
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_name
ORDER BY total_revenue DESC;
```

`orders` и `order_items` оба распределены по `order_id` → JOIN **локальный**. `products` (4 строки) → **Broadcast Motion**.

```
-- EXPLAIN ANALYZE Q1 (v1), execution time: 63.254 ms
Gather Motion 2:1  (slice3; segments: 2)  (actual time=60.5..60.5 rows=4)
  -> HashAggregate  Group Key: product_name
       -> Redistribute Motion 2:2  Hash Key: product_name        ← финальная агрегация
            -> HashAggregate  Group Key: product_name, order_id
                 -> Hash Join  Hash Cond: order_items.order_id = orders.order_id  ← LOCAL
                      -> Seq Scan on order_items
                      -> Hash
                           -> Seq Scan on orders
                 -> Hash
                      -> Broadcast Motion 2:2  (slice1)          ← products (4 строки)
                           -> Seq Scan on products
```

### Q2 — Конверсия сессий в заказы по UTM-источнику и устройству (v1)

```sql
SELECT ws.utm_source,
       ws.device_type,
       COUNT(DISTINCT ws.website_session_id)                                             AS total_sessions,
       COUNT(DISTINCT o.order_id)                                                        AS total_orders,
       ROUND(COUNT(DISTINCT o.order_id) * 100.0
             / NULLIF(COUNT(DISTINCT ws.website_session_id), 0), 2)                     AS conversion_pct
FROM website_sessions ws
LEFT JOIN orders o ON o.website_session_id = ws.website_session_id
GROUP BY ws.utm_source, ws.device_type
ORDER BY total_sessions DESC;
```

`website_sessions` распределена по `website_session_id`, `orders` — по `order_id`. JOIN по `website_session_id`, которого нет в ключе `orders` → **Redistribute Motion на `orders`**.

```
-- EXPLAIN ANALYZE Q2 (v1), execution time: 1059.413 ms
Gather Motion 2:1  (slice4; segments: 2)  (actual time=774.6..774.6 rows=8)
  -> Sort  (Merge Key: count(website_session_id))
       -> Hash Join  (utm_source, device_type)
            -> HashAggregate  Group Key: utm_source, device_type
                 -> Redistribute Motion 2:2  Hash Key: utm_source, device_type
                      -> ...
                           -> Hash Left Join  Hash Cond: ws.website_session_id = o.website_session_id
                                -> Seq Scan on website_sessions ws
                                -> Hash
                                     -> Redistribute Motion 2:2  Hash Key: o.website_session_id  ← REDISTRIBUTE на orders
                                          -> Seq Scan on orders o
            -> Hash  (count(website_session_id))
                 -> ...
```

### Q3 — Процент возвратов по продуктам (v1)

```sql
SELECT p.product_name,
       COUNT(oi.order_item_id)                                                            AS items_sold,
       COUNT(r.order_item_refund_id)                                                     AS items_refunded,
       ROUND(COUNT(r.order_item_refund_id) * 100.0
             / NULLIF(COUNT(oi.order_item_id), 0), 2)                                   AS refund_rate_pct,
       COALESCE(SUM(r.refund_amount_usd), 0)                                             AS total_refunded_usd
FROM products p
JOIN order_items oi            ON oi.product_id   = p.product_id
LEFT JOIN order_item_refunds r ON r.order_item_id = oi.order_item_id
GROUP BY p.product_name
ORDER BY refund_rate_pct DESC NULLS LAST;
```

`order_items` распределена по `order_id`, `order_item_refunds` — по `order_item_id` (намеренное несовпадение). JOIN по `order_item_id`: `order_item_refunds` уже распределена по ключу JOIN → лежит на месте; `order_items` нужно перераспределить → **Redistribute Motion на `order_items`**. `products` → **Broadcast Motion**.

```
-- EXPLAIN ANALYZE Q3 (v1), execution time: 14.649 ms
Gather Motion 2:1  (slice4; segments: 2)  (actual time=7.1..7.1 rows=4)
  -> Sort  (Merge Key: refund_rate_pct)
       -> HashAggregate  Group Key: product_name
            -> Redistribute Motion 2:2  Hash Key: product_name   ← финальная агрегация
                 -> HashAggregate  Group Key: product_name
                      -> Hash Join  Hash Cond: order_items.product_id = products.product_id
                           -> Hash Left Join  Hash Cond: order_items.order_item_id = order_item_refunds.order_item_id
                                -> Redistribute Motion 2:2  Hash Key: order_items.order_item_id  ← REDISTRIBUTE на order_items
                                     -> Seq Scan on order_items
                                -> Hash
                                     -> Seq Scan on order_item_refunds        ← LOCAL (dist by order_item_id)
                           -> Hash
                                -> Broadcast Motion 2:2  (slice2)             ← products (4 строки)
                                     -> Seq Scan on products
```

### Перераспределение (v1 → v2)

`sql/redistribution.sql` перераспределяет данные на месте через `ALTER TABLE ... SET DISTRIBUTED BY ... REORGANIZE=TRUE` — без создания промежуточных таблиц:

- `orders`: `order_id` → `website_session_id`
- `order_item_refunds`: `order_item_id` → `order_id`

```bash
docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore < sql/redistribution.sql
```

### Изменения в планах запросов (v2)

**Q1** — добавляется **Redistribute Motion на `orders`** (регрессия): `order_items` остаётся по `order_id`, а `orders` теперь по `website_session_id` → ключи расходятся.

```
-- EXPLAIN ANALYZE Q1 (v2), execution time: 54.401 ms
Gather Motion 2:1  (slice4; segments: 2)  (actual time=42.2..42.2 rows=4)
  -> HashAggregate  Group Key: product_name
       -> Redistribute Motion 2:2  Hash Key: product_name        ← финальная агрегация
            -> HashAggregate  Group Key: product_name, order_id
                 -> Hash Join  Hash Cond: order_items.order_id = orders.order_id
                      -> Seq Scan on order_items
                      -> Hash
                           -> Redistribute Motion 2:2  Hash Key: orders.order_id  ← REDISTRIBUTE на orders (регрессия)
                                -> Seq Scan on orders
                 -> Hash
                      -> Broadcast Motion 2:2  (slice2)          ← products (4 строки)
                           -> Seq Scan on products
```

**Q2** — Redistribute Motion на `orders` **устраняется** (улучшение): `orders` и `website_sessions` теперь оба по `website_session_id` → JOIN локальный.

```
-- EXPLAIN ANALYZE Q2 (v2), execution time: 919.914 ms
Gather Motion 2:1  (slice3; segments: 2)  (actual time=1128.2..1128.2 rows=8)
  -> Sort  (Merge Key: count(website_session_id))
       -> Hash Join  (utm_source, device_type)
            -> HashAggregate  Group Key: utm_source, device_type
                 -> Redistribute Motion 2:2  Hash Key: utm_source, device_type
                      -> ...
            -> Hash
                 -> HashAggregate  Group Key: utm_source, device_type
                      -> ...
                           -> Materialize
                                -> Hash Left Join  Hash Cond: ws.website_session_id = o.website_session_id  ← LOCAL
                                     -> Seq Scan on website_sessions ws
                                     -> Hash
                                          -> Seq Scan on orders o              ← без Redistribute Motion
```

**Q3** — ожидалось улучшение, но фактически **регрессия**: `order_item_refunds` перешла с `order_item_id` на `order_id`, что совпадает с ключом `order_items`. Однако JOIN выполняется по `order_item_id`, а не по `order_id` — оптимизатор не может использовать ко-локацию по `order_id` для этого условия. Итог: теперь **оба** источника перераспределяются (v1 — только `order_items`).

```
-- EXPLAIN ANALYZE Q3 (v2), execution time: 11.659 ms
Gather Motion 2:1  (slice5; segments: 2)  (actual time=7.8..7.8 rows=4)
  -> Sort  (Merge Key: refund_rate_pct)
       -> HashAggregate  Group Key: product_name
            -> Redistribute Motion 2:2  Hash Key: product_name   ← финальная агрегация
                 -> HashAggregate  Group Key: product_name
                      -> Hash Join  Hash Cond: order_items.product_id = products.product_id
                           -> Hash Left Join  Hash Cond: order_items.order_item_id = order_item_refunds.order_item_id
                                -> Redistribute Motion 2:2  Hash Key: order_items.order_item_id     ← REDISTRIBUTE на order_items
                                     -> Seq Scan on order_items
                                -> Hash
                                     -> Redistribute Motion 2:2  Hash Key: order_item_refunds.order_item_id  ← REDISTRIBUTE на order_item_refunds (регрессия)
                                          -> Seq Scan on order_item_refunds
                           -> Hash
                                -> Broadcast Motion 2:2  (slice3)             ← products (4 строки)
                                     -> Seq Scan on products
```

### Запуск

```bash
# Планы v1 (до перераспределения):
docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore < sql/queries_v1.sql

# Планы v2 (после перераспределения):
docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore < sql/queries_v2.sql

# Графики после перераспределения:
python3 plots/distribution_analysis.py v2
```

### Сводная таблица Motion (фактические результаты)

| Запрос | Motion V1 | Motion V2 | Результат |
|--------|-----------|-----------|-----------|
| Q1: `orders ↔ order_items` | LOCAL (63 ms) | **Redistribute** (54 ms) | Регрессия плана; быстрее за счёт меньшего числа колонок |
| Q1: `products` | Broadcast | Broadcast | Без изменений |
| Q2: `orders` | **Redistribute** (1059 ms) | LOCAL (920 ms) | Motion устранён; ускорение несмотря на spill DISTINCT-агрегата |
| Q3: `order_items` | **Redistribute** (15 ms) | **Redistribute** (12 ms) | Motion сохранился |
| Q3: `order_item_refunds` | LOCAL (dist by `order_item_id`) | **Redistribute** (регрессия) | Добавился второй Motion |
| Q3: `products` | Broadcast | Broadcast | Без изменений |

### Выводы

- **Ко-локация** работает только тогда, когда ключ дистрибьюции совпадает именно с колонкой JOIN-условия, а не просто с «соседней» колонкой одной таблицы.
- **Перераспределение `orders`** (order_id → website_session_id) устранило Motion в Q2, но внесло регрессию в Q1 — классический компромисс при смене ключа.
- **Перераспределение `order_item_refunds`** (order_item_id → order_id) оказалось контрпродуктивным для Q3: в v1 таблица лежала точно по ключу JOIN (`order_item_id`), в v2 — нет, что добавило второй Redistribute Motion.
- **Broadcast** для `products` оптимизатор выбирает автоматически — передача 4 строк дешевле перераспределения крупных таблиц.
- При выборе ключа в продакшене нужно ориентироваться на самый частый и тяжёлый запрос и моделировать все смежные запросы: улучшение одного сценария может деградировать несколько других.

---

## 8. GPFDIST (усложнённый вариант)

### Описание

gpfdist — встроенный HTTP-сервер Greenplum для параллельной раздачи файлов. Каждый сегмент подключается к gpfdist напрямую и вытягивает свою часть CSV одновременно — значительно быстрее JDBC при bulk load: нет накладных расходов JDBC, нет узкого места в виде одного потока.

gpfdist работает как отдельный контейнер в той же Docker-сети `gpnet`. CSV-файлы монтируются из `./data/` хоста в `/data/csv` контейнера в режиме read-only. Образ собирается из `gpfdist/Dockerfile` на базе `woblerr/greenplum:6.27.1`, который уже содержит бинарник `gpfdist`. `setup.sh` запускает контейнер автоматически на шаге 4/4 и ждёт готовности через healthcheck.

### Проверка

```bash
# Проверить, что процесс gpfdist запущен:
docker exec gpfdist pgrep -a gpfdist
```

### Внешние таблицы

Сегменты подключаются к gpfdist по hostname контейнера `gpfdist`:

```sql
CREATE EXTERNAL TABLE ext_gpfdist_orders (
    order_id           BIGINT,
    created_at         TIMESTAMP,
    website_session_id BIGINT,
    user_id            BIGINT,
    primary_product_id INT,
    items_purchased    SMALLINT,
    price_usd          NUMERIC(10,2),
    cogs_usd           NUMERIC(10,2)
)
LOCATION ('gpfdist://gpfdist:8080/orders.csv')
FORMAT 'CSV' (HEADER TRUE);
```

Полный набор — `sql/gpfdist_external_table.sql`. Таблицы создаются автоматически через `setup.sh`. Для ручной проверки:

```bash
docker exec -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d toystore \
  -c "SELECT COUNT(*) FROM ext_gpfdist_orders;"
```

### PXF vs gpfdist

| Критерий | PXF (JDBC) | gpfdist |
|----------|------------|---------|
| Источник | Живая БД | CSV-файлы |
| Параллелизм | Один JDBC-поток на запрос | Каждый сегмент тянет свою часть независимо |
| Накладные расходы | JDBC round-trip | Прямой HTTP |
| Применение | Интеграция с источником в реальном времени | Bulk load из файлов |

---

## 9. Заключение

В ходе работы:

- Развёрнут Greenplum-кластер (1 мастер + 2 сегмента) совместно с PostgreSQL через Docker Compose; все параметры вынесены в `.env`.
- Выбран датасет Maven Fuzzy Factory (6 таблиц); данные загружены в PostgreSQL через init-скрипты и перенесены в GP через PXF external tables с профилем `Jdbc`.
- Обоснованы начальные ключи дистрибьюции (v1): высококардинальные колонки обеспечивают `skew_pct < 1 %` для крупных таблиц; результаты визуализированы Python-скриптом.
- Выполнены три аналитических запроса до и после перераспределения; для каждого получен и разобран реальный план `EXPLAIN ANALYZE`: перераспределение `orders` устранило Redistribute Motion в Q2, но внесло регрессию в Q1; перераспределение `order_item_refunds` (order_item_id → order_id) оказалось контрпродуктивным — добавило второй Motion в Q3 вместо устранения первого, поскольку JOIN выполняется по `order_item_id`, а не по `order_id`.
- Запущен gpfdist внутри контейнера `gpmaster` для параллельной загрузки CSV без JDBC-overhead.
