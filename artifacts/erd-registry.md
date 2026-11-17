# ERD + DDL — реестр выплат и выплаты (Ф1, задел Ф2)

- **Артефакты:** `artifacts/erd-registry.md` (модель), `artifacts/schema-registry.sql` (DDL)
- **Фичи:** Ф1 (`SCRUM-2187`, `SCRUM-2189`, `SCRUM-2190`), задел под Ф2
- **Проверка:** исполнение DDL на PGlite (WASM PostgreSQL 15+)
- **Дата:** 2026-11-17

## Модель (DBML)

```dbml
Table companies {
  id uuid [pk]
  name text [not null]
  created_at timestamptz [not null]
}

Table contractors {
  id uuid [pk]
  inn char(12) [not null, unique]
  full_name text [not null]
  phone text [not null]
  self_employed_status text [not null]
  status_checked_at timestamptz
  created_at timestamptz [not null]
}

Table validation_reports {
  registry_id uuid [pk, ref: - registries.id]
  row_count integer [not null]
  accepted_count integer [not null]
  rejected_count integer [not null]
  error_share numeric(5,4) [not null]
  reasons jsonb [not null]
  generated_at timestamptz [not null]
}

Table registries {
  id uuid [pk]
  company_id uuid [not null, ref: > companies.id]
  status registry_status [not null]
  file_name text [not null]
  object_key text [not null]
  row_count integer [not null]
  total_amount numeric(14,2) [not null]
  accepted_count integer [not null]
  rejected_count integer [not null]
  error_share numeric(5,4)
  idempotency_key text [not null, unique]
  created_at timestamptz [not null]
  updated_at timestamptz [not null]
}

Table payout_rows {
  id uuid [pk]
  registry_id uuid [not null, ref: > registries.id]
  contractor_id uuid [ref: > contractors.id]
  full_name text [not null]
  inn char(12) [not null]
  phone text [not null]
  amount numeric(14,2) [not null]
  purpose text [not null]
  status row_status [not null]
  reject_reason reject_reason
  created_at timestamptz [not null]
}

Table payouts {
  id uuid [pk]
  registry_id uuid [not null, ref: > registries.id]
  row_id uuid [not null, unique, ref: - payout_rows.id]
  contractor_id uuid [ref: > contractors.id]
  amount numeric(14,2) [not null]
  status payout_status [not null]
  sbp_ref text
  attempts integer [not null]
  created_at timestamptz [not null]
  updated_at timestamptz [not null]
}

Table processed_events {
  event_id uuid [pk]
  consumer text [not null]
  processed_at timestamptz [not null]
}

Table receipts {
  id uuid [pk]
  payout_id uuid [not null, unique, ref: - payouts.id]
  status receipt_status [not null]
  received_at timestamptz
  created_at timestamptz [not null]
}
```

## Принятые решения

| Решение | Почему так | Источник |
|---|---|---|
| `payouts.row_id` уникален | одна выплата на строку реестра — защита от повторного перевода на уровне БД, а не только в коде | `CHK-07`, `AS-13` |
| `registries.idempotency_key` уникален | повторная загрузка с тем же ключом не создаёт второй реестр | `AS-13` |
| `registries.row_count <= 5000`, `amount <= 1 000 000` | лимиты из допущений продублированы в БД, чтобы их нельзя было обойти | `AS-02` |
| Статус `VALIDATION_FAILED` отдельно от `BLOCKED` | технический сбой ≠ блокировка по качеству данных | `AS-19` |
| `status` строки и наличие `reject_reason` связаны CHECK | отклонённая строка обязана иметь причину, принятая — не иметь | `CHK-03…CHK-07` |
| `payouts.attempts <= 3` | не более трёх попыток отправки в СБП | `AS-17` |
| `receipts.status = RECEIVED` требует `received_at` | чек не может быть получен без даты | `O-05`, `AS-07` |
| `payout_rows.inn` хранится как в файле, без FK на `contractors.inn` | в реестре бывают неверные и неизвестные ИНН; связь с исполнителем появляется после проверки | `CHK-03`, `CHK-08` |
| Пять enum-типов вместо текстовых статусов | статусы ограничены на уровне БД | `02-business-rules.md` §4 |
| Таблица `processed_events` | `eventId` из AsyncAPI должен где-то храниться, иначе защита от повторной обработки не работает | `AS-13` |
| Частичный уникальный индекс `(registry_id, inn) WHERE status='VALIDATED'` | `O-08` запрещает дубли ИНН в реестре; на уровне БД это возможно только для принятых строк | `O-08` |
| Индекс `payouts(registry_id)` | отчёт по результатам выплаты читает выплаты по реестру | `SCRUM-2192` |
| Функция `inn_is_valid` + CHECK на ИНН | контрольная сумма ИНН — требование критериев приёмки, а не пожелание; формат проверять недостаточно | `AS-09`, `SCRUM-2190` |
| `registries.total_amount <= 10 000 000` | лимит реестра по сумме, не только по числу строк | `AS-02`, `SCRUM-2189` |
| Таблица `validation_reports` | отчёт должен сохраняться вместе с реестром, а не собираться каждый раз заново | `SCRUM-2190` |

## Трассировка

| Требование | Где в модели |
|---|---|
| Приём реестра и его статусы | `registries.status` (`UPLOADED…CANCELLED`) |
| Счётчики проверки и доля ошибок | `registries.accepted_count`, `rejected_count`, `error_share` |
| Причина отказа по строке | `payout_rows.reject_reason` |
| Отсутствие повторной выплаты | `payouts.row_id` unique |
| Попытки отправки в СБП | `payouts.attempts` |
| Чек по каждой выплате | `receipts.payout_id` unique |
| Контрольная сумма ИНН | `inn_is_valid()` в CHECK у `contractors.inn` и `payout_rows.inn` |
| Лимит суммы реестра | `registries.total_amount <= 10 000 000` |
| Сохранение отчёта о проверке | `validation_reports` (первичный ключ — `registry_id`) |

## Ограничения модели

- **Чеки и возвраты** описаны заделом под Ф2; в Ф1 таблица `receipts` не заполняется.
- **История статусов** не хранится отдельной таблицей: в требованиях Ф1 аудит не заявлен.
- **Контрольная сумма ИНН** реализована SQL-функцией inn_is_valid одним выражением (без PL/pgSQL), чтобы скрипт проходил онлайн-редакторы; при переносе на другую СУБД алгоритм нужно повторить.
- **Идемпотентность входящих событий** обеспечена таблицей `processed_events` (`AS-13`).
