col NEXT_CHANGE# for 99999999999999999999999999999999
select group#, status, sequence#, archived, bytes/1024/1024, FIRST_CHANGE#, NEXT_CHANGE#
from v$log
/
