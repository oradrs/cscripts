PRO Enter SQL_ID
DEF sql_id_y = '&1.'
@planx.sql Y &&sql_id_y.
@sqlperf.sql &&sql_id_y.
--@dba_hist_sqlstat_sql_id_chart.sql &&sql_id_y. ""
@dba_hist_sqlstat_dbtime_chart.sql "" N &&sql_id_y. ""
@dba_hist_sqlstat_execs_chart.sql "" N &&sql_id_y. ""
@dba_hist_sqlstat_bg_chart.sql "" N &&sql_id_y. ""
@sqlash.sql Y &&sql_id_y.
@sqlmon.sql Y &&sql_id_y.

UNDEF sql_id_y
UNDEF 1 2