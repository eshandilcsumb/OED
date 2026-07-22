CREATE MATERIALIZED VIEW group_hourly_readings_unit_cagg AS
SELECT
    gdm.group_id,
    mh.graphic_unit_id,
    mh.bucket,
    SUM(mh.reading_rate) AS reading_rate
FROM meter_hourly_readings_unit_cagg mh
INNER JOIN groups_deep_meters gdm
    ON mh.meter_id = gdm.meter_id
INNER JOIN LATERAL unnest(
    get_graphic_unit(gdm.group_id)
) AS gu(graphic_unit_id)
    ON mh.graphic_unit_id = gu.graphic_unit_id
GROUP BY
    gdm.group_id,
    mh.graphic_unit_id,
    mh.bucket
WITH NO DATA;

ALTER MATERIALIZED VIEW group_hourly_readings_unit_cagg
SET (
    timescaledb.materialized_only = true
);