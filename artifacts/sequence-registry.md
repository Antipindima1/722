# Sequence — загрузка и проверка реестра (Ф1)

- **Артефакт:** `artifacts/sequence-registry.md` (диаграмма в PlantUML)
- **Фича:** Ф1 — `SCRUM-2187`, истории `SCRUM-2189`, `SCRUM-2190`
- **Проверка:** рендер в PlantUML (Kroki), сверка шагов с OpenAPI и правилами

## Сценарий

Загрузка файла, асинхронная проверка (включая проверку прошлых выплат), опрос статуса и
разбор отклонённых строк. Отдельно показаны отказ хранилища и недоставка события.

```plantuml
@startuml
title Ф1. Загрузка и проверка реестра

actor "Бухгалтер" as acc
participant "Веб-интерфейс" as web
participant "API Gateway" as api
participant "Сервис реестров" as reg
participant "Сервис выплат" as pay
database "БД реестров" as db
participant "Хранилище файлов" as s3
queue "Очередь событий" as mq

acc -> web : 1 Выбрать файл реестра
web -> api : 2 POST /registries {file, Idempotency-Key}
api -> reg : 3 POST /registries {file, Idempotency-Key, userId}

alt Файл и поля корректны
  reg -> db : 4 INSERT registry (status=UPLOADED, idempotency_key)
  reg -> s3 : 5 PUT file (object_key)
  reg -> db : 6 UPDATE registry (status=VALIDATING)
  reg -> mq : 7 Kafka RegistryUploaded {registry_id}
  reg --> api : 8 202 Accepted {registry_id, status=VALIDATING}
  api --> web : 9 202 Accepted
  web --> acc : 10 Экран «Проверяется»
else Формат или колонки неверны
  reg --> api : 11 400 Bad Request {code=FORMAT_INVALID, message}
  api --> web : 12 400
  web --> acc : 13 Ошибка загрузки с причиной
else Превышен лимит реестра
  reg --> api : 14 409 Conflict {code=REGISTRY_LIMIT_EXCEEDED}
  api --> web : 15 409
  web --> acc : 16 Сообщение о лимите
end

== Асинхронная проверка ==
mq -> reg : 17 RegistryUploaded {registry_id}
reg -> s3 : 18 GET file (object_key)

alt Файл недоступен в хранилище
  reg -> db : 19 UPDATE registry (status=BLOCKED)
  reg -> mq : 20 Kafka RegistryValidationFailed {registry_id, reason=FILE_UNAVAILABLE}
else Файл получен
  loop По 200 строк
    reg -> db : 21 INSERT rows (status=NEW, inn_hash)
    reg -> pay : 22 POST /payouts/exists:batch {items[{registryId, rowId}]}
    pay --> reg : 23 200 OK {results[{rowId, paid}]}
    alt paid = true
      reg -> db : 24 UPDATE row (status=REJECTED, reject_reason=ALREADY_PAID)
    end
    reg -> db : 25 UPDATE rows (status=VALIDATED / REJECTED, reject_reason)
  end
  alt Доля отклонённых больше 10%
    reg -> db : 26 UPDATE registry (status=BLOCKED)
  else Ошибок в пределах порога
    reg -> db : 27 UPDATE registry (status=CHECKED)
  end
  reg -> mq : 28 Kafka RegistryChecked {registry_id, status, rejected_count}
end

== Доставка событий ==
alt Брокер недоступен
  loop 3 попытки: 1 с, 5 с, 15 с
    reg -> mq : 29 Повторная публикация события
  end
  reg -> mq : 30 Публикация в DLQ {registry_id, reason=BROKER_UNAVAILABLE}
end

== Опрос статуса ==
acc -> web : 31 Обновить экран
web -> api : 32 GET /registries/{id} {If-None-Match: ETag}
api -> reg : 33 GET /registries/{id}
reg -> db : 34 SELECT registry (status, counts, updated_at)
alt ETag не изменился
  reg --> api : 35 304 Not Modified
else Состояние изменилось
  reg --> api : 36 200 OK {status, row_count, rejected_count, ETag}
end
api --> web : 37 Ответ
web --> acc : 38 Статус и счётчики

== Разбор отклонённых строк ==
acc -> web : 39 Открыть отклонённые строки
web -> api : 40 GET /registries/{id}/rows {status=REJECTED, limit=50, offset=0}
api -> reg : 41 GET /registries/{id}/rows
reg -> db : 42 SELECT rows (reject_reason, amount, inn_masked)
reg --> api : 43 200 OK {items[{rowId, rejectReason, rejectMessage}], total}
api --> web : 44 Ответ
web --> acc : 45 Список строк с причинами отказа

@enduml
```

## Соответствие спецификации

| Шаги | Операция OpenAPI | Код |
|---|---|---|
| 2, 3 | `POST /registries` | 202 |
| 11–16 | `POST /registries` (ошибки) | 400, 409 |
| 22, 23 | `POST /payouts/exists:batch` | 200 |
| 32–38 | `GET /registries/{registryId}` | 200, 304 |
| 40–45 | `GET /registries/{registryId}/rows` | 200 |

## Соответствие правилам

| Правило | Где на диаграмме |
|---|---|
| `CHK-01`, `CHK-02` (формат и обязательные колонки) | ветка «Формат или колонки неверны» |
| `CHK-03…CHK-06` (ИНН, дубли, сумма, телефон) | шаги 21, 25, `reject_reason` |
| **`CHK-07` (нет прошлой выплаты)** | **шаги 22–24: пакетный запрос в `Сервис выплат` (до 500 строк), причина `ALREADY_PAID`** |
| `AS-02` (лимиты) | ветка «Превышен лимит реестра» |
| `AS-13` (идемпотентность) | шаг 4 |
| `AS-14` (блокировка при >10% ошибок) | шаг 26 |
| `O-06`, `AS-15` (маскирование ПДн) | шаг 42 |
| **`AS-17` (ретраи и DLQ)** | **блок «Доставка событий»: 3 попытки 1/5/15 с, затем публикация в DLQ** |
| Отказ хранилища | ветка «Файл недоступен» → `BLOCKED` + событие об ошибке |

## Что не показано

- Выплаты по СБП — Ф2.
- Получение чека ФНС — вне выбранных фич.
- Повторная загрузка исправленного реестра — тот же сценарий с новым `Idempotency-Key`.
