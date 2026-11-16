---
title: Skills Catalog
description: Каталог навыков AI-агента под артефакты, назначенные ментором по SA-2378.
tags:
  - skills
  - agent
---

# Skills — каталог навыков агента

Состав ограничен назначением ментора: по задаче `SA-2378` нужны **все четыре** типа
артефактов из таблицы выбора, поэтому оставлены только навыки под них. Остальные
навыки из прежнего каталога (процессные и по нотациям, не входящим в назначение)
удалены.

Каждый навык хранится в `skills/<skill-name>/SKILL.md`.

## Как выбирать skill

1. Прочитай корневой `AGENTS.md`.
2. Определи, какой из четырёх артефактов нужен.
3. Открой `SKILL.md` соответствующего навыка.
4. Для артефакта «OpenAPI + Sequence» используй два навыка последовательно:
   `openapi-design`, затем `sequence-diagram`.
5. Не запускай все навыки автоматически. При конфликте приоритет у `AGENTS.md`.

## Каталог

| Skill | Артефакт из SA-2378 | Когда применять | Чем проверяется |
|---|---|---|---|
| [[c4-container-diagram/SKILL\|c4-container-diagram]] | C4, уровень 2 (контейнеры) | Нужна архитектура контейнеров и связей между ними | Рендер в PlantUML C4 или Structurizr, аргументация решений |
| [[openapi-design/SKILL\|openapi-design]] | OpenAPI + Sequence | Синхронные интеграции: REST-контракт | Spectral |
| [[sequence-diagram/SKILL\|sequence-diagram]] | OpenAPI + Sequence | Взаимодействие сервисов во времени, включая ошибки и ретраи | Ревью против `BRD`, `API` |
| [[asyncapi-design/SKILL\|asyncapi-design]] | AsyncAPI | Асинхронные события и каналы (Kafka) | AsyncAPI CLI validate |
| [[erd-data-model/SKILL\|erd-data-model]] | ER + DDL PostgreSQL | Модель данных и физическая схема БД | DDL выполняется в DBeaver без ошибок |

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
