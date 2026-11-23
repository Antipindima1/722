# Sequence — выплата по СБП (Ф2)

- **Артефакт:** `artifacts/feature-sbp-payout/sequence-payout.md` (PlantUML)
- **Фича:** Ф2 — `SCRUM-2188`, истории `SCRUM-2191`, `SCRUM-2203`
- **Проверка:** рендер PlantUML (Kroki), сверка шагов с OpenAPI и правилами

## Сценарий

Запуск пакета, проверки перед выплатой, отправка в СБП с повторами, частичный успех, разбор
ошибок и повторный запуск только по проблемным строкам.

Все повторные вызовы СБП идут с **тем же** `Idempotency-Key`, что и первая попытка: иначе
потерянный ответ превращается во второй перевод (`AS-13`, `CHK-11`).

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
else Суточный лимит компании превышен
  pay -> db : 8 SELECT sum(p.amount) за сутки по компании (payouts join registries)
  pay --> api : 9 409 {code=DAILY_LIMIT_EXCEEDED}
else Условия выполнены
  pay -> db : 10 INSERT payouts (status=CREATED)
  pay -> db : 11 UPDATE registry (status=PAYING)
  pay --> api : 12 202 Accepted {batchId, payoutCount}
  api --> web : 13 202
  web --> acc : 14 Экран «В выплате»
end

== Обработка строк ==
loop По каждой строке реестра
  pay -> fns : 15 запрос статуса самозанятого {inn}
  alt ФНС не ответила
    loop 3 попытки: 1 / 5 / 15 минут
      pay -> fns : 16 повтор запроса статуса
    end
    pay -> db : 17 UPDATE payout (status=ERROR, reason=FNS_UNAVAILABLE)
    pay -> mq : 18 событие PayoutFailed {payoutId, reason}
    pay -> mq : 19 публикация в DLQ {payoutId}
  else Статус утрачен
    fns --> pay : 20 {status=LOST}
    pay -> db : 21 UPDATE payout (status=DECLINED, reason=CONTRACTOR_STATUS_LOST)
  else Статус подтверждён
    fns --> pay : 22 {status=ACTIVE}
    pay -> db : 23 UPDATE payout (status=SENT_TO_SBP, attempts=1)
    pay -> sbp : 24 POST /payments {payoutId, phone, amount, Idempotency-Key}
    alt СБП подтвердил перевод
      sbp --> pay : 25 {status=EXECUTED, sbpRef}
      pay -> db : 26 UPDATE payout (status=EXECUTED, sbp_ref)
      pay -> mq : 27 событие PayoutSent {payoutId, amount}
    else СБП отклонил перевод (бизнес-причина)
      sbp --> pay : 28 {status=DECLINED, reason=SBP_REJECTED}
      pay -> db : 29 UPDATE payout (status=DECLINED, error_reason)
    else Техническая ошибка
      sbp --> pay : 30 {error}
      loop 3 попытки: 1 / 5 / 15 минут
        pay -> sbp : 31 повтор POST /payments {тот же Idempotency-Key}
        pay -> mq : 32 событие PayoutRetryScheduled {payoutId, attempt}
      end
      alt Попытки исчерпаны
        pay -> db : 33 UPDATE payout (status=ERROR, reason)
        pay -> mq : 34 событие PayoutFailed {payoutId, reason}
        pay -> mq : 35 публикация в DLQ {payoutId}
      end
    end
  end
end

pay -> db : 36 UPDATE registry (status=DONE / DONE_WITH_ERRORS)

== Отчёт и повторный запуск ==
acc -> web : 37 Открыть результаты выплаты
web -> api : 38 GET /registries/{id}/payouts {status, limit, offset}
api -> pay : 39 GET /registries/{id}/payouts
pay -> db : 40 SELECT payouts (status, attempts, error_reason)
pay --> api : 41 200 {items, total}
api --> web : 42 Ответ
web --> acc : 43 Выплачено, ошибки с причиной, DLQ

acc -> web : 44 Повторить по проблемным строкам
web -> api : 45 POST /registries/{id}/payouts/retry {Idempotency-Key}
api -> pay : 46 POST /retry
alt Нет выплат в статусе ERROR
  pay --> api : 47 409 {code=RETRY_NOT_ALLOWED}
else Есть проблемные строки
  pay -> db : 48 UPDATE payouts (status=CREATED) только для ERROR
  pay --> api : 49 202 Accepted
end

@enduml
```

## Соответствие спецификации

| Шаги | Операция OpenAPI | Код |
|---|---|---|
| 2, 3 | `POST /registries/{registryId}/payouts` | 202, 409 |
| 38–43 | `GET /registries/{registryId}/payouts` | 200 |
| 45–49 | `POST /registries/{registryId}/payouts/retry` | 202, 409 |

## Соответствие правилам

| Правило | Где на диаграмме |
|---|---|
| `CHK-09` (только «Проверен») | ветка «Реестр не в статусе CHECKED» |
| `CHK-10` (средства на пакет) | шаги 5–7 |
| `CHK-12` (суточный лимит компании) | шаги 8–9, сумма по компании за сутки |
| `CHK-08`, `AS-05` (статус в ФНС перед каждой выплатой) | шаги 15–22 |
| `CHK-07`, `CHK-11`, `AS-13` (идемпотентность) | уникальный `row_id`; шаги 24 и 31 — один и тот же `Idempotency-Key` |
| `AS-17` (3 попытки 1/5/15 минут, DLQ) | шаги 16–19 (ФНС), 31–35 (СБП) |
| `AS-06` (частичный успех) | строки обрабатываются независимо, шаг 36 |
| `AS-21` (события выплат) | шаги 18, 27, 32, 34 |
| §4.1 (реестр «В выплате») | шаг 11: `PAYING` перед обработкой |
| Бизнес-отказ ≠ тех. ошибка | шаги 28–29 (`DECLINED`, без повторов) против 30–35 (`ERROR`, DLQ) |
| `SCRUM-2192` (отчёт, повтор по проблемным) | шаги 37–49 |

## Что не показано

- Получение чека ФНС — вне выбранных фич (`O-05`, `AS-07`), обязательное следствие выплаты.
- Возвраты и аннулирование чека — вне фич (`AS-08`).
