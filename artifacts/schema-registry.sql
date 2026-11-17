-- ВыплатыПро: модель данных контура реестра и выплат (Ф1 + задел под Ф2)
-- PostgreSQL 15+
-- Проверка: исполнение на PGlite (WASM PostgreSQL), см. artifacts/postgres-validate.txt

CREATE TYPE registry_status AS ENUM (
    'UPLOADED',
    'VALIDATING',
    'CHECKED',
    'BLOCKED',
    'VALIDATION_FAILED',
    'REJECTED',
    'CANCELLED'
);

CREATE TYPE row_status AS ENUM ('NEW', 'VALIDATED', 'REJECTED');

CREATE TYPE reject_reason AS ENUM (
    'INVALID_INN',
    'DUPLICATE_INN',
    'AMOUNT_OUT_OF_RANGE',
    'INVALID_PHONE',
    'ALREADY_PAID',
    'MISSING_REQUIRED_FIELD'
);

CREATE TYPE payout_status AS ENUM ('CREATED', 'SENT', 'EXECUTED', 'DECLINED');

CREATE TYPE receipt_status AS ENUM ('PENDING', 'RECEIVED', 'MISSING', 'CANCELLED');

-- Компания-заказчик: владелец реестров и плательщик
CREATE TABLE companies (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text        NOT NULL CHECK (length(btrim(name)) > 0),
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Исполнитель-самозанятый
CREATE TABLE contractors (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inn                  char(12) NOT NULL UNIQUE CHECK (inn ~ '^[0-9]{12}$'),
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
    total_amount    numeric(14, 2)  NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
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

-- Строка реестра: одна выплата одному исполнителю
CREATE TABLE payout_rows (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid          NOT NULL REFERENCES registries (id) ON DELETE CASCADE,
    contractor_id uuid          REFERENCES contractors (id) ON DELETE SET NULL,
    full_name     text          NOT NULL CHECK (length(btrim(full_name)) > 0),
    inn           char(12)      NOT NULL CHECK (inn ~ '^[0-9]{12}$'),
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

-- Выплата по строке реестра
CREATE TABLE payouts (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registry_id   uuid            NOT NULL REFERENCES registries (id) ON DELETE RESTRICT,
    row_id        uuid            NOT NULL UNIQUE REFERENCES payout_rows (id) ON DELETE RESTRICT,
    contractor_id uuid            REFERENCES contractors (id) ON DELETE SET NULL,
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0 AND amount <= 1000000),
    status        payout_status   NOT NULL DEFAULT 'CREATED',
    sbp_ref       text,
    attempts      integer         NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 3),
    created_at    timestamptz     NOT NULL DEFAULT now(),
    updated_at    timestamptz     NOT NULL DEFAULT now()
);

CREATE INDEX payouts_status_idx ON payouts (status);

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

COMMENT ON TABLE registries IS 'Реестр выплат: пакет строк, загруженный бухгалтером (knowledge/entities/registry.md)';
COMMENT ON COLUMN registries.idempotency_key IS 'Ключ идемпотентности загрузки, AS-13';
COMMENT ON COLUMN registries.row_count IS 'Не более 5000 строк в реестре, AS-02';
COMMENT ON COLUMN registries.error_share IS 'Доля отклонённых строк; выше порога реестр блокируется, AS-14';
COMMENT ON COLUMN payout_rows.reject_reason IS 'Причина отклонения строки, CHK-03…CHK-07';
COMMENT ON COLUMN payouts.row_id IS 'Одна выплата на строку реестра: защита от повторов, CHK-07, AS-13';
COMMENT ON COLUMN payouts.attempts IS 'Не более 3 попыток отправки в СБП, AS-17';
COMMENT ON TABLE receipts IS 'Чек ФНС обязателен по каждой выплате, O-05, AS-07';
