----------------------------------------------------------------------------------------
--
-- File name:   sql_perf_change_by_date.sql
--
-- Purpose:     Lists SQL Statements with Elapsed Time per Execution changing over time
--
-- Author:      Carlos Sierra
--
-- Version:     2017/11/28
--
-- Usage:       Lists statements that have changed their elapsed time per execution over
--              some history.
--              Uses the ratio between "elapsed time per execution" and the median of 
--              this metric for SQL statements within the sampled history, and using
--              linear regression identifies those that have changed the most. In other
--              words where the slope of the linear regression is larger. Positive slopes
--              are considered "improving" while negative are "regressing".
--
-- Example:     @sql_perf_change_by_date.sql
--
-- Parameters:  Range of dates
--
-- Notes:       Developed and tested on 11.2.0.3 and 12.2.0.1.
--
--              Requires an Oracle Diagnostics Pack License since AWR data is accessed.
--
--              To further investigate poorly performing SQL use sqld360.sql or planx.sql
--             
---------------------------------------------------------------------------------------
--

DEF elapsed_time_delta = '9000000';
DEF executions_delta = '1000';
DEF time_per_exec = '500';
DEF captured_at_least_x_times = '20';
DEF min_slope_threshold = '0.1';
DEF max_num_rows = '20';

SET TERM ON FEED OFF VER OFF ECHO OFF HEA ON LIN 400 PAGES 50 TAB OFF TIMI OFF LONG 80000 LONGC 2000 TRIMS ON;

COL current_time NEW_V current_time FOR A15;
SELECT 'current_time: ' x, TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') current_time FROM DUAL;
COL x_host_name NEW_V x_host_name;
SELECT host_name x_host_name FROM v$instance;
COL x_db_name NEW_V x_db_name;
SELECT name x_db_name FROM v$database;
COL x_container NEW_V x_container;
SELECT 'NONE' x_container FROM DUAL;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') x_container FROM DUAL;

COL default_yyyy_mm_dd_from HEA 'Default|YYYY-MM-DD|FROM';
COL default_yyyy_mm_dd_to HEA 'Default|YYYY-MM-DD|TO';

SELECT TO_CHAR(MIN(CAST(begin_interval_time AS DATE)), 'YYYY-MM-DD') default_yyyy_mm_dd_from,
       TO_CHAR(MAX(CAST(end_interval_time AS DATE)), 'YYYY-MM-DD') default_yyyy_mm_dd_to
  FROM dba_hist_snapshot;

ACC yyyy_mm_dd_from PROMPT 'Enter YYYY-MM-DD FROM (opt): ';
ACC yyyy_mm_dd_to   PROMPT 'Enter YYYY-MM-DD TO (opt): ';

DEF yyyy_mm_dd_from
DEF yyyy_mm_dd_to

COL row_n FOR A2 HEA '#';
COL executions HEA 'Executions';
COL med_secs_per_exec HEA 'Median Secs|Per Exec';
COL std_secs_per_exec HEA 'Std Dev Secs|Per Exec';
COL avg_secs_per_exec HEA 'Avg Secs|Per Exec';
COL min_secs_per_exec HEA 'Min Secs|Per Exec';
COL max_secs_per_exec HEA 'Max Secs|Per Exec';
COL plans FOR 9999;
COL sql_text_80 FOR A80;

SPO sql_perf_change_by_date_&&current_time..txt;
PRO HOST: &&x_host_name.
PRO DATABASE: &&x_db_name.
PRO CONTAINER: &&x_container.
PRO
PRO SQL Statements with "Elapsed Time per Execution" changing over time
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

WITH
per_time AS (
SELECT h.dbid,
       h.sql_id,
       SYSDATE - CAST(s.end_interval_time AS DATE) days_ago,
       SUM(h.elapsed_time_delta) / SUM(h.executions_delta) time_per_exec,
       SUM(h.executions_delta) executions
  FROM dba_hist_sqlstat h, 
       dba_hist_snapshot s
 WHERE h.executions_delta > 0 
   --AND h.plan_hash_value > 0
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND CAST(s.end_interval_time AS DATE) >= NVL(TO_DATE(TRIM('&&yyyy_mm_dd_from.'), 'YYYY-MM-DD'), CAST(s.end_interval_time AS DATE))
   AND CAST(s.end_interval_time AS DATE) <= NVL(TO_DATE(TRIM('&&yyyy_mm_dd_to.'), 'YYYY-MM-DD') + 1, CAST(s.end_interval_time AS DATE))
 GROUP BY
       h.dbid,
       h.sql_id,
       SYSDATE - CAST(s.end_interval_time AS DATE)
HAVING SUM(h.elapsed_time_delta) > &&elapsed_time_delta.
   AND SUM(h.executions_delta) > &&executions_delta.
   AND SUM(h.elapsed_time_delta) / SUM(h.executions_delta) > &&time_per_exec.
),
avg_time AS (
SELECT dbid,
       sql_id, 
       MEDIAN(time_per_exec) med_time_per_exec,
       STDDEV(time_per_exec) std_time_per_exec,
       AVG(time_per_exec)    avg_time_per_exec,
       MIN(time_per_exec)    min_time_per_exec,
       MAX(time_per_exec)    max_time_per_exec,
       SUM(executions)       executions
  FROM per_time
 GROUP BY
       dbid,
       sql_id
HAVING COUNT(*) >= &&captured_at_least_x_times. 
),
time_over_median AS (
SELECT h.dbid,
       h.sql_id,
       h.days_ago,
       (h.time_per_exec / a.med_time_per_exec) time_per_exec_over_med,
       a.med_time_per_exec,
       a.std_time_per_exec,
       a.avg_time_per_exec,
       a.min_time_per_exec,
       a.max_time_per_exec,
       a.executions
  FROM per_time h, avg_time a
 WHERE a.sql_id = h.sql_id
),
ranked AS (
SELECT RANK () OVER (ORDER BY ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) DESC) rank_num,
       t.dbid,
       t.sql_id,
       CASE WHEN REGR_SLOPE(t.time_per_exec_over_med, t.days_ago) > 0 THEN 'IMPROVING' ELSE 'REGRESSING' END change,
       ROUND(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago), 6) slope,
       ROUND(AVG(t.med_time_per_exec)/1e6, 6) med_secs_per_exec,
       ROUND(AVG(t.std_time_per_exec)/1e6, 6) std_secs_per_exec,
       ROUND(AVG(t.avg_time_per_exec)/1e6, 6) avg_secs_per_exec,
       ROUND(MIN(t.min_time_per_exec)/1e6, 6) min_secs_per_exec,
       ROUND(MAX(t.max_time_per_exec)/1e6, 6) max_secs_per_exec,
       SUM(t.executions)                      executions
  FROM time_over_median t
 GROUP BY
       t.dbid,
       t.sql_id
HAVING ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) > &&min_slope_threshold.
)
SELECT LPAD(ROWNUM, 2) row_n,
       r.sql_id,
       r.change,
       TO_CHAR(r.slope, '990.000MI') slope,
       TO_CHAR(r.executions, '999,999,999,999') executions,
       TO_CHAR(r.med_secs_per_exec, '999,990.000000') med_secs_per_exec,
       TO_CHAR(r.std_secs_per_exec, '999,990.000000') std_secs_per_exec,
       TO_CHAR(r.avg_secs_per_exec, '999,990.000000') avg_secs_per_exec,
       TO_CHAR(r.min_secs_per_exec, '999,990.000000') min_secs_per_exec,
       TO_CHAR(r.max_secs_per_exec, '999,990.000000') max_secs_per_exec,
       (SELECT COUNT(DISTINCT p.plan_hash_value) FROM dba_hist_sql_plan p WHERE p.dbid = r.dbid AND p.sql_id = r.sql_id) plans,
       REPLACE((SELECT DBMS_LOB.SUBSTR(s.sql_text, 80) FROM dba_hist_sqltext s WHERE s.dbid = r.dbid AND s.sql_id = r.sql_id AND ROWNUM = 1), CHR(10)) sql_text_80
  FROM ranked r
 WHERE r.rank_num <= &&max_num_rows.
 ORDER BY
       r.rank_num
/

SPO OFF;
SET FEED ON VER ON HEA ON LIN 80 PAGES 14 LONG 80 LONGC 80 TRIMS OFF;
