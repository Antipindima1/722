-- ВыплатыПро: DDL, сгенерированный заново по навыку erd-data-model после правки E-08
-- Источники: SCRUM-2189, SCRUM-2190, knowledge/02-business-rules.md, knowledge/03-assumptions.md
-- Правило навыка E-08: каждый лимит и каждая проверка из критериев приёмки отражены в схеме
-- либо вынесены в допущения.

-- ---------- проверка ИНН: контрольная сумма (E-08, AS-09) ----------
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

-- ---------- статусы: полный жизненный цикл (§4.1–4.4) ----------
CREATE TYPE registry_status AS ENUM (
    'UPLOADED', 'VALIDATING', 'CHECKED', 'BLOCKED', 'VALIDATION_FAILED',
    'REJECTED', 'CANCELLED', 'PAYING', 'DONE', 'DONE_WITH_ERRORS'
);

CREATE TYPE row_status AS ENUM ('NEW', 'VALIDATED', 'REJECTED', 'PAYING', 'PAID', 'FAILED');

CREATE TYPE reject_reason AS ENUM (
    'INVALID_INN', 'DUPLICATE_INN', 'AMOUNT_OUT_OF_RANGE',
    'INVALID_PHONE', 'ALREADY_PAID', 'MISSING_REQUIRED_FIELD'
);

CREATE TYPE payout_status AS ENUM ('CREATED', 'SENT_TO_SBP', 'EXECUTED', 'DECLINED');

CREATE TYPE receipt_status AS ENUM ('PENDING', 'RECEIVED', 'MISSING', 'CANCELLED');

-- ---------- компании и исполнители ----------
CREATE TABLE companies (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL CHECK (btrim(name) <> ''),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE contractors (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inn                  varchar(12) NOT NULL UNIQUE
                                      CHECK (inn_is_valid(inn)),
    full_name            text NOT NULL CHECK (btrim(full_name) <> ''),
    phone                text NOT NULL CHECK (phone ~ '^7[0-9]{10}$'),
    self_employed_status text NOT NULL DEFAULT 'UNKNOWN'
                                      CHECK (self_employed_status IN ('ACTIVE', 'LOST', 'UNKNOWN')),
    status_checked_at    timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now()
);

-- ---------- реестр: лимиты строк и суммы (E-08, AS-02) ----------
CREATE TABLE registries (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid NOT NULL REFERENCES companies (id) ON DELETE RESTRICT,
    status          registry_status NOT NULL DEFAULT 'UPLOADED',
    file_name       text NOT NULL CHECK (btrim(file_name) <> ''),
    object_key      text NOT NULL CHECK (btrim(object_key) <> ''),
    row_count       integer NOT NULL DEFAULT 0
                            CHECK (row_count BETWEEN 0 AND 5000),
    total_amount    numeric(14, 2) NOT NULL DEFAULT 0
                            CHECK (total_amount >= 0 AND total_amount <= 10000000),
    accepted_count  integer NOT NULL DEFAULT 0 CHECK (accepted_count >= 0),
    rejected_count  integer NOT NULL DEFAULT 0 CHECK (rejected_count >= 0),
    error_share     numeric(5, 4) CHECK (error_share >= 0 AND error_share <= 1),
    idempotency_key text NOT NULL UNIQUE CHECK (btrim(idempotency_key) <> ''),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CHECK (accepted_count + rejected_count <= row_count)
);

CREATE INDEX registries_company_status_idx ON registries (company_id, status);
CREATE INDEX registries_updated_idx ON registries (updated_at DESC);

-- ---------- отчёт о проверке сохраняется вместе с реестром (SCRUM-2190) ----------
CREATE TABLE validation_reports (
    registry_id    uuid PRIMARY KEY REFERENCES registries (id) ON DELETE CASCADE,
    row_count      integer NOT NULL CHECK (row_count >= 0),
    accepted_count integer NOT NULL CHECK (accepted_count >= 0),
    rejected_count integer NOT NULL CHECK (rejected_count >= 0),
    error_share    numeric(5, 4) NOT NULL CHECK (error_share BETWEEN 0 AND 1),
    reasons        jsonb NOT NULL DEFAULT '{}'::jsonb,
    generated_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------- строки реестра ----------
CREATE TABLE payout_rows (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid NOT NULL REFERENCES registries (id) ON DELETE CASCADE,
    full_name     text NOT NULL CHECK (btrim(full_name) <> ''),
    inn           varchar(12) NOT NULL CHECK (inn_is_valid(inn)),
    phone         text NOT NULL CHECK (phone ~ '^7[0-9]{10}$'),
    amount        numeric(14, 2) NOT NULL
                                 CHECK (amount > 0 AND amount <= 1000000),
    purpose       text NOT NULL CHECK (btrim(purpose) <> ''),
    status        row_status NOT NULL DEFAULT 'NEW',
    reject_reason reject_reason,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CHECK ((status = 'REJECTED' AND reject_reason IS NOT NULL)
        OR (status <> 'REJECTED' AND reject_reason IS NULL))
);

CREATE INDEX payout_rows_registry_status_idx ON payout_rows (registry_id, status);
CREATE INDEX payout_rows_inn_idx ON payout_rows (inn);
CREATE UNIQUE INDEX payout_rows_validated_inn_uq
    ON payout_rows (registry_id, inn) WHERE status = 'VALIDATED';

-- ---------- выплаты ----------
CREATE TABLE payouts (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid NOT NULL REFERENCES registries (id) ON DELETE RESTRICT,
    row_id        uuid NOT NULL UNIQUE REFERENCES payout_rows (id) ON DELETE RESTRICT,
    contractor_id uuid NOT NULL REFERENCES contractors (id) ON DELETE RESTRICT,
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    status        payout_status NOT NULL DEFAULT 'CREATED',
    sbp_ref       text,
    attempts      integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX payouts_status_idx ON payouts (status);
CREATE INDEX payouts_registry_idx ON payouts (registry_id);

-- ---------- чеки ----------
CREATE TABLE receipts (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_id   uuid NOT NULL UNIQUE REFERENCES payouts (id) ON DELETE CASCADE,
    status      receipt_status NOT NULL DEFAULT 'PENDING',
    received_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CHECK (status <> 'RECEIVED' OR received_at IS NOT NULL)
);

CREATE INDEX receipts_status_idx ON receipts (status);

-- ---------- идемпотентность входящих событий (AS-13, AS-20) ----------
CREATE TABLE processed_events (
    event_id     uuid PRIMARY KEY,
    consumer     text NOT NULL CHECK (btrim(consumer) <> ''),
    processed_at timestamptz NOT NULL DEFAULT now()
);
