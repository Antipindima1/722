# Проверка артефактов Ф1: OpenAPI + Sequence

- **Артефакты:** `artifacts/openapi-registry.yaml`, `artifacts/sequence-registry.md`
- **Инструменты из таблицы требований:** Spectral (OpenAPI), рендер PlantUML (Sequence)
- **Дата:** 2026-11-17

## 1. Самопроверка агента по чек-листу навыка

Чек-лист `skills/openapi-design/SKILL.md`, раздел «Чек-лист самопроверки перед PR».

| # | Пункт | Результат | Чем подтверждается |
|---|---|---|---|
| 1 | Прочитаны актуальные Story, критерии приёмки и связанные задачи | да | `SCRUM-2187`, `SCRUM-2189`, `SCRUM-2190` прочитаны целиком |
| 2 | Проверены `knowledge` и статусы допущений | да | `02-business-rules.md` (`O-`, `CHK-`), `03-assumptions.md` (`AS-01`, `AS-02`, `AS-13`, `AS-14`, `AS-15`) |
| 3 | Каждое существенное требование имеет источник | да | таблица «Трассировка» в `openapi-registry.md` и таблица соответствия в `sequence-registry.md` |
| 4 | Термины и статусы согласованы с источниками | да | статусы реестра и строки совпадают с §4.1–4.2 `02-business-rules.md` |
| 5 | Нет придуманных требований и полей | **было замечание, исправлено** | первая версия спеки не имела описания у `GET /registries` — Spectral выдал `operation-description`, добавлено |
| 6 | Формат соответствует нотации | да | OpenAPI 3.0.3, PlantUML sequence |
| 7 | Согласован с другими артефактами | да | имена контейнеров совпадают с C4 L2: `API Gateway`, `Сервис реестров`, `Хранилище файлов` |
| 8 | Открытые вопросы и допущения обозначены | да | раздел «Открытые вопросы» в `openapi-registry.md` |
| 9 | Ссылки, имена файлов, синтаксис проверены | да | Spectral 0 ошибок, рендер 200 |
| 10 | Diff только в рамках задачи, без секретов и ПДн | да | добавлены только артефакты Ф1 и `.spectral.yaml`; данных клиентов нет |
| 11 | PR описывает изменения, источники, проверки, ограничения | да | тело PR |
| 12 | PR выполнен при наличии прав и разрешения | да | разрешение пользователя |

## 2. Прогон Spectral

```
node pnpm.mjs dlx @stoplight/spectral-cli@6 lint artifacts/openapi-registry.yaml \
     --ruleset .spectral.yaml --format json
```

| Параметр | Значение |
|---|---|
| Версия Spectral | 6.17.1 |
| Ruleset | `.spectral.yaml`: `spectral:oas` + `operation-description`, `operation-tags`, `operation-operationId`, `tag-description`, `no-$ref-siblings` как `error` |
| Код возврата | **0** |
| Ошибок | **0** |
| Предупреждений | 0 |

Первый прогон дал одно нарушение: `operation-description` на `GET /registries` — описание
операции отсутствовало. Исправлено, повторный прогон чистый.

## 3. Рендер Sequence

```
POST https://kroki.io/plantuml/svg  (тело — блок ```plantuml``` из sequence-registry.md)
```

| Параметр | Значение |
|---|---|
| HTTP | **200** |
| SVG | 36 844 байта |
| Canvas | 2082×1721 |
| Проверка содержимого | 10 из 10: участники, `202 Accepted`, `RegistryUploaded`, `304 Not Modified`, `rejectReason` и др. |

## 4. Сверка с критериями приёмки

| История | Критерий | Где |
|---|---|---|
| SCRUM-2189 | приём CSV/XLSX с обязательными колонками | `POST /registries`, `multipart/form-data` |
| SCRUM-2189 | лимиты реестра | `409` + описание лимита |
| SCRUM-2189 | статусы «Загружен» → «Проверяется» | `RegistryStatus`, шаги 4–10 диаграммы |
| SCRUM-2190 | отчёт по каждой строке с причиной | `GET /rows`, `rejectReason`, `rejectMessage` |
| SCRUM-2190 | блокировка при превышении доли ошибок | `GET /report`, поле `blocked`; шаг 21 диаграммы |

## 5. Что проверка НЕ подтверждает

- **Соответствие реальному коду.** Спецификация проектная, реализации нет — Spectral проверяет
  только формат и полноту описания, не поведение.
- **Контракты внешних систем.** ФНС и СБП в Ф1 не участвуют; для Ф2 их контракты неизвестны
  (`AS-16`).
- **Нагрузочные характеристики.** Асинхронность заявлена, но время проверки 5 000 строк не
  измерялось.

## 6. Как воспроизвести

```bash
export PATH="<node-bin>:$PATH"
node <pnpm.mjs> dlx @stoplight/spectral-cli@6 lint artifacts/openapi-registry.yaml \
     --ruleset .spectral.yaml

sed -n '/```plantuml/,/```/p' artifacts/sequence-registry.md | sed '1d;$d' > /tmp/seq.puml
curl -s -X POST https://kroki.io/plantuml/svg -H "Content-Type: text/plain" \
     --data-binary @/tmp/seq.puml -o artifacts/sequence-registry.svg
```

## 9. Правки по замечаниям ревью

| Замечание | Что сделано | Проверка |
|---|---|---|
| S-01 `CHK-07` не обеспечена данными | добавлена операция `GET /payouts/exists`; на диаграмме — шаги 22–24 с обращением к `Сервис выплат` и причиной `ALREADY_PAID` | Spectral 0 ошибок; в SVG найдены `GET /payouts/exists` и `ALREADY_PAID` |
| S-02 нет ветки недоставки события | добавлен блок «Доставка событий»: 3 попытки 1/5/15 с, затем `DLQ` | в SVG найдены `DLQ` и `RegistryValidationFailed` |
| S-03 `format: decimal` | суммы стали строками с `pattern: '^\\d+\\.\\d{2}$'` | Spectral 0 ошибок |
| S-04 нет ветки «файл недоступен» | добавлена ветка: статус `BLOCKED` + событие `RegistryValidationFailed` | в SVG найдена ветка «Файл недоступен» |

Повторные прогоны после правок:

| Проверка | Результат |
|---|---|
| Spectral (код возврата) | **0** |
| Spectral (ошибок) | **0** |
| Рендер Sequence HTTP | **200** |
| SVG | 45 374 байта, canvas 2096×2167 |
| Содержимое SVG | **10 из 10** проверок |

## 10. Справочник кодов ошибок

Добавлен по замечанию: HTTP-коды были, машиночитаемых кодов ошибок не было.

| Что сделано | Где |
|---|---|
| Схема `ErrorCode` с 10 значениями | `openapi-registry.yaml`, components.schemas |
| `Error.code` ссылается на `ErrorCode` | там же |
| Таблица «код → HTTP → когда → что делать» | `openapi-registry.md`, раздел «Коды ошибок» |

Коды: `FORMAT_INVALID`, `MISSING_REQUIRED_COLUMNS`, `INVALID_QUERY_PARAM`,
`UNAUTHENTICATED`, `FORBIDDEN`, `REGISTRY_NOT_FOUND`, `REGISTRY_LIMIT_EXCEEDED`,
`REGISTRY_BLOCKED`, `IDEMPOTENCY_KEY_REUSED`, `FILE_TOO_LARGE`.

Повторный прогон Spectral: код возврата **0**, ошибок **0**.

## 11. Серверные ошибки (5xx)

Добавлено по замечанию: в спецификации были только клиентские коды 4xx.

| Что сделано | Где |
|---|---|
| Ответы `500 ServerError` и `503 ServiceUnavailable` | прикреплены ко всем 6 операциям |
| Заголовок `Retry-After` у `503` | `components.responses.ServiceUnavailable` |
| Коды `INTERNAL_ERROR`, `SERVICE_UNAVAILABLE`, `UPSTREAM_TIMEOUT` | `ErrorCode` |
| Правило повтора для 5xx | `openapi-registry.md`, раздел «Коды ошибок» |

Смысл: 5xx не означает, что операция не выполнена. Загрузка идемпотентна по `Idempotency-Key`,
поэтому повтор безопасен; `Retry-After` задаёт паузу.

Повторный прогон Spectral: код возврата **0**, ошибок **0**.
