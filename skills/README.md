---
title: Skills Catalog
description: Каталог навыков AI-агента под артефакты проекта.
tags:
  - skills
  - agent
---

# Skills — каталог навыков агента

Состав покрывает **четыре** типа артефактов, поэтому оставлены только навыки под них.
Остальные навыки (процессные и по нотациям, не входящим в состав артефактов) удалены.

Каждый навык хранится в `skills/<skill-name>/SKILL.md`.

## Как выбирать skill

1. Прочитай корневой `AGENTS.md`.
2. Определи, какой из четырёх артефактов нужен.
3. Открой `SKILL.md` соответствующего навыка.
4. Для артефакта «OpenAPI + Sequence» используй два навыка последовательно:
   `openapi-design`, затем `sequence-diagram`.
5. Не запускай все навыки автоматически. При конфликте приоритет у `AGENTS.md`.

## Каталог

| Skill | Артефакт | Когда применять | Чем проверяется |
|---|---|---|---|
| [c4-container-diagram](c4-container-diagram/SKILL.md) | C4, уровень 2 (контейнеры) | Нужна архитектура контейнеров и связей между ними | Рендер в PlantUML C4 или Structurizr, аргументация решений |
| [openapi-design](openapi-design/SKILL.md) | OpenAPI + Sequence | Синхронные интеграции: REST-контракт | Spectral |
| [sequence-diagram](sequence-diagram/SKILL.md) | OpenAPI + Sequence | Взаимодействие сервисов во времени, включая ошибки и ретраи | Ревью против `BRD`, `API` |
| [asyncapi-design](asyncapi-design/SKILL.md) | AsyncAPI | Асинхронные события и каналы (Kafka) | AsyncAPI CLI validate |
| [erd-data-model](erd-data-model/SKILL.md) | ER + DDL PostgreSQL | Модель данных и физическая схема БД | DDL выполняется в DBeaver без ошибок |
| [Смотрящий](smotryashchiy/SKILL.md) | Проверка любого из артефактов | Нужно найти ошибки в готовом результате и обосновать их | Отчёт `artifacts/<артефакт>-review.md` + запрос на исправление |

## Проверка результата

Перед сдачей любой артефакт проходит через [Смотрящего](smotryashchiy/SKILL.md) — навык-критик.
Он не правит артефакт, а находит ошибки, аргументирует каждую ссылкой на требование и
формирует готовый запрос на исправление. Правило жёсткое: замечание без обоснования
(«почему это ошибка» + источник) не выдаётся, а допущение не считается ошибкой.

## Типовые сочетания

| Цель | Навыки |
|---|---|
| Спроектировать архитектуру | `c4-container-diagram` |
| Описать синхронную интеграцию | `openapi-design` → `sequence-diagram` |
| Описать асинхронную интеграцию | `asyncapi-design` → при необходимости `sequence-diagram` |
| Спроектировать данные | `erd-data-model` |
| Сверить артефакты между собой | последовательно `c4-container-diagram` → `openapi-design` / `asyncapi-design` → `erd-data-model`, сверка по `knowledge/02-business-rules.md` |

## Важные разграничения

- C4 L2 — контейнеры и их взаимодействие; это не BPMN и не ER-модель.
- C4 L4 (код) не входит в назначение: детализация до классов не требуется.
- OpenAPI описывает HTTP API, AsyncAPI — message-driven API. Не объединяй их в один контракт.
- Sequence Diagram показывает взаимодействия во времени, а не состояния сущности.
- ER + DDL: DDL должен выполняться в PostgreSQL без ошибок, иначе артефакт не принят.

## Общий принцип

Все проектные факты берутся только из Jira и `knowledge` в соответствии с корневым
`AGENTS.md`. Нехватка данных, спорные статусы и противоречия выносятся на уточнение, а не
заполняются догадками.

## Нормативные справочники форматов

Только для проверки нотации и синтаксиса, не как источники требований проекта:

- [C4 Model diagrams](https://c4model.com/diagrams)
- [OpenAPI Specification](https://spec.openapis.org/oas/)
- [AsyncAPI Specification](https://www.asyncapi.com/docs/reference/specification/v3.0.0)
- [DBML documentation](https://dbml.dbdiagram.io/docs/)
