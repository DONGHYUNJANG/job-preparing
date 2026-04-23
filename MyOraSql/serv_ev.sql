SELECT service_name, event, total_waits, time_waited
FROM   gv$service_event
WHERE  service_name IN ('GL', 'AP')
ORDER BY service_name, time_waited DESC
/
