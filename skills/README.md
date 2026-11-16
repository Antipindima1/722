---
title: Skills Catalog
description: Каталог специализированных навыков AI-агента проекта и правила их выбора.
tags:
  - skills
  - agent
---

# Skills — каталог навыков агента

Каждый навык хранится отдельно в `skills/<skill-name>/SKILL.md`. Перед работой выбери наиболее узкий подходящий skill; при необходимости используй несколько навыков последовательно.

## Как выбирать skill

1. Прочитай корневой `AGENTS.md`.
2. Определи тип задачи и требуемый артефакт.
3. Открой `SKILL.md` соответствующего навыка.
4. Если задача затрагивает несколько артефактов, используй основной skill и необходимые смежные skills.
5. Не запускай все skills автоматически — применяй только нужные.
6. При конфликте инструкции корневого `AGENTS.md` имеет приоритет.

## Каталог

| Skill | Когда применять | Результат |
|---|---|---|
| [[jira-story-delivery/SKILL|jira-story-delivery]] | Выполнение Jira Story/Bug/Task от анализа до проверки PR | Изменения и отчёт по Story |
| [[requirements-analysis/SKILL|requirements-analysis]] | Сбор, анализ, декомпозиция и трассируемость требований | Реестр требований и вопросов |
| [[vision-document/SKILL|vision-document]] | Определение продуктового видения и границ | Vision document |
| [[brd-document/SKILL|brd-document]] | Формализация бизнес-требований | BRD |
| [[business-rules-modeling/SKILL|business-rules-modeling]] | Реестр бизнес-правил и таблицы решений | Business rules catalogue / decision table |
| [[bpmn-process-diagram/SKILL|bpmn-process-diagram]] | Сквозные бизнес-процессы и взаимодействие участников | BPMN 2.0 diagram |
| [[use-case-diagram/SKILL|use-case-diagram]] | Акторы, граница системы и пользовательские цели | UML Use Case Diagram |
| [[activity-diagram/SKILL|activity-diagram]] | Потоки действий, условия и параллельные ветви | UML Activity Diagram |
| [[sequence-diagram/SKILL|sequence-diagram]] | Взаимодействия участников/сервисов во времени | UML Sequence Diagram |
| [[state-machine-diagram/SKILL|state-machine-diagram]] | Жизненный цикл одной сущности | UML State Machine Diagram |
| [[c4-context-diagram/SKILL|c4-context-diagram]] | Архитектура на уровне системы и внешнего контекста | C4 L1 System Context |
| [[c4-container-diagram/SKILL|c4-container-diagram]] | Приложения, сервисы и хранилища внутри системы | C4 L2 Container |
| [[c4-component-diagram/SKILL|c4-component-diagram]] | Внутренние компоненты одного контейнера | C4 L3 Component |
| [[c4-code-diagram/SKILL|c4-code-diagram]] | Точечная детализация кода выбранного компонента | C4 L4 Code/Class Diagram |
| [[openapi-design/SKILL|openapi-design]] | Синхронный HTTP API | OpenAPI YAML/JSON |
| [[asyncapi-design/SKILL|asyncapi-design]] | События, сообщения и каналы | AsyncAPI YAML/JSON |
| [[erd-data-model/SKILL|erd-data-model]] | Сущности, связи и физическая модель БД | ERD / DBML |
| [[architecture-consistency-review/SKILL|architecture-consistency-review]] | Сверка нескольких архитектурных артефактов | Отчёт о согласованности |

## Типовые сочетания навыков

| Цель | Навыки |
|---|---|
| Разобрать новую бизнес-инициативу | `requirements-analysis` → `vision-document` → `brd-document` |
| Описать бизнес-процесс | `requirements-analysis` → `bpmn-process-diagram` → `business-rules-modeling` |
| Описать пользовательские функции | `requirements-analysis` → `use-case-diagram` → `activity-diagram` |
| Спроектировать архитектуру | `c4-context-diagram` → `c4-container-diagram` → при необходимости `c4-component-diagram` / `c4-code-diagram` |
| Описать интеграционный сценарий | `sequence-diagram` + `openapi-design` и/или `asyncapi-design` |
| Спроектировать данные | `erd-data-model` + `business-rules-modeling` |
| Проверить изменение по Story | `jira-story-delivery` + профильные skills + `architecture-consistency-review` |

## Важные разграничения

- C4 L1–L4 — уровни детализации архитектуры. L4 (Code) не обязателен и создаётся только при реальной пользе.
- C4 — не нотация бизнес-процессов, состояний или ER-моделирования. Для них применяй BPMN/UML/ERD skills.
- BPMN и UML Activity Diagram не взаимозаменяемы: выбирай BPMN для бизнес-процессов с участниками/пулами и потоками сообщений, Activity — для потока действий/логики.
- Sequence Diagram показывает взаимодействия во времени; State Machine Diagram — состояния одной сущности.
- OpenAPI описывает HTTP API; AsyncAPI — message-driven API. Не объединяй их в один контракт.
- BRD и Vision — разные документы: Vision фиксирует направление и ценность, BRD — конкретные бизнес-требования и границы.

## Общий принцип

Все проектные факты берутся только из Jira и `knowledge` в соответствии с корневым `AGENTS.md`. Нехватка данных, спорные статусы и противоречия должны быть вынесены на уточнение, а не заполнены догадками.

## Нормативные справочники форматов

Эти ссылки нужны только для проверки нотации и синтаксиса, не как источники требований проекта:

- [C4 Model diagrams](https://c4model.com/diagrams)
- [OpenAPI Specification](https://spec.openapis.org/oas/)
- [AsyncAPI Specification](https://www.asyncapi.com/docs/reference/specification/v3.0.0)
- [BPMN 2.0.2 (OMG)](https://www.omg.org/spec/BPMN/2.0.2)
- [UML 2.5.1 (OMG)](https://www.omg.org/spec/UML)
- [DBML documentation](https://dbml.dbdiagram.io/docs/)
