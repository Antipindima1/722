---
title: База знаний — Каршеринг
type: readme
status: draft
product: Каршеринг
updated: 2026-11-16
tags:
  - knowledge/meta
---

# База знаний: каршеринг

Vault для Obsidian. Источник фактов — только артефакты проекта в Confluence
(Vision, BRD, C4, Sequence, OpenAPI/AsyncAPI/ER). Всё, что сформулировано
самостоятельно, помечено как допущение `AS-xx` и вынесено в [[03-assumptions]].

## Что внутри

| Файл | Что содержит |
|---|---|
| [[00-index]] | Карта знаний: точка входа, связи между заметками |
| [[01-glossary]] | Глоссарий: сущности, роли, сервисы, интеграции |
| [[02-business-rules]] | Бизнес-правила: ограничения, обязательные проверки, статусы и переходы |
| [[03-assumptions]] | Допущения: всё, чего нет в артефактах |
| [[04-task-SA-2378]] | Постановка задачи SA-2378: порядок работ, таблица артефактов, Definition of Done |

Сущности: [[booking|Бронирование]], [[trip|Поездка]], [[deposit|Залог]],
[[payment|Платёж]], [[damage-case|Кейс повреждения]], [[car|Автомобиль]],
[[client|Клиент]].

## Как вести

1. **Факт vs допущение.** Утверждение из артефакта — факт, у него в тексте стоит
   ссылка на источник (`BRD 7.3.1 / BR-01`, `API 1.3`, `Vision 5.1`). Всё остальное —
   допущение с номером `AS-xx` и записью в [[03-assumptions]].
2. **Атомарность.** Одна заметка — одна сущность или одно правило.
3. **Связи.** Каждая заметка ссылается на соседние через `[[wikilink]]`, карта в
   [[00-index]] обновляется при добавлении заметки.
4. **Правила нумеруются** и не удаляются: отменённое помечается
   `status: deprecated` и остаётся, потому что на него ссылаются артефакты и `ai-log.md`.
5. **Никаких секретов и ПДн.** Токены, персональные данные, данные с текущей работы
   в базу не попадают.

## Как открыть в Obsidian

`Open folder as vault` → выбрать папку `knowledge`. Плагины ядра (граф, backlinks,
теги, поиск) включены в `.obsidian/`.

## Источники

| Источник | Страница Confluence |
|---|---|
| Vision | [1238695945](https://javacode.atlassian.net/wiki/spaces/SA/pages/1238695945) |
| BRD | [1239842820](https://javacode.atlassian.net/wiki/spaces/SA/pages/1239842820) |
| C4 | [1254490123](https://javacode.atlassian.net/wiki/spaces/SA/pages/1254490123) |
| Декомпозиция v2 | [1278836772](https://javacode.atlassian.net/wiki/spaces/SA/pages/1278836772) |
| Sequence | [1294467116](https://javacode.atlassian.net/wiki/spaces/SA/pages/1294467116) |
| OpenAPI / AsyncAPI / ER | [1327005707](https://javacode.atlassian.net/wiki/spaces/SA/pages/1327005707) |
