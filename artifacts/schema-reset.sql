-- ВыплатыПро: сброс схемы перед повторным применением schema-registry.sql
-- Использовать только на тестовой базе: удаляет все таблицы и типы контура.
-- Порядок важен: сначала таблицы, потом типы (иначе DROP TYPE упрётся в зависимости).

DROP TABLE IF EXISTS validation_reports CASCADE;
DROP TABLE IF EXISTS receipts CASCADE;
DROP TABLE IF EXISTS payouts CASCADE;
DROP TABLE IF EXISTS payout_rows CASCADE;
DROP TABLE IF EXISTS processed_events CASCADE;
DROP TABLE IF EXISTS registries CASCADE;
DROP TABLE IF EXISTS contractors CASCADE;
DROP TABLE IF EXISTS companies CASCADE;

DROP FUNCTION IF EXISTS inn_is_valid(text);
DROP TYPE IF EXISTS receipt_status CASCADE;
DROP TYPE IF EXISTS payout_status CASCADE;
DROP TYPE IF EXISTS reject_reason CASCADE;
DROP TYPE IF EXISTS row_status CASCADE;
DROP TYPE IF EXISTS registry_status CASCADE;
