SELECT s.service_name, s.inst_id, COUNT(*) AS session_count
FROM   gv$session s
WHERE  s.service_name IN ('GL', 'AP')
GROUP BY s.service_name, s.inst_id
ORDER BY s.service_name
/
