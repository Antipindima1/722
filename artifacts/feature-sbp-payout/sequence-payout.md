# Sequence — выплата по СБП (Ф2)

- **Артефакт:** `artifacts/feature-sbp-payout/sequence-payout.md` (PlantUML)
- **Фича:** Ф2 — `SCRUM-2188`, истории `SCRUM-2191`, `SCRUM-2203`
- **Проверка:** рендер PlantUML (Kroki), сверка шагов с OpenAPI и правилами

## Сценарий

Запуск пакета, проверки перед выплатой, отправка в СБП с повторами, частичный успех, разбор
ошибок и повторный запуск только по проблемным строкам.

```plantuml
@startuml
title Ф2. Выплата по СБП

actor "Бухгалтер" as acc
participant "Веб-интерфейс" as web
participant "API Gateway" as api
participant "Сервис выплат" as pay
participant "Адаптер ФНС" as fns
participant "СБП" as sbp
participant "Банк компании" as bank
database "БД выплат" as db
queue "Очередь событий" as mq

acc -> web : 1 Запустить выплаты по реестру
web -> api : 2 POST /registries/{id}/payouts {Idempotency-Key}
api -> pay : 3 POST /registries/{id}/payouts {userId, Idempotency-Key}

alt Реестр не в статусе CHECKED
  pay --> api : 4 409 {code=REGISTRY_NOT_CHECKED}
else Средств на пакет недостаточно
  pay -> bank : 5 GET /balance
  bank --> pay : 6 {balance}
  pay --> api : 7 409 {code=INSUFFICIENT_FUNDS}
else Суточный лимит превышен
  pay -> db : 8 SELECT sum(amount) за сутки
  pay --> api : 9 409 {code=DAILY_LIMIT_EXCEEDED}
else Условия выполнены
  pay -> db : 10 INSERT payouts (status=CREATED)
  pay --> api : 11 202 Accepted {batchId, payoutCount}
  api --> web : 12 202
  web --> acc : 13 Экран «В выплате»
end

== Обработка строк ==
loop По каждой строке реестра
  pay -> fns : 14 запрос статуса самозанятого {inn}
  fns --> pay : 15 {status}
  alt Статус утрачен
    pay -> db : 16 UPDATE payout (status=DECLINED, reason=CONTRACTOR_STATUS_LOST)
  else Статус подтверждён
    pay -> db : 17 UPDATE payout (status=SENT_TO_SBP, attempts=1)
    pay -> sbp : 18 POST /payments {payoutId, phone, amount, Idempotency-Key}
    alt СБП подтвердил перевод
      sbp --> pay : 19 {status=EXECUTED, sbpRef}
      pay -> db : 20 UPDATE payout (status=EXECUTED, sbp_ref)
      pay -> mq : 21 событие PayoutSent {payoutId, amount}
    else Техническая ошибка
      sbp --> pay : 22 {error}
      loop 3 попытки: 1 / 5 / 15 минут
        pay -> sbp : 23 повтор POST /payments
        pay -> mq : 24 событие PayoutRetryScheduled {payoutId, attempt}
      end
      alt Попытки исчерпаны
        pay -> db : 25 UPDATE payout (status=ERROR, reason)
        pay -> mq : 26 событие PayoutFailed {payoutId, reason}
        pay -> mq : 27 публикация в DLQ {payoutId}
      end
    end
  end
end

pay -> db : 28 UPDATE registry (status=DONE / DONE_WITH_ERRORS)

== Отчёт и повторный запуск ==
acc -> web : 29 Открыть результаты выплаты
web -> api : 30 GET /registries/{id}/payouts {status, limit, offset}
api -> pay : 31 GET /registries/{id}/payouts
pay -> db : 32 SELECT payouts (status, attempts, error_reason)
pay --> api : 33 200 {items, total}
api --> web : 34 Ответ
web --> acc : 35 Выплачено, ошибки с причиной, DLQ

acc -> web : 36 Повторить по проблемным строкам
web -> api : 37 POST /registries/{id}/payouts/retry {Idempotency-Key}
api -> pay : 38 POST /retry
alt Нет выплат в статусе ERROR
  pay --> api : 39 409 {code=RETRY_NOT_ALLOWED}
else Есть проблемные строки
  pay -> db : 40 UPDATE payouts (status=CREATED) только для ERROR
  pay --> api : 41 202 Accepted
end

@enduml
```

## Соответствие спецификации

| Шаги | Операция OpenAPI | Код |
|---|---|---|
| 2, 3 | `POST /registries/{registryId}/payouts` | 202, 409 |
| 30–35 | `GET /registries/{registryId}/payouts` | 200 |
| 37–41 | `POST /registries/{registryId}/payouts/retry` | 202, 409 |

## Соответствие правилам

| Правило | Где на диаграмме |
|---|---|
| `CHK-09` (только «Проверен») | ветка «Реестр не в статусе CHECKED» |
| `CHK-10` (средства на пакет) | шаги 5–7 |
| `CHK-12` (суточный лимит) | шаги 8–9 |
| `CHK-08`, `AS-05` (статус в ФНС перед каждой выплатой) | шаги 14–16 |
| `CHK-07`, `CHK-11`, `AS-13` (идемпотентность) | уникальный `row_id`, шаг 18 с `Idempotency-Key` |
| `AS-17` (3 попытки 1/5/15 минут, DLQ) | шаги 22–27 |
| `AS-06` (частичный успех) | строки обрабатываются независимо, шаг 28 |
| `AS-21` (события выплат) | шаги 21, 24, 26 |
| `SCRUM-2192` (отчёт, повтор по проблемным) | шаги 29–41 |

## Что не показано

- Получение чека ФНС — вне выбранных фич (`O-05`, `AS-07`), обязательное следствие выплаты.
- Возвраты и аннулирование чека — вне фич (`AS-08`).
