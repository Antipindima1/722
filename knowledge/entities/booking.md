---
title: Бронирование
type: entity
status: draft
product: Каршеринг
updated: 2026-11-16
tags:
  - knowledge/entity
---

# Бронирование (Booking)

Резерв конкретного автомобиля за клиентом на ограниченный срок с контролем доступности.
Источник: `Vision 6`, `BRD 4`.

## Атрибуты

| Атрибут | Смысл | Источник |
|---|---|---|
| `booking_id` | Идентификатор брони; ключ сообщений Kafka | `API 2` |
| `user_id` | Владелец брони; проверяется против `JWT` | `API 1.2` |
| `car_id` | Забронированный автомобиль | `API 1.1` |
| `status` | Статус брони | `BRD 8.1`, `API 1.3` |
| `created_at`, `updated_at` | Метки времени; `updated_at` формирует `ETag` | `API 1.1` |
| `end_at` | Плановое окончание брони | `API 1.1` |
| `idempotency_key` | Ключ идемпотентности создания, хранится в самой брони | `API 1.3` |

## Статусы

`PENDING_HOLD` → `CONFIRMED` → `CONVERTED_TO_TRIP`; из `CONFIRMED` также `CANCELLED` и
`EXPIRED`. Переходы и условия — [[02-business-rules#4.1. Бронирование]].

## Правила

- Срок брони и бесплатная отмена — `AS-01`; лимит активных броней — `AS-02`;
  конкурентный доступ — `AS-03`.
- Отмена: `PENDING_HOLD` и `CONFIRMED` — 200 и переход в `CANCELLED`; `CANCELLED` —
  идемпотентно 200; `EXPIRED` и `CONVERTED_TO_TRIP` — 409. Источник: `API 1.3`.
- При `HoldFailed` бронь переходит в `CANCELLED`, причина берётся из поля `reason`
  события, публикуется `BookingCancelled`, автомобиль освобождается. Источник: `API 2.2.3`.
- Если бронь истекла к моменту прихода `HoldSucceeded`, в `CONFIRMED` она не переводится.
  Источник: `API 2.2.1.3`.

## События

`BookingConfirmed`, `BookingCancelled`, `BookingExpired` — топик `booking.events`,
публикует `Outbox Publisher`. Источник: `API 2.1`.

## Связи

[[client]] · [[car]] · [[trip]] · [[deposit]] · [[02-business-rules]]
