-- ВыплатыПро: модель данных контура реестра и выплат (Ф1 + задел под Ф2)
-- PostgreSQL 15+
-- Проверка: исполнение на PGlite (WASM PostgreSQL), см. artifacts/f1-registry/postgres-validate.txt
-- Скрипт НЕ идемпотентный: рассчитан на пустую базу. Для повторного применения сначала
-- выполните artifacts/f1-registry/schema-reset.sql (удаляет таблицы и типы контура).

CREATE TYPE registry_status AS ENUM (
    'UPLOADED',          -- Загружен
    'VALIDATING',        -- Проверяется
    'CHECKED',           -- Проверен
    'BLOCKED',           -- Заблокирован (доля ошибок выше порога)
    'VALIDATION_FAILED', -- Ошибка проверки (техническая причина)
    'REJECTED',          -- Отклонён
    'CANCELLED',         -- Отменён
    'PAYING',            -- В выплате
    'DONE',              -- Завершён
    'DONE_WITH_ERRORS'   -- Завершён с ошибками
);

CREATE TYPE row_status AS ENUM (
    'NEW',        -- Новая
    'VALIDATED',  -- Проверена
    'REJECTED',   -- Отклонена
    'PAYING',     -- В выплате
    'PAID',       -- Выплачена
    'FAILED'      -- Ошибка
);

CREATE TYPE reject_reason AS ENUM (
    'INVALID_INN',
    'DUPLICATE_INN',
    'AMOUNT_OUT_OF_RANGE',
    'INVALID_PHONE',
    'MISSING_REQUIRED_FIELD'
);

CREATE TYPE payout_status AS ENUM (
    'CREATED',      -- Создана
    'SENT_TO_SBP',  -- Отправлена в СБП
    'EXECUTED',     -- Исполнена
    'DECLINED'      -- Отклонена
);

CREATE TYPE receipt_status AS ENUM ('PENDING', 'RECEIVED', 'MISSING', 'CANCELLED');

-- Контрольная сумма ИНН из 12 цифр (AS-09)
-- Реализовано одним SQL-выражением без PL/pgSQL: такие функции переносятся
-- онлайн-редакторами и простыми миграторами, которые режут скрипт по точке с запятой.
CREATE OR REPLACE FUNCTION inn_is_valid(inn text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS '
SELECT CASE WHEN inn !~ ''^[0-9]{12}$'' THEN false ELSE
    ((substr(inn,1,1)::int*7 + substr(inn,2,1)::int*2 + substr(inn,3,1)::int*4
    + substr(inn,4,1)::int*10 + substr(inn,5,1)::int*3 + substr(inn,6,1)::int*5
    + substr(inn,7,1)::int*9 + substr(inn,8,1)::int*4 + substr(inn,9,1)::int*6
    + substr(inn,10,1)::int*8) % 11) % 10 = substr(inn,11,1)::int
  AND
    ((substr(inn,1,1)::int*3 + substr(inn,2,1)::int*7 + substr(inn,3,1)::int*2
    + substr(inn,4,1)::int*4 + substr(inn,5,1)::int*10 + substr(inn,6,1)::int*3
    + substr(inn,7,1)::int*5 + substr(inn,8,1)::int*9 + substr(inn,9,1)::int*4
    + substr(inn,10,1)::int*6 + substr(inn,11,1)::int*8) % 11) % 10 = substr(inn,12,1)::int
END';

-- Компания-заказчик: владелец реестров и плательщик
CREATE TABLE companies (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text        NOT NULL CHECK (length(btrim(name)) > 0),
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Исполнитель-самозанятый
CREATE TABLE contractors (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inn                  char(12) NOT NULL UNIQUE
                                  CHECK (inn::text ~ '^[0-9]{12}$' AND inn_is_valid(inn::text)),
    full_name            text     NOT NULL CHECK (length(btrim(full_name)) > 0),
    phone                text     NOT NULL CHECK (phone ~ '^7[0-9]{10}$'),
    self_employed_status text     NOT NULL DEFAULT 'UNKNOWN'
                                  CHECK (self_employed_status IN ('ACTIVE', 'LOST', 'UNKNOWN')),
    status_checked_at    timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now()
);

-- Реестр выплат
CREATE TABLE registries (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid            NOT NULL REFERENCES companies (id) ON DELETE RESTRICT,
    status          registry_status NOT NULL DEFAULT 'UPLOADED',
    file_name       text            NOT NULL,
    object_key      text            NOT NULL,
    row_count       integer         NOT NULL DEFAULT 0 CHECK (row_count >= 0 AND row_count <= 5000),
    total_amount    numeric(14, 2)  NOT NULL DEFAULT 0
                                  CHECK (total_amount >= 0 AND total_amount <= 10000000),
    accepted_count  integer         NOT NULL DEFAULT 0 CHECK (accepted_count >= 0),
    rejected_count  integer         NOT NULL DEFAULT 0 CHECK (rejected_count >= 0),
    error_share     numeric(5, 4)   CHECK (error_share >= 0 AND error_share <= 1),
    idempotency_key text            NOT NULL UNIQUE,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    updated_at      timestamptz     NOT NULL DEFAULT now(),
    CHECK (accepted_count + rejected_count <= row_count)
);

CREATE INDEX registries_company_status_idx ON registries (company_id, status);
CREATE INDEX registries_updated_idx ON registries (updated_at DESC);


-- Отчёт о проверке реестра: сохраняется вместе с реестром (SCRUM-2190)
CREATE TABLE validation_reports (
    registry_id   uuid PRIMARY KEY REFERENCES registries (id) ON DELETE CASCADE,
    row_count     integer        NOT NULL CHECK (row_count >= 0),
    accepted_count integer       NOT NULL CHECK (accepted_count >= 0),
    rejected_count integer       NOT NULL CHECK (rejected_count >= 0),
    error_share   numeric(5, 4)  NOT NULL CHECK (error_share >= 0 AND error_share <= 1),
    reasons       jsonb          NOT NULL DEFAULT '{}'::jsonb,
    generated_at  timestamptz    NOT NULL DEFAULT now()
);

COMMENT ON TABLE validation_reports IS 'Сохранённый отчёт о проверке реестра, SCRUM-2190';

-- Строка реестра: одна выплата одному исполнителю
CREATE TABLE payout_rows (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid          NOT NULL REFERENCES registries (id) ON DELETE CASCADE,
    full_name     text          NOT NULL CHECK (length(btrim(full_name)) > 0),
    inn           char(12)      NOT NULL
                                  CHECK (inn::text ~ '^[0-9]{12}$' AND inn_is_valid(inn::text)),
    phone         text          NOT NULL CHECK (phone ~ '^7[0-9]{10}$'),
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    purpose       text          NOT NULL CHECK (length(btrim(purpose)) > 0),
    status        row_status    NOT NULL DEFAULT 'NEW',
    reject_reason reject_reason,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    CHECK (
        (status = 'REJECTED' AND reject_reason IS NOT NULL)
        OR (status <> 'REJECTED' AND reject_reason IS NULL)
    )
);

CREATE INDEX payout_rows_registry_status_idx ON payout_rows (registry_id, status);
CREATE INDEX payout_rows_inn_idx ON payout_rows (inn);
-- O-08: в одном реестре не может быть двух принятых строк с одним ИНН
CREATE UNIQUE INDEX payout_rows_registry_inn_validated_uq
    ON payout_rows (registry_id, inn)
    WHERE status = 'VALIDATED';

-- Выплата по строке реестра
CREATE TABLE payouts (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid            NOT NULL REFERENCES registries (id) ON DELETE RESTRICT,
    row_id        uuid            NOT NULL UNIQUE REFERENCES payout_rows (id) ON DELETE RESTRICT,
    contractor_id uuid            NOT NULL REFERENCES contractors (id) ON DELETE RESTRICT,
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    status        payout_status   NOT NULL DEFAULT 'CREATED',
    sbp_ref       text,
    attempts      integer         NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 3),
    created_at    timestamptz     NOT NULL DEFAULT now(),
    updated_at    timestamptz     NOT NULL DEFAULT now()
);

CREATE INDEX payouts_status_idx ON payouts (status);
CREATE INDEX payouts_registry_idx ON payouts (registry_id);

-- Чек ФНС по выплате
CREATE TABLE receipts (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_id   uuid           NOT NULL UNIQUE REFERENCES payouts (id) ON DELETE CASCADE,
    status      receipt_status NOT NULL DEFAULT 'PENDING',
    received_at timestamptz,
    created_at  timestamptz    NOT NULL DEFAULT now(),
    CHECK (status <> 'RECEIVED' OR received_at IS NOT NULL)
);

CREATE INDEX receipts_status_idx ON receipts (status);

-- Идемпотентность входящих событий: AS-13, eventId из AsyncAPI
CREATE TABLE processed_events (
    event_id     uuid PRIMARY KEY,
    consumer     text        NOT NULL CHECK (length(btrim(consumer)) > 0),
    processed_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE processed_events IS 'Обработанные события: защита от повторной обработки по eventId, AS-13';
COMMENT ON TABLE registries IS 'Реестр выплат: пакет строк, загруженный бухгалтером (knowledge/entities/registry.md)';
COMMENT ON COLUMN registries.idempotency_key IS 'Ключ идемпотентности загрузки, AS-13';
COMMENT ON COLUMN registries.row_count IS 'Не более 5000 строк в реестре, AS-02';
COMMENT ON COLUMN registries.error_share IS 'Доля отклонённых строк; выше порога реестр блокируется, AS-14';
COMMENT ON COLUMN payout_rows.reject_reason IS 'Причина отклонения строки, CHK-03…CHK-07';
COMMENT ON COLUMN payouts.row_id IS 'Одна выплата на строку реестра: защита от повторов, CHK-07, AS-13';
COMMENT ON COLUMN payouts.attempts IS 'Не более 3 попыток отправки в СБП, AS-17';
COMMENT ON TABLE receipts IS 'Чек ФНС обязателен по каждой выплате, O-05, AS-07';
