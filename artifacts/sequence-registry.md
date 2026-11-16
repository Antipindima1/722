# Sequence — загрузка и проверка реестра (Ф1)

- **Артефакт:** `artifacts/sequence-registry.md` (диаграмма в PlantUML)
- **Фича:** Ф1 — `SCRUM-2187`, истории `SCRUM-2189`, `SCRUM-2190`
- **Проверка:** рендер в PlantUML (Kroki), сверка шагов с OpenAPI и правилами

## Сценарий

Загрузка файла реестра, асинхронная проверка, опрос статуса и разбор отклонённых строк.

```plantuml
@startuml
title Ф1. Загрузка и проверка реестра

actor "Бухгалтер" as acc
participant "Веб-интерфейс" as web
participant "API Gateway" as api
participant "Сервис реестров" as reg
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
loop По 200 строк
  reg -> db : 19 INSERT rows (status=NEW)
  reg -> db : 20 UPDATE rows (status=VALIDATED / REJECTED, reject_reason)
end
alt Доля отклонённых больше 10%
  reg -> db : 21 UPDATE registry (status=BLOCKED)
else Ошибок в пределах порога
  reg -> db : 22 UPDATE registry (status=CHECKED)
end
reg -> mq : 23 Kafka RegistryChecked {registry_id, status, rejected_count}

== Опрос статуса ==
acc -> web : 24 Обновить экран
web -> api : 25 GET /registries/{id} {If-None-Match: ETag}
api -> reg : 26 GET /registries/{id}
reg -> db : 27 SELECT registry (status, counts, updated_at)
alt ETag не изменился
  reg --> api : 28 304 Not Modified
else Состояние изменилось
  reg --> api : 29 200 OK {status, row_count, rejected_count, ETag}
end
api --> web : 30 Ответ
web --> acc : 31 Статус и счётчики

== Разбор отклонённых строк ==
acc -> web : 32 Открыть отклонённые строки
web -> api : 33 GET /registries/{id}/rows {status=REJECTED, limit=50, offset=0}
api -> reg : 34 GET /registries/{id}/rows
reg -> db : 35 SELECT rows (reject_reason, amount, inn_masked)
reg --> api : 36 200 OK {items[{rowId, rejectReason, rejectMessage}], total}
api --> web : 37 Ответ
web --> acc : 38 Список строк с причинами отказа

@enduml
```

## Соответствие спецификации

| Шаг диаграммы | Операция OpenAPI | Код |
|---|---|---|
| 2, 3 | `POST /registries` | 202 |
| 11–16 | `POST /registries` (ошибки) | 400, 409 |
| 25–31 | `GET /registries/{registryId}` | 200, 304 |
| 33–38 | `GET /registries/{registryId}/rows` | 200 |

## Соответствие правилам

| Правило | Где на диаграмме |
|---|---|
| `CHK-01`, `CHK-02` (формат и обязательные колонки) | ветка «Формат или колонки неверны» |
| `CHK-03…CHK-07` (ИНН, дубли, сумма, телефон, повтор) | шаги 19–20, `reject_reason` |
| `AS-02` (лимиты реестра) | ветка «Превышен лимит реестра» |
| `AS-13` (идемпотентность) | шаг 4, ключ идемпотентности в `INSERT` |
| `AS-14` (блокировка при >10% ошибок) | шаг 21 |
| `O-06`, `AS-15` (маскирование ПДн) | шаг 35, `inn_masked` |
| `AS-17` (события и доставка) | шаги 7, 23, очередь событий |

## Что не показано

- Выплаты по СБП — это Ф2, отдельный сценарий.
- Получение чека ФНС — вне выбранных фич.
- Повторная загрузка исправленного реестра — тот же сценарий с новым `Idempotency-Key`.
