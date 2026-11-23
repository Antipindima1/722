# Матрица проверок артефактов

Соответствие требованию «Слабая зона → Артефакт → Чем проверить» из постановки задачи.

| Слабая зона | Артефакт | Чем проверить | Инструмент | Результат | Доказательство |
|---|---|---|---|---|---|
| System design | C4, уровень 2 (контейнеры) | рендер в PlantUML C4, аргументация решений | Kroki `POST /plantuml/svg` | HTTP 200, диаграмма отрисована, 9 контейнеров, 3 внешние системы, 15 из 15 связей с протоколами | `artifacts/c4-container.svg`, `artifacts/c4-container-check.md` |
| Интеграции, синхронные | OpenAPI + Sequence с ошибками и ретраями | Spectral | Spectral 6.17.1, ruleset `spectral:oas` | код возврата 0, ошибок 0, предупреждений 0 | `artifacts/feature-registry-check/spectral-registry.json`, `artifacts/feature-registry-check/openapi-registry-check.md` |
| Интеграции, асинхронные | AsyncAPI | AsyncAPI CLI validate | `@asyncapi/cli` validate | ошибок 0; 7 предупреждений (лицензия, email, `messageId`), разобраны в отчёте | `artifacts/feature-registry-check/asyncapi-validate.txt`, `artifacts/feature-registry-check/asyncapi-registry-check.md` |
| Данные | ER + DDL PostgreSQL | **DDL выполняется в DBeaver без ошибок** | DBeaver + PostgreSQL (Neon) | ✅ скрипт выполнен без ошибок; схема проверена самопроверкой schema-verify.sql | `artifacts/dbeaver-check.md, `artifacts/schema-verify.sql |

## Что уже проверено по данным

| Проверка | Инструмент | Результат |
|---|---|---|
| Исполнение DDL | PGlite (PostgreSQL 18.6, WASM) | OK: 8 таблиц, 8 внешних ключей, 20 индексов |
| Ограничения | PGlite, 11 негативных вставок | 11 из 11 отбиты |
| Модель | `@dbml/core` parse | OK: 8 таблиц, 7 связей |
| Рендер ER | Kroki `POST /plantuml/svg` | HTTP 200, 27 КБ |

## Как закрыть пункт «DBeaver»

1. В DBeaver открыть соединение с PostgreSQL (Neon из задания).
2. Выполнить `artifacts/schema-reset.sql` — снять прошлую схему, иначе будет ошибка `type already exists`.
3. Выполнить `artifacts/schema-registry.sql` целиком **через `Alt+X` (Execute SQL Script)**.

Важно: `Ctrl+Enter` в DBeaver выполняет только инструкцию под курсором. Если запускать так,
`COMMENT ON TABLE receipts` упадёт с `relation receipts does not exist` — таблицы ещё
не созданы.
4. Проверить результат:

```sql
select table_name from information_schema.tables
where table_schema = 'public' order by 1;
```

Ожидаемо 8 таблиц: `companies`, `contractors`, `payout_rows`, `payouts`, `processed_events`, `receipts`, `registries`, `validation_reports`.

5. Зафиксировать результат: «Script executed» без ошибок + скриншот или список таблиц.

После прогона в таблицу выше вписывается результат и ссылка на отчёт.

## Самопроверка схемы

Файл `artifacts/schema-verify.sql запускается в DBeaver через Alt+X и проверяет:

- структуру: 8 таблиц, 5 enum-типов, 7 внешних ключей, 20 индексов;
- функцию контрольной суммы ИНН (валидный и невалидный);
- 11 ограничений негативными вставками, результат в таблице `verify_results (колонка passed).

Скрипт выполняется в транзакции и заканчивается ROLLBACK — тестовые данные в базе не остаются.
