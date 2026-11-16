# Каршеринг — база знаний и артефакты

Учебный проект системного аналитика: система краткосрочной аренды автомобилей.
Здесь живут база знаний, правила работы ИИ-агента и навыки, по которым агент готовит
артефакты. Проектные факты берутся только из Jira и `knowledge/`.

## Структура

| Путь | Что внутри |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Правила поведения ИИ-агента: источники, формат ответов, маршрутизация по навыкам |
| [`knowledge/`](knowledge/) | Vault Obsidian: глоссарий, бизнес-правила, допущения, сущности |
| [`knowledge/00-index.md`](knowledge/00-index.md) | Карта знаний — точка входа |
| [`knowledge/01-glossary.md`](knowledge/01-glossary.md) | Глоссарий |
| [`knowledge/02-business-rules.md`](knowledge/02-business-rules.md) | Ограничения, обязательные проверки, статусы и переходы |
| [`knowledge/03-assumptions.md`](knowledge/03-assumptions.md) | Допущения `AS-xx` |
| [`knowledge/04-task-SA-2378.md`](knowledge/04-task-SA-2378.md) | Постановка задачи, таблица артефактов, Definition of Done |
| [`skills/`](skills/) | Навыки агента: C4 L2, OpenAPI + Sequence, AsyncAPI, ER + DDL и «Смотрящий» |
| [`skills/README.md`](skills/README.md) | Каталог навыков и правила выбора |

Появятся при выполнении `SA-2378`: `artifacts/` (артефакты и отчёты проверки
`<артефакт>-check.md`, `<артефакт>-review.md`) и `ai-log.md` (журнал ошибок агента).

## Навыки

| Навык | Артефакт | Проверка |
|---|---|---|
| `c4-container-diagram` | C4, уровень 2 | PlantUML C4 / Structurizr |
| `openapi-design` + `sequence-diagram` | OpenAPI + Sequence | Spectral |
| `asyncapi-design` | AsyncAPI | AsyncAPI CLI validate |
| `erd-data-model` | ER + DDL PostgreSQL | DDL в DBeaver |
| `smotryashchiy` | Проверка результата | Отчёт с обоснованными замечаниями |

## Как открыть

1. Склонировать репозиторий.
2. В Obsidian: `Open folder as vault` → папка `knowledge`.
3. Настройки Obsidian (`.obsidian/`) уже в репозитории: включены граф, backlinks, теги,
   поиск, шаблоны.

## Правила ведения

- **Факт** — утверждение из артефакта проекта со ссылкой на источник (`BRD 7.3.1 / BR-01`,
  `Vision 5.1`, `API 1.3`, `C4`) или на ключ Jira.
- **Допущение** — всё, чего в артефактах нет; нумеруется `AS-xx` и живёт в
  `knowledge/03-assumptions.md` с причиной и областью применения.
- Секретов, персональных данных и материалов с текущей работы в репозитории нет.

## Источники

Vision, BRD, C4, декомпозиция, sequence-диаграммы и OpenAPI/AsyncAPI/ER-диаграмма —
в Confluence проекта (пространство `SA`), задача Jira `SA-2378`.
