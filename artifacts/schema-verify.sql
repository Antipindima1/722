-- ВыплатыПро: самопроверка схемы после применения DDL
-- Запускать в DBeaver целиком через Alt+X (Execute SQL Script).
-- В конце откатывает транзакцию: тестовые данные в базе не остаются.
-- Ожидаемый итог: в колонке passed везде true.

BEGIN;

-- тестовые данные
INSERT INTO companies (id, name)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Проверка схемы');

INSERT INTO registries (id, company_id, file_name, object_key, idempotency_key, row_count, total_amount)
VALUES ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
        'check.csv', 's3/check.csv', 'check-key-1', 2, 1500.00);

INSERT INTO contractors (id, inn, full_name, phone)
VALUES ('aaaaaaaa-0000-0000-0000-000000000003', '123456789047', 'Иванов И.И.', '79991234567');

INSERT INTO payout_rows (id, registry_id, full_name, inn, phone, amount, purpose, status, reject_reason)
VALUES ('aaaaaaaa-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000002',
        'Иванов И.И.', '123456789047', '79991234567', 1000.00, 'Курьерские услуги', 'VALIDATED', NULL);

CREATE TEMP TABLE verify_results (
    num      serial,
    check_name text,
    expected   text,
    passed     boolean
) ON COMMIT DROP;

DO $$
DECLARE
    v_registry uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
    v_row      uuid := 'aaaaaaaa-0000-0000-0000-000000000004';
    v_contractor uuid := 'aaaaaaaa-0000-0000-0000-000000000003';
BEGIN
    BEGIN
        INSERT INTO payout_rows (registry_id, full_name, inn, phone, amount, purpose)
        VALUES (v_registry, 'Петров П.П.', '123456789047', '79991234568', 0, 'Тест');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('сумма строки > 0', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('сумма строки > 0', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO payout_rows (registry_id, full_name, inn, phone, amount, purpose)
        VALUES (v_registry, 'Сидоров С.С.', '123456789012', '79991234569', 10, 'Тест');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('контрольная сумма ИНН', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('контрольная сумма ИНН', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO registries (company_id, file_name, object_key, idempotency_key)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'r2.csv', 's3/r2.csv', 'check-key-1');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('уникальность ключа идемпотентности', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('уникальность ключа идемпотентности', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO registries (company_id, file_name, object_key, idempotency_key, row_count, total_amount)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'r4.csv', 's3/r4.csv', 'check-key-4', 1, 10000001);
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('лимит суммы реестра 10 млн', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('лимит суммы реестра 10 млн', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO registries (company_id, file_name, object_key, idempotency_key, row_count)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'r3.csv', 's3/r3.csv', 'check-key-3', 5001);
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('лимит 5000 строк', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('лимит 5000 строк', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO payout_rows (registry_id, full_name, inn, phone, amount, purpose, status)
        VALUES (v_registry, 'Сидоров С.С.', '123456789047', '79991234569', 10, 'Тест', 'REJECTED');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('отклонённая строка без причины', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('отклонённая строка без причины', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO payouts (registry_id, row_id, contractor_id, amount, attempts)
        VALUES (v_registry, v_row, v_contractor, 1000.00, 4);
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('не более 3 попыток', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('не более 3 попыток', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO payouts (id, registry_id, row_id, contractor_id, amount)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000005', v_registry, v_row, v_contractor, 1000.00);
        INSERT INTO receipts (payout_id, status)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000005', 'RECEIVED');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('чек получен без даты', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('чек получен без даты', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO payout_rows (id, registry_id, full_name, inn, phone, amount, purpose, status)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000006', v_registry,
                'Иванов И.И. (дубль)', '123456789047', '79991234567', 500.00, 'Тест', 'VALIDATED');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('дубль ИНН среди принятых строк', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('дубль ИНН среди принятых строк', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO processed_events (event_id, consumer)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000007', 'worker');
        INSERT INTO processed_events (event_id, consumer)
        VALUES ('aaaaaaaa-0000-0000-0000-000000000007', 'worker');
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('повторная обработка eventId', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('повторная обработка eventId', 'ошибка', true);
    END;

    BEGIN
        INSERT INTO validation_reports (registry_id, row_count, accepted_count, rejected_count, error_share)
        VALUES (v_registry, 2, 1, 1, 0.5);
        INSERT INTO validation_reports (registry_id, row_count, accepted_count, rejected_count, error_share)
        VALUES (v_registry, 2, 2, 0, 0.0);
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('второй отчёт по реестру', 'ошибка', false);
    EXCEPTION WHEN others THEN
        INSERT INTO verify_results (check_name, expected, passed) VALUES ('второй отчёт по реестру', 'ошибка', true);
    END;
END $$;

-- 1. Структура: должно быть 8 таблиц
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY 1;

-- 2. Enum-типы: должно быть 5
SELECT typname
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public' AND t.typtype = 'e'
ORDER BY 1;

-- 3. Внешние ключи и индексы
SELECT
    (SELECT count(*) FROM information_schema.table_constraints WHERE constraint_type = 'FOREIGN KEY') AS foreign_keys,
    (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public') AS indexes;

-- 4. Функция контрольной суммы ИНН: true / false
SELECT inn_is_valid('123456789047') AS valid_inn_ok,
       inn_is_valid('123456789012') AS invalid_inn_ok;

-- 5. Проверки ограничений: везде passed = true
SELECT num, check_name, expected, passed
FROM verify_results
ORDER BY num;

ROLLBACK;
