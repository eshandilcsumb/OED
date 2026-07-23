/*
The following function returns data for plotting bar graphs. It works on groups.
It should not be used on raw readings.
It is the new version of compressed_barchart_group_readings_2 that works with units. It takes these parameters:
group_ids: A array of group ids to query.
graphic_unit_id: The unit id of the unit to use for the graph.
bar_width_days: The number of days to use for the bar width.
start_timestamp: The start timestamp of the data to return.
end_timestamp: The end timestamp of the data to return.
 */
CREATE OR REPLACE FUNCTION group_bar_readings_unit (
	group_ids INTEGER[],
	requested_graphic_unit_id INTEGER,
	bar_width_days INTEGER,
	start_stamp TIMESTAMP,
	end_stamp TIMESTAMP
)
	RETURNS TABLE(group_id INTEGER, reading FLOAT, start_timestamp TIMESTAMP, end_timestamp TIMESTAMP)
AS $$
DECLARE
	bar_width INTERVAL;
	real_tsrange TSRANGE;
	real_start_stamp TIMESTAMP;
	real_end_stamp TIMESTAMP;
	num_bars INTEGER;
	readings_max_tsrange TSRANGE;
BEGIN
	bar_width := INTERVAL '1 day' * bar_width_days;

	SELECT tsrange(MIN(dr.bucket), MAX(dr.bucket + INTERVAL '1 day')) INTO readings_max_tsrange
	FROM group_daily_readings_unit_cagg dr
	-- Get all the group ids passed in.
	INNER JOIN unnest(group_ids) gids(id) ON dr.group_id = gids.id
    WHERE dr.graphic_unit_id = requested_graphic_unit_id;

	real_tsrange := tsrange(date_trunc_up('day', start_stamp), date_trunc('day', end_stamp)) * readings_max_tsrange;
	-- Get the actual start/end time rounded to the nearest day from the range.
	real_start_stamp := lower(real_tsrange);
	real_end_stamp := upper(real_tsrange);
	-- This gives the number of whole bars that will fit within the real start/end times. For example, if the number of days
	-- between start and end is 14 days and the bar width is 3 days then you get 4.
	num_bars := floor(extract(EPOCH FROM real_end_stamp - real_start_stamp) / extract(EPOCH FROM bar_width));
	-- This makes the full bars go from the end time to as far back in time as possible.
	-- This means that if some time was dropped to get full bars it is at the start of the interval.
	-- It was felt that the most recent readings are the most important so drop older ones.
	-- It also helps with maps since they use the latest bar for their value.
	real_start_stamp := real_end_stamp - (num_bars *  bar_width);
	-- Since the inner join on the generate_series adds the bar_width, we need to back up the
	-- end timestamp by that amount so it stops at the desired end timestamp.
	real_end_stamp := real_end_stamp - bar_width;

	RETURN QUERY
		SELECT
		-- readings.reading_rate is the weighted average reading rate per hour over the day.
		-- Convert to a quantity by multiplying by the time in hours which is 24 since daily values.
		-- reading is the sum of all readings within one bar.
		readings.group_id,
		SUM(readings.reading_rate * 24) AS reading,
		bars.interval_start AS start_timestamp,
		bars.interval_start + bar_width AS end_timestamp

		FROM (((group_daily_readings_unit_cagg readings
			INNER JOIN generate_series(real_start_stamp, real_end_stamp, bar_width) bars(interval_start)
			ON tsrange(bars.interval_start, bars.interval_start + bar_width, '[]') @> tsrange(readings.bucket, readings.bucket + INTERVAL '1 day','()'))
			-- Don't return bar data if raw since cannot sum.
			INNER JOIN units u ON readings.graphic_unit_id = u.id AND u.unit_represent != 'raw'::unit_represent_type)
			INNER JOIN unnest(group_ids) gids(id) ON readings.group_id = gids.id)
			-- Use the readings in the passed in graphic unit
			WHERE readings.graphic_unit_id = requested_graphic_unit_id

			GROUP BY readings.group_id, bars.interval_start;
END;
$$ LANGUAGE 'plpgsql';