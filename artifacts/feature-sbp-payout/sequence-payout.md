# Sequence — выплата по СБП (Ф2)

- **Артефакт:** `artifacts/feature-sbp-payout/sequence-payout.md` (PlantUML)
- **Фича:** Ф2 — `SCRUM-2188`, истории `SCRUM-2191`, `SCRUM-2203`
- **Проверка:** рендер PlantUML (Kroki), сверка шагов с OpenAPI и правилами

## Сценарий

Запуск пакета, проверки перед выплатой, отправка в СБП с повторами, частичный успех, разбор
ошибок и повторный запуск только по проблемным строкам.

Все повторные вызовы СБП идут с **тем же** `Idempotency-Key`, что и первая попытка: иначе
потерянный ответ превращается во второй перевод (`AS-13`, `CHK-11`).

Событие `PayoutFailed` публикуется и при техническом отказе, и при бизнес-отказе (утрата
статуса, отказ СБП): потребители должны узнать о неуспешной выплате в любом случае (`AS-21`).

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
    pay -> mq : 18 событие PayoutFailed {payoutId, reason=FNS_UNAVAILABLE}
    pay -> mq : 19 публикация в DLQ {payoutId}
  else Статус утрачен
    fns --> pay : 20 {status=LOST}
    pay -> db : 21 UPDATE payout (status=DECLINED, reason=CONTRACTOR_STATUS_LOST)
    pay -> mq : 22 событие PayoutFailed {payoutId, reason=CONTRACTOR_STATUS_LOST}
  else Статус подтверждён
    fns --> pay : 23 {status=ACTIVE}
    pay -> db : 24 UPDATE payout (status=SENT_TO_SBP, attempts=1)
    pay -> sbp : 25 POST /payments {payoutId, phone, amount, Idempotency-Key}
    alt СБП подтвердил перевод
      sbp --> pay : 26 {status=EXECUTED, sbpRef}
      pay -> db : 27 UPDATE payout (status=EXECUTED, sbp_ref)
      pay -> mq : 28 событие PayoutSent {payoutId, amount}
    else СБП отклонил перевод (бизнес-причина)
      sbp --> pay : 29 {status=DECLINED, reason=SBP_REJECTED}
      pay -> db : 30 UPDATE payout (status=DECLINED, error_reason)
      pay -> mq : 31 событие PayoutFailed {payoutId, reason=SBP_REJECTED}
    else Техническая ошибка
      sbp --> pay : 32 {error}
      loop 3 попытки: 1 / 5 / 15 минут
        pay -> sbp : 33 повтор POST /payments {тот же Idempotency-Key}
        pay -> mq : 34 событие PayoutRetryScheduled {payoutId, attempt}
      end
      alt Попытки исчерпаны
        pay -> db : 35 UPDATE payout (status=ERROR, reason)
        pay -> mq : 36 событие PayoutFailed {payoutId, reason}
        pay -> mq : 37 публикация в DLQ {payoutId}
      end
    end
  end
end

pay -> db : 38 UPDATE registry (status=DONE / DONE_WITH_ERRORS)

== Отчёт и повторный запуск ==
acc -> web : 39 Открыть результаты выплаты
web -> api : 40 GET /registries/{id}/payouts {status, limit, offset}
api -> pay : 41 GET /registries/{id}/payouts
pay -> db : 42 SELECT payouts (status, attempts, error_reason)
pay --> api : 43 200 {items, total}
api --> web : 44 Ответ
web --> acc : 45 Выплачено, ошибки с причиной, DLQ

acc -> web : 46 Повторить по проблемным строкам
web -> api : 47 POST /registries/{id}/payouts/retry {Idempotency-Key}
api -> pay : 48 POST /retry
alt Нет выплат в статусе ERROR
  pay --> api : 49 409 {code=RETRY_NOT_ALLOWED}
else Есть проблемные строки
  pay -> db : 50 UPDATE payouts (status=CREATED) только для ERROR
  pay --> api : 51 202 Accepted
end

@enduml
```

## Соответствие спецификации

| Шаги | Операция OpenAPI | Код |
|---|---|---|
| 2, 3 | `POST /registries/{registryId}/payouts` | 202, 409 |
| 40–45 | `GET /registries/{registryId}/payouts` | 200 |
| 47–51 | `POST /registries/{registryId}/payouts/retry` | 202, 409 |

## Соответствие правилам

| Правило | Где на диаграмме |
|---|---|
| `CHK-09` (только «Проверен») | ветка «Реестр не в статусе CHECKED» |
| `CHK-10` (средства на пакет) | шаги 5–7 |
| `CHK-12` (суточный лимит компании) | шаги 8–9, сумма по компании за сутки |
| `CHK-08`, `AS-05` (статус в ФНС перед каждой выплатой) | шаги 15–23 |
| `CHK-07`, `CHK-11`, `AS-13` (идемпотентность) | уникальный `row_id`; шаги 25 и 33 — один и тот же `Idempotency-Key` |
| `AS-17` (3 попытки 1/5/15 минут, DLQ) | шаги 16–19 (ФНС), 33–37 (СБП) |
| `AS-06` (частичный успех) | строки обрабатываются независимо, шаг 38 |
| `AS-21` (события выплат) | шаги 18, 22, 28, 31, 34, 36 |
| §4.1 (реестр «В выплате») | шаг 11: `PAYING` перед обработкой |
| Бизнес-отказ ≠ тех. ошибка | шаги 21–22 и 29–31 (`DECLINED`, без повторов) против 32–37 (`ERROR`, DLQ) |
| `SCRUM-2192` (отчёт, повтор по проблемным) | шаги 39–51 |

## Что не показано

- Получение чека ФНС — вне выбранных фич (`O-05`, `AS-07`), обязательное следствие выплаты.
- Возвраты и аннулирование чека — вне фич (`AS-08`).
