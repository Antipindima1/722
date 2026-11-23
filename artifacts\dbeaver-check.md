# Проверка DDL в DBeaver

- **Требование:** «Данные → ER + DDL PostgreSQL → DDL выполняется в DBeaver без ошибок» (SA-2378)
- **Инструмент:** DBeaver, соединение с PostgreSQL (Neon)
- **Дата:** 2026-11-18
- **Результат:** DDL применён без ошибок; самопроверка схемы пройдена

## Как выполнялось

1. Соединение с PostgreSQL открыто в DBeaver.
2. Выполнен `artifacts/f1-registry/schema-reset.sql` — снята прошлая схема.
3. Выполнен `artifacts/f1-registry/schema-registry.sql` целиком через **Alt+X (Execute SQL Script)**.
4. Выполнен `artifacts/f1-registry/schema-verify.sql` — самопроверка.

## Почему Alt+X, а не Ctrl+Enter

`Ctrl+Enter` в DBeaver выполняет только инструкцию под курсором. При таком запуске
`COMMENT ON TABLE receipts` падает с `relation "receipts" does not exist` — таблицы ещё
не созданы. Это ошибка запуска, а не DDL.

## Скриншот

На снимке видно: 8 таблиц в схеме `public` (`companies`, `contractors`, `payout_rows`, `payouts`, `processed_events`, `receipts`, `registries`, `validation_reports`), открытый скрипт и результат `verify_results` — 11 строк, `passed = true` у всех.

Файл скриншота:
[`artifacts/dbeaver-schema-verify.png`](dbeaver-schema-verify.png) — DBeaver 26.2.1, соединение `neondb`.

## Ожидаемые числа проверки

| Показатель | Значение |
|---|---|
| Наши таблицы | 8 |
| Лишние таблицы в схеме (не наши) | 5 |
| Всего таблиц в `public` | 13 |
| Enum-типы | 5 |
| Внешние ключи (по нашим таблицам) | 7 |
| Индексы (по нашим таблицам) | 20 |
| `inn_is_valid` для валидного / невалидного ИНН | `true` / `false` |
| Проверок ограничений пройдено | 11 из 11 |

## Что это подтверждает

- DDL синтаксически корректен для PostgreSQL и применяется штатным клиентом, а не только
  через тестовый движок.
- Ограничения не декоративные: 11 негативных вставок отбиты базой.
- Функция контрольной суммы ИНН работает.
- Модель не конфликтует с уже существующими таблицами в схеме.
