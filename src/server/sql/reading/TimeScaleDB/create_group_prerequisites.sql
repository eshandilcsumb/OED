/*
 * create_group_prerequisites.sql
 *
 * Creates the group-specific hypertable used as the source of
 * group_hourly_readings_unit_cagg.
 *
 * Data flow:
 *
 * meter_hourly_readings_unit_cagg
 *              |
 *              v
 * group_hourly_readings_unit_ht
 *              |
 *              v
 * group_hourly_readings_unit_cagg
 */

CREATE TABLE IF NOT EXISTS group_hourly_readings_unit_ht (
    group_id INTEGER NOT NULL,
    meter_id INTEGER NOT NULL,
    graphic_unit_id INTEGER NOT NULL,
    bucket TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    reading_rate DOUBLE PRECISION NOT NULL,
    max_rate DOUBLE PRECISION,
    min_rate DOUBLE PRECISION
);

SELECT create_hypertable(
    'group_hourly_readings_unit_ht',
    by_range('bucket'),
    if_not_exists => TRUE
);

CREATE UNIQUE INDEX IF NOT EXISTS
    group_hourly_readings_unit_ht_unique_idx
ON group_hourly_readings_unit_ht (
    group_id,
    meter_id,
    graphic_unit_id,
    bucket
);

CREATE INDEX IF NOT EXISTS
    group_hourly_readings_unit_ht_query_idx
ON group_hourly_readings_unit_ht (
    group_id,
    graphic_unit_id,
    bucket
);

/*
 * Rebuild the group hypertable from the existing meter hourly CAGG.
 *
 * Run this after:
 *   - meter_hourly_readings_unit_cagg is refreshed;
 *   - group membership changes;
 *   - groups_deep_meters is refreshed.
 */
CREATE OR REPLACE FUNCTION rebuild_group_hourly_readings_unit_ht()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE group_hourly_readings_unit_ht;

    INSERT INTO group_hourly_readings_unit_ht (
        group_id,
        meter_id,
        graphic_unit_id,
        bucket,
        reading_rate,
        max_rate,
        min_rate
    )
    SELECT
        gdm.group_id,
        mh.meter_id,
        mh.graphic_unit_id,
        mh.bucket,
        mh.reading_rate,
        mh.max_rate,
        mh.min_rate
    FROM meter_hourly_readings_unit_cagg mh

    INNER JOIN groups_deep_meters gdm
        ON mh.meter_id = gdm.meter_id

    INNER JOIN LATERAL unnest(
        get_graphic_unit(gdm.group_id)
    ) AS gu(graphic_unit_id)
        ON mh.graphic_unit_id = gu.graphic_unit_id;
END;
$$;