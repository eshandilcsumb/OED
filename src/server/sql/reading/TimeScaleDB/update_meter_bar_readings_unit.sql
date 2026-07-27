/*
This takes tsrange_to_shrink which is the requested time range to plot and makes sure it does
not exceed the start/end times for all the readings. This can be an issue, in particular,
because infinity is used to indicate to graph all readings. This version does it to the nearest
day by using the day reading view since bars use to the nearest day and this should be faster.
This should be fine since bar uses the same view to get data.
 */
CREATE OR REPLACE FUNCTION shrink_tsrange_to_meters_by_day(tsrange_to_shrink TSRANGE, meter_ids INTEGER[])
	RETURNS TSRANGE
AS $$
DECLARE
	readings_max_tsrange TSRANGE;
BEGIN
	SELECT tsrange(min(dr.bucket), max(dr.bucket + INTERVAL '1 day')) INTO readings_max_tsrange
	FROM meter_daily_readings_unit_cagg dr
	-- Get all the meter_ids in the passed array of meters.
	INNER JOIN unnest(meter_ids) meters(id) ON dr.meter_id = meters.id;
	-- Make the original range be to the day by dropping parts of days at start/end.
	RETURN tsrange(date_trunc_up('day', lower(tsrange_to_shrink)), date_trunc('day', upper(tsrange_to_shrink))) * readings_max_tsrange;
END;
$$ LANGUAGE 'plpgsql';


/*
The following function returns data for plotting bar graphs. It works on meters.
It should not be used on raw readings.
It is the new version of compressed_barchart_readings_2 that works with units. It takes these parameters:
meter_ids: A array of meter ids to query.
graphic_unit_id: The unit id of the unit to use for the graph.
bar_width_days: The number of days to use for the bar width.
start_timestamp: The start timestamp of the data to return.
end_timestamp: The end timestamp of the data to return.
 */
-- New version of meter_bar_readings_unit that uses the new meter_daily_readings_unit view.
CREATE OR REPLACE FUNCTION meter_bar_readings_unit (
	meter_ids INTEGER[],
	-- This is the graphic unit id, changed from graphic_unit_id to avoid confusion with the graphic unit id in the view.
	passed_graphic_unit_id INTEGER,
	bar_width_days INTEGER,
	start_stamp TIMESTAMP,
	end_stamp TIMESTAMP
)
	RETURNS TABLE(meter_id INTEGER, reading FLOAT, start_timestamp TIMESTAMP, end_timestamp TIMESTAMP)
AS $$
DECLARE
	bar_width INTERVAL;
	real_tsrange TSRANGE;
	real_start_stamp TIMESTAMP;
	real_end_stamp TIMESTAMP;
	num_bars INTEGER;
BEGIN
	-- This is how wide (time interval) for each bar.
	bar_width := INTERVAL '1 day' * bar_width_days;
	/*
	This rounds to the day for the start and end times requested. It then shrinks in case the actual readings span
	less time than the request. This can commonly happen when you get +/-infinity for all readings available.
	It uses the day reading view because that is faster than using all the readings.
	This has an issue associated with it:

	1) If the readings at the start/end have a partial day then it shows up as a day. The original code did:
	real_tsrange := shrink_tsrange_to_real_readings(tsrange(date_trunc_up('day', start_stamp), date_trunc('day', end_stamp)));
	and did not have this issue since it used the readings and then truncated up/down.
	A more general solution would be to change the daily (and hourly) view so it does not include partial ones at start/end.
	This would fix this case and also impact other uses in what seems a positive way.
	Note this does not address that missing days in a bar width get no value so the bar will likely read low.
	*/
	real_tsrange := shrink_tsrange_to_meters_by_day(tsrange(start_stamp, end_stamp), meter_ids);
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
		-- Modified to retrieve converted daily readings from the materialized view.
		mdr.meter_id AS meter_id,
		sum(mdr.reading_rate * 24)  AS reading,
		bars.interval_start AS start_timestamp,
		bars.interval_start + bar_width AS end_timestamp

		FROM meter_daily_readings_unit_cagg mdr
		INNER JOIN generate_series(real_start_stamp, real_end_stamp, bar_width) bars(interval_start)
				ON tsrange(bars.interval_start, bars.interval_start + bar_width, '[]') @> tsrange(mdr.bucket, mdr.bucket + INTERVAL '1 day', '()')
		INNER JOIN unnest(meter_ids) meters(id) ON mdr.meter_id = meters.id
		INNER JOIN meters m ON m.id = meters.id
		INNER JOIN units u ON m.unit_id = u.id AND u.unit_represent != 'raw'::unit_represent_type
		WHERE mdr.graphic_unit_id = passed_graphic_unit_id
		GROUP BY mdr.meter_id, bars.interval_start;

END;
$$ LANGUAGE 'plpgsql';