-- ВыплатыПро: вариант DDL для онлайн-площадок (RunSQL, dbfiddle и подобные)
-- Отличия от artifacts/schema-registry.sql:
--   * нет CREATE TYPE — статусы хранятся как text с CHECK (... IN (...));
--   * нет CREATE FUNCTION — проверка контрольной суммы ИНН остаётся в полной версии.
-- Модель, ключи, индексы и остальные ограничения совпадают с полной версией.

CREATE TABLE companies (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text        NOT NULL CHECK (length(btrim(name)) > 0),
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE contractors (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inn                  varchar(12) NOT NULL UNIQUE CHECK (inn ~ '^[0-9]{12}$'),
    full_name            text        NOT NULL CHECK (length(btrim(full_name)) > 0),
    phone                text        NOT NULL CHECK (phone ~ '^7[0-9]{10}$'),
    self_employed_status text        NOT NULL DEFAULT 'UNKNOWN'
                                     CHECK (self_employed_status IN ('ACTIVE', 'LOST', 'UNKNOWN')),
    status_checked_at    timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE registries (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid           NOT NULL REFERENCES companies (id) ON DELETE RESTRICT,
    status          text           NOT NULL DEFAULT 'UPLOADED'
                                  CHECK (status IN ('UPLOADED','VALIDATING','CHECKED','BLOCKED','VALIDATION_FAILED','REJECTED','CANCELLED')),
    file_name       text           NOT NULL,
    object_key      text           NOT NULL,
    row_count       integer        NOT NULL DEFAULT 0 CHECK (row_count >= 0 AND row_count <= 5000),
    total_amount    numeric(14, 2) NOT NULL DEFAULT 0
                                  CHECK (total_amount >= 0 AND total_amount <= 10000000),
    accepted_count  integer        NOT NULL DEFAULT 0 CHECK (accepted_count >= 0),
    rejected_count  integer        NOT NULL DEFAULT 0 CHECK (rejected_count >= 0),
    error_share     numeric(5, 4)  CHECK (error_share >= 0 AND error_share <= 1),
    idempotency_key text           NOT NULL UNIQUE,
    created_at      timestamptz    NOT NULL DEFAULT now(),
    updated_at      timestamptz    NOT NULL DEFAULT now(),
    CHECK (accepted_count + rejected_count <= row_count)
);

CREATE INDEX registries_company_status_idx ON registries (company_id, status);
CREATE INDEX registries_updated_idx ON registries (updated_at DESC);

CREATE TABLE validation_reports (
    registry_id    uuid PRIMARY KEY REFERENCES registries (id) ON DELETE CASCADE,
    row_count      integer       NOT NULL CHECK (row_count >= 0),
    accepted_count integer       NOT NULL CHECK (accepted_count >= 0),
    rejected_count integer       NOT NULL CHECK (rejected_count >= 0),
    error_share    numeric(5, 4) NOT NULL CHECK (error_share >= 0 AND error_share <= 1),
    reasons        jsonb         NOT NULL DEFAULT '{}'::jsonb,
    generated_at   timestamptz   NOT NULL DEFAULT now()
);

CREATE TABLE payout_rows (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid           NOT NULL REFERENCES registries (id) ON DELETE CASCADE,
    full_name     text           NOT NULL CHECK (length(btrim(full_name)) > 0),
    inn           varchar(12)    NOT NULL CHECK (inn ~ '^[0-9]{12}$'),
    phone         text           NOT NULL CHECK (phone ~ '^7[0-9]{10}$'),
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    purpose       text           NOT NULL CHECK (length(btrim(purpose)) > 0),
    status        text           NOT NULL DEFAULT 'NEW'
                                 CHECK (status IN ('NEW','VALIDATED','REJECTED')),
    reject_reason text           CHECK (reject_reason IN ('INVALID_INN','DUPLICATE_INN','AMOUNT_OUT_OF_RANGE','INVALID_PHONE','ALREADY_PAID','MISSING_REQUIRED_FIELD')),
    created_at    timestamptz    NOT NULL DEFAULT now(),
    CHECK ((status = 'REJECTED' AND reject_reason IS NOT NULL)
        OR (status <> 'REJECTED' AND reject_reason IS NULL))
);

CREATE INDEX payout_rows_registry_status_idx ON payout_rows (registry_id, status);
CREATE INDEX payout_rows_inn_idx ON payout_rows (inn);
CREATE UNIQUE INDEX payout_rows_registry_inn_validated_uq
    ON payout_rows (registry_id, inn)
    WHERE status = 'VALIDATED';

CREATE TABLE payouts (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid           NOT NULL REFERENCES registries (id) ON DELETE RESTRICT,
    row_id        uuid           NOT NULL UNIQUE REFERENCES payout_rows (id) ON DELETE RESTRICT,
    contractor_id uuid           NOT NULL REFERENCES contractors (id) ON DELETE RESTRICT,
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    status        text           NOT NULL DEFAULT 'CREATED'
                                 CHECK (status IN ('CREATED','SENT','EXECUTED','DECLINED')),
    sbp_ref       text,
    attempts      integer        NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 3),
    created_at    timestamptz    NOT NULL DEFAULT now(),
    updated_at    timestamptz    NOT NULL DEFAULT now()
);

CREATE INDEX payouts_status_idx ON payouts (status);
CREATE INDEX payouts_registry_idx ON payouts (registry_id);

CREATE TABLE receipts (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_id   uuid        NOT NULL UNIQUE REFERENCES payouts (id) ON DELETE CASCADE,
    status      text        NOT NULL DEFAULT 'PENDING'
                            CHECK (status IN ('PENDING','RECEIVED','MISSING','CANCELLED')),
    received_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CHECK (status <> 'RECEIVED' OR received_at IS NOT NULL)
);

CREATE INDEX receipts_status_idx ON receipts (status);

CREATE TABLE processed_events (
    event_id     uuid PRIMARY KEY,
    consumer     text        NOT NULL CHECK (length(btrim(consumer)) > 0),
    processed_at timestamptz NOT NULL DEFAULT now()
);
