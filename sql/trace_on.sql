-- turns sql trace on using event 10046 level 12 (include binds and waits)
--ALTER SESSION SET tracefile_identifier = 'iod_indexes_rebuild_online';
ALTER SESSION SET STATISTICS_LEVEL = 'ALL';
ALTER SESSION SET EVENTS '10046 TRACE NAME CONTEXT FOREVER, LEVEL 12';