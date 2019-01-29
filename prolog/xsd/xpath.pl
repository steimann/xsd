:- module(xpath, 
	[
		assert/3,
		assertion/4
	]).

:- use_module(library(regex)).
:- use_module(library(xsd/date_time)).
:- use_module(library(xsd/simpletype)).
:- use_module(library(xsd/xsd_messages)).

:- op(1, fx, user:($)).
:- op(700, xfx, user:(eq)).

assert(D_File, D_ID, XPathExpr) :-
	warning('Testing for ~w with File ~w and ID ~w!', [XPathExpr, D_File, D_ID]).
assertion(D_File, D_ID, D_Text, XPathString) :-
	nb_setval(context_file, D_File),
	nb_setval(context_id, D_ID),
	nb_setval(context_value, D_Text),

	term_string(XPathExpr, XPathString),
	!,
	xpath_expr(XPathExpr, Result),
	(
		\+compound(Result);
		(
			=(Result, data(_, Value)),
			\=(Value, [false])
		)
	).
	% warning('Result: ~w', [Result]).


/* ### Special Cases ### */

/* --- atomic values are valid xpath expressions --- */
xpath_expr(Result, Result) :-
	% simple check for now - needs to be replaced by constructors later on
	\+compound(Result).


/* ### Special Functions ### */

/* --- $value --- */
xpath_expr($value, Result) :-
	nb_current(context_value, Value),
	term_string(Result, Value).


/* ### Operators ### */

/* --- eq --- */
xpath_expr(Value1 eq Value2, data('boolean', [ResultValue])) :-
	xpath_expr(Value1, Result1),
	xpath_expr(Value2, Result2),
	
	% just a simple numeric comparison for now (needs to be replaced)
	Result1 =:= Result2 ->
		ResultValue = true;
		ResultValue = false.


/* ### Functions ### */

/* ~~~ Constructors ~~~ */

/* --- string --- */
xpath_expr(string(Value), data('string', [ResultValue])) :-
	validate_xsd_simpleType('string', Value),
	term_string(Value, ResultValue).
/* --- boolean --- */
xpath_expr(boolean(Value), data('boolean', [ResultValue])) :-
	member(Value, ['false', '0']) ->
		ResultValue = false;
		ResultValue = true.
/* --- decimal --- */
xpath_expr(decimal(Value), data('decimal', [ResultValue])) :-
	validate_xsd_simpleType('decimal', Value),
	( % add leading 0 in front of decimal point, as prolog cannot handle decimals like ".32"
		Value =~ '^(\\+|-)?\\..*$' ->
		(
			atomic_list_concat(TMP, '.', Value),
			atomic_list_concat(TMP, '0.', ProcValue)	
		);
		ProcValue = Value
	),
	term_string(ResultValue, ProcValue).
/* --- float --- */
xpath_expr(float(Value), data('float', [ResultValue])) :-
	validate_xsd_simpleType('float', Value),
	parse_float(Value, ResultValue).
/* --- double --- */
xpath_expr(double(Value), data('double', [ResultValue])) :-
	validate_xsd_simpleType('double', Value),
	% double values are internally handled as float values
	parse_float(Value, ResultValue).
/* --- duration --- */
xpath_expr(duration(Value), Result) :-
	validate_xsd_simpleType('duration', Value),
	split_string(Value, 'P', '', PSplit),
	(
		PSplit = [Sign, PSplitR], Sign = '-';
		PSplit = [_, PSplitR], Sign = '+'
	),
	split_string(PSplitR, 'Y', '', YSplit),
	(
		YSplit = [YSplitR], Years = 0;
		YSplit = [YearsTMP, YSplitR], number_string(Years, YearsTMP)
	),
	split_string(YSplitR, 'M', '', MoSplit),
	(
		MoSplit = [MoSplitR], Months = 0;
		MoSplit = [MonthsTMP, MoSplitR], \+sub_string(MonthsTMP, _, _, _, 'T'), number_string(Months, MonthsTMP);
		MoSplit = [MoSplitR0, MoSplitR1], sub_string(MoSplitR0, _, _, _, 'T'), string_concat(MoSplitR0, 'M', TMP), string_concat(TMP, MoSplitR1, MoSplitR), Months = 0;
		MoSplit = [MonthsTMP, MoSplitR0, MoSplitR1], string_concat(MoSplitR0, 'M', TMP), string_concat(TMP, MoSplitR1, MoSplitR), number_string(Months, MonthsTMP)
	),
	split_string(MoSplitR, 'D', '', DSplit),
	(
		DSplit = [DSplitR], Days = 0;
		DSplit = [DaysTMP, DSplitR], number_string(Days, DaysTMP)
	),
	split_string(DSplitR, 'T', '', TSplit),
	(
		TSplit = [TSplitR];
		TSplit = [_, TSplitR]	
	),
	split_string(TSplitR, 'H', '', HSplit),
	(
		HSplit = [HSplitR], Hours = 0;
		HSplit = [HoursTMP, HSplitR], number_string(Hours, HoursTMP)	
	),
	split_string(HSplitR, 'M', '', MiSplit),
	(
		MiSplit = [MiSplitR], Minutes = 0;
		MiSplit = [MinutesTMP, MiSplitR], number_string(Minutes, MinutesTMP)
	),
	split_string(MiSplitR, 'S', '', SSplit),
	(
		SSplit = [_], Seconds = 0;
		SSplit = [SecondsTMP, _], number_string(Seconds, SecondsTMP)
	),
	normalize_duration(
		data('duration', [Sign, Years, Months, Days, Hours, Minutes, Seconds]),
		Result
	).
/* --- dateTime --- */
xpath_expr(dateTime(Value), data('dateTime', [Sign, Year, Month, Day, Hour, Minute, Second, TimeZoneSign, TimeZoneHour, TimeZoneMinute])) :-
	validate_xsd_simpleType('dateTime', Value),
	split_string(Value, 'T', '', TSplit),
	TSplit = [Date, Time],
	xpath_expr(date(Date), data('date', [Sign, Year, Month, Day, _, _, _])),
	xpath_expr(time(Time), data('time', [Hour, Minute, Second, TimeZoneSign, TimeZoneHour, TimeZoneMinute])).
xpath_expr(dateTime(Date,Time), data('dateTime', [Sign, Year, Month, Day, Hour, Minute, Second, TimeZoneSign, TimeZoneHour, TimeZoneMinute])) :-
	validate_xsd_simpleType('date', Date),
	validate_xsd_simpleType('time', Time),
	xpath_expr(date(Date), data('date', [Sign, Year, Month, Day, TimeZoneSignDate, TimeZoneHourDate, TimeZoneMinuteDate])),
	xpath_expr(time(Time), data('time', [Hour, Minute, Second, TimeZoneSignTime, TimeZoneHourTime, TimeZoneMinuteTime])),
	(
		% both date and time have the same or no TC
		TimeZoneSignDate = TimeZoneSignTime, TimeZoneSign = TimeZoneSignDate,
		TimeZoneHourDate = TimeZoneHourTime, TimeZoneHour = TimeZoneHourDate,
		TimeZoneMinuteDate = TimeZoneMinuteTime, TimeZoneMinute = TimeZoneMinuteDate;
		% only date has TC
		TimeZoneSign = TimeZoneSignDate,
		TimeZoneHourDate \= 0, TimeZoneHourTime = 0, TimeZoneHour = TimeZoneHourDate,
		TimeZoneMinuteDate \= 0, TimeZoneMinuteTime = 0, TimeZoneMinute = TimeZoneMinuteDate;
		% only time has TC
		TimeZoneSign = TimeZoneSignTime,
		TimeZoneHourDate = 0, TimeZoneHourTime \= 0, TimeZoneHour = TimeZoneHourTime,
		TimeZoneMinuteDate = 0, TimeZoneMinuteTime \= 0, TimeZoneMinute = TimeZoneMinuteTime
	).
/* --- time --- */
xpath_expr(time(Value), data('time', [Hour, Minute, Second, TimeZoneSign, TimeZoneHour, TimeZoneMinute])) :-
	validate_xsd_simpleType('time', Value),
	(
		% negative TC
		split_string(Value, '-', '', MinusSplit),
		MinusSplit = [TimeTMP, TimeZoneTMP],
		TimeZoneSign = '-'
		;
		% positive TC
		split_string(Value, '+', '', PlusSplit),
		PlusSplit = [TimeTMP, TimeZoneTMP],
		TimeZoneSign = '+'
		;
		% UTC TC
		split_string(Value, 'Z', '', ZSplit),
		ZSplit = [TimeTMP, _],
		TimeZoneSign = '+',
		TimeZoneTMP = '00:00'
		;
		% no TC
		split_string(Value, 'Z+-', '', AllSplit),
		AllSplit = [TimeTMP],
		TimeZoneSign = '+',
		TimeZoneTMP = '00:00'
	),
	split_string(TimeTMP, ':', '', TimeSplit),
	TimeSplit = [HourTMP, MinuteTMP, SecondTMP],
	split_string(TimeZoneTMP, ':', '', TimeZoneSplit),
	TimeZoneSplit = [TimeZoneHourTMP, TimeZoneMinuteTMP],
	number_string(Hour, HourTMP),
	number_string(Minute, MinuteTMP),
	number_string(Second, SecondTMP),
	number_string(TimeZoneHour, TimeZoneHourTMP),
	number_string(TimeZoneMinute, TimeZoneMinuteTMP).
/* --- date --- */
xpath_expr(date(Value), data('date', [Sign, Year, Month, Day, TimeZoneSign, TimeZoneHour, TimeZoneMinute])) :-
	validate_xsd_simpleType('date', Value),
	split_string(Value, '-', '', MinusSplit),
	(
		% BC, negative TZ
		MinusSplit = [_, YearTMP, MonthTMP, DayTMP, TimeZoneTMP], Sign = '-', TimeZoneSign = '-';
		% BC, ...
		MinusSplit = [_, YearTMP, MonthTMP, DayTimeZoneTMP], Sign = '-', TimeZoneSign = '+',
		(
			% ... UTC TC
			split_string(DayTimeZoneTMP, 'Z', '', ZSplit), ZSplit = [DayTMP, _], TimeZoneTMP = '00:00';
			% ... positive TC
			split_string(DayTimeZoneTMP, '+', '', PlusSplit), PlusSplit = [DayTMP, TimeZoneTMP];
			% ... no TZ
			\+sub_string(DayTimeZoneTMP, _, _, _, 'Z'), \+sub_string(DayTimeZoneTMP, _, _, _, '+'), 
			DayTMP = DayTimeZoneTMP, TimeZoneTMP = '00:00'
		);
		% AD, negative TZ
		MinusSplit = [YearTMP, MonthTMP, DayTMP, TimeZoneTMP], Sign = '+', TimeZoneSign = '-';
		% AD, ...
		MinusSplit = [YearTMP, MonthTMP, DayTimeZoneTMP], Sign = '+', TimeZoneSign = '+',
		(
			% ... UTC TC
			split_string(DayTimeZoneTMP, 'Z', '', ZSplit), ZSplit = [DayTMP, _], TimeZoneTMP = '00:00';
			% ... positive TC
			split_string(DayTimeZoneTMP, '+', '', PlusSplit), PlusSplit = [DayTMP, TimeZoneTMP];
			% ... no TZ
			\+sub_string(DayTimeZoneTMP, _, _, _, 'Z'), \+sub_string(DayTimeZoneTMP, _, _, _, '+'), 
			DayTMP = DayTimeZoneTMP, TimeZoneTMP = '00:00'
		)
	),
	split_string(TimeZoneTMP, ':', '', ColonSplit),
	ColonSplit = [TimeZoneHourTMP, TimeZoneMinuteTMP],
	number_string(Year, YearTMP),
	number_string(Month, MonthTMP),
	number_string(Day, DayTMP),
	number_string(TimeZoneHour, TimeZoneHourTMP),
	number_string(TimeZoneMinute, TimeZoneMinuteTMP).


/* ~~~ Parsing ~~~ */

parse_float(Value, nan) :-
	Value =~ '^\\+?NaN$'.
parse_float(Value, -nan) :-
	Value =~ '^-NaN$'.
parse_float(Value, inf) :-
	Value =~ '^\\+?INF$'.
parse_float(Value, -inf) :-
	Value =~ '^-INF$'.
parse_float(Value, ResultValue) :-
	term_string(ValueTerm, Value), ResultValue is float(ValueTerm).


/* ~~~ Normalization ~~~ */

normalize_duration(
	data('duration', [USign, UYears, UMonths, UDays, UHours, UMinutes, USeconds]),
	data('duration', [NSign, NYears, NMonths, NDays, NHours, NMinutes, NSeconds])) :-
	% 0 =< Seconds < 60
	% seconds are (in constrast to the other values) given as float
	number_string(USeconds, SUSeconds),
	split_string(SUSeconds, '.', '', LUSeconds),
	(
		LUSeconds = [SIntegerSeconds], number_string(IntegerSeconds, SIntegerSeconds), NSeconds is IntegerSeconds mod 60;
		LUSeconds = [SIntegerSeconds,SFractionalSeconds], number_string(IntegerSeconds, SIntegerSeconds),
			TSeconds is IntegerSeconds mod 60, number_string(TSeconds, STSeconds),
			atomic_list_concat([STSeconds,SFractionalSeconds], '.', ANSeconds), atom_string(ANSeconds, SNSeconds), number_string(NSeconds, SNSeconds)
	),
	MinutesDiv is IntegerSeconds div 60,
	% 0 =< Minutes < 60
	MinutesTMP is UMinutes + MinutesDiv,
	HoursDiv is MinutesTMP div 60, NMinutes is MinutesTMP mod 60,
	% 0 =< Hours < 24
	HoursTMP is UHours + HoursDiv,
	DaysDiv is HoursTMP div 24, NHours is HoursTMP mod 24,
	% 0 =< Days < 31
	DaysTMP is UDays + DaysDiv,
	MonthsDiv is DaysTMP div 31, NDays is DaysTMP mod 31,
	% 0 =< Months < 12
	MonthsTMP is UMonths + MonthsDiv,
	YearsDiv is MonthsTMP div 12, NMonths is MonthsTMP mod 12,
	% Years have no restrictions
	YearsTMP is UYears + YearsDiv,
	(
		% negative year values lead to a flipping of the sign
		YearsTMP < 0 ->
			(
				USign = '+' ->
					NSign = '-';
					NSign = '+'	
			);
			(
				% durations of 0 are always positive
				UYears = 0, UMonths = 0, UDays = 0, UHours = 0, UMinutes = 0, USeconds = 0 ->
					NSign = '+';
					NSign = USign
			)
	),
	NYears is abs(YearsTMP).