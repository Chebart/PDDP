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
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/pxf_external_tables.sql
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/gp_tables.sql
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
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/distribution_analysis.sql

# Построить гистограммы до перераспределения (запускается на хосте из venv):
python3 plots/distribution_analysis.py v1
```

`distribution_analysis.sql` выводит количество строк и процент на каждом сегменте, а также коэффициент skew:

```
skew_pct = (max_rows − min_rows) / avg_rows × 100
```

Значение `skew_pct < 10 %` считается приемлемым. `distribution_analysis.py` подключается к Greenplum через порт 5432 и сохраняет `plots/distribution_v1.png`. Каждая панель — одна таблица, пунктирная линия — идеальное распределение 50/50.

### Ожидаемые результаты (v1)

| Таблица | skew_pct | Причина |
|---------|----------|---------|
| `website_sessions` | < 1 % | Большая кардинальность, хеш практически равномерен |
| `website_pageviews` | < 1 % | Наследует распределение `session_id` |
| `orders` | < 1 % | Большая кардинальность `order_id` |
| `order_items` | < 1 % | Большая кардинальность `order_id` |
| `order_item_refunds` | 1–5 % | Меньший объём — чуть больший разброс |
| `products` | ~50 % | Всего 4 строки: хеш 2/2 или 3/1 — нормально для микро-таблицы |

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
-- вывод EXPLAIN ANALYZE (v1):
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
-- вывод EXPLAIN ANALYZE (v1):
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

`order_items` распределена по `order_id`, `order_item_refunds` — по `order_item_id` (намеренное несовпадение). JOIN по `order_item_id` → **Redistribute Motion на `order_items`**. `products` → **Broadcast Motion**.

```
-- вывод EXPLAIN ANALYZE (v1):
```

### Перераспределение (v1 → v2)

`sql/redistribution.sql` создаёт таблицу с новым ключом, переносит данные через `INSERT INTO ... SELECT`, затем `DROP TABLE` + `ALTER TABLE RENAME`:

- `orders`: `order_id` → `website_session_id`
- `order_item_refunds`: `order_item_id` → `order_id`

```bash
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/redistribution.sql
```

### Изменения в планах запросов (v2)

**Q1** — добавляется **Redistribute Motion на `orders`** (регрессия): `order_items` остаётся по `order_id`, а `orders` теперь по `website_session_id` → ключи расходятся.

```
-- вывод EXPLAIN ANALYZE (v2):
```

**Q2** — Redistribute Motion на `orders` **устраняется** (улучшение): `orders` и `website_sessions` теперь оба по `website_session_id` → JOIN локальный.

```
-- вывод EXPLAIN ANALYZE (v2):
```

**Q3** — Redistribute Motion на `order_items` **устраняется** (улучшение): `order_item_refunds` перешла на `order_id`, как и `order_items` → данные ко-локированы.

```
-- вывод EXPLAIN ANALYZE (v2):
```

### Запуск

```bash
# Планы v1 (до перераспределения):
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/queries_v1.sql

# Планы v2 (после перераспределения):
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/queries_v2.sql

# Графики после перераспределения:
python3 plots/distribution_analysis.py v2
```

### Сводная таблица Motion

| Запрос | Motion V1 | Motion V2 |
|--------|-----------|-----------|
| Q1: `orders ↔ order_items` | LOCAL | **Redistribute** |
| Q1: `products` | Broadcast | Broadcast |
| Q2: `orders` | **Redistribute** | LOCAL |
| Q3: `order_items` | **Redistribute** | LOCAL |
| Q3: `products` | Broadcast | Broadcast |

### Выводы

- **Ко-локация** по join-ключу — единственный способ устранить Motion: ключи дистрибьюции обеих сторон JOIN должны совпадать с колонкой условия.
- **Изменение ключа** — всегда компромисс: улучшение Q2 и Q3 деградировало Q1.
- **Broadcast** для `products` оптимизатор выбирает автоматически — передача 4 строк дешевле перераспределения крупных таблиц.
- При выборе ключа в продакшене нужно ориентироваться на самый частый и тяжёлый запрос.

---

## 8. GPFDIST (усложнённый вариант)

### Описание

gpfdist — встроенный HTTP-сервер Greenplum для параллельной раздачи файлов. Каждый сегмент подключается к gpfdist напрямую и вытягивает свою часть CSV одновременно — значительно быстрее JDBC при bulk load: нет накладных расходов JDBC, нет узкого места в виде одного потока.

gpfdist запускается внутри контейнера `gpmaster`, поскольку бинарник входит в состав дистрибутива Greenplum. CSV-файлы копируются из `data/` в контейнер перед запуском.

### Запуск

```bash
# Скопировать CSV-файлы в контейнер:
docker cp data/. gpmaster:/tmp/csv/

# Запустить gpfdist внутри gpmaster в фоне:
docker exec -d gpmaster bash -c \
  "source /usr/local/greenplum-db/greenplum_path.sh && \
   gpfdist -d /tmp/csv -p 8080 -l /tmp/gpfdist.log -v"

# Проверить доступность:
docker exec gpmaster bash -c "curl -s http://localhost:8080/ | head -5"
```

### Внешние таблицы

Сегменты подключаются к gpfdist по имени хоста `gpmaster` (hostname контейнера):

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
LOCATION ('gpfdist://gpmaster:8080/orders.csv')
FORMAT 'CSV' (HEADER TRUE);
```

Полный набор — `sql/gpfdist_external_table.sql`.

```bash
docker exec -i gpmaster psql -U gpadmin -d toystore < sql/gpfdist_external_table.sql

# Проверить:
docker exec gpmaster psql -U gpadmin -d toystore \
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
- Выполнены три аналитических запроса до и после перераспределения; для каждого разобрано поведение Redistribute и Broadcast Motion: перераспределение `orders` и `order_item_refunds` устранило Motion в Q2 и Q3 ценой регрессии в Q1.
- Запущен gpfdist внутри контейнера `gpmaster` для параллельной загрузки CSV без JDBC-overhead.
