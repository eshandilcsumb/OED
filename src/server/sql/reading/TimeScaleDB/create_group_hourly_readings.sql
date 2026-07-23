/*
 * Create continuous aggregate for hourly group readings.
 *
 * Data flow:
 *
 *   meter_hourly_readings_unit_cagg
 *              |
 *              | (expanded into group rows)
 *              v
 *   group_hourly_readings_unit_ht
 *              |
 *              v
 *   group_hourly_readings_unit_cagg
 *
 * The group hypertable already contains one row per
 * group, graphic unit, and hourly bucket.
 *
 * Therefore, this continuous aggregate only performs
 * the aggregation of readings for each group/hour
 * without joining against groups_deep_meters during
 * query execution.
 */

CREATE MATERIALIZED VIEW group_hourly_readings_unit_cagg
WITH (timescaledb.continuous) AS
SELECT
    group_id,
    graphic_unit_id,
    time_bucket('1 hour', bucket) AS bucket,
    SUM(reading_rate) AS reading_rate,
    SUM(max_rate) AS max_rate,
    SUM(min_rate) AS min_rate
FROM group_hourly_readings_unit_ht
GROUP BY
    group_id,
    graphic_unit_id,
    time_bucket('1 hour', bucket)
WITH NO DATA;

ALTER MATERIALIZED VIEW group_hourly_readings_unit_cagg
SET (
    timescaledb.materialized_only = false
);