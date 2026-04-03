# 데이터가드 DB설치후 2

![image (19).png](image_(19).png)

### 1. prod db 를 아카이브 모드로 변경합니다.

```sql
[oracle@ora19c ~]$ sqlplus / as sysdba

SQL*Plus: Release 19.0.0.0.0 - Production on Thu Apr 2 16:08:02 2026
Version 19.26.0.0.0

Copyright (c) 1982, 2024, Oracle.  All rights reserved.

Connected to:
Oracle Database 19c Enterprise Edition Release 19.0.0.0.0 - Production
Version 19.26.0.0.0

SYS@PROD> archive log list
Database log mode              No Archive Mode
Automatic archival             Disabled
Archive destination            /u01/app/oracle/product/19.3.0/dbhome_1/dbs/arch
Oldest online log sequence     10
Current log sequence           14
SYS@PROD>
SYS@PROD> shutdown immediate
Database closed.
Database dismounted.
ORACLE instance shut down.
SYS@PROD>
SYS@PROD>
SYS@PROD> startup mount
ORACLE instance started.

Total System Global Area 1073739904 bytes
Fixed Size                  8947840 bytes
Variable Size             629145600 bytes
Database Buffers          427819008 bytes
Redo Buffers                7827456 bytes
Database mounted.
SYS@PROD>
SYS@PROD> alter database archivelog;

Database altered.

SYS@PROD> alter database open;

Database altered.

SYS@PROD> archive log list
Database log mode              Archive Mode
Automatic archival             Enabled
Archive destination            /u01/app/oracle/product/19.3.0/dbhome_1/dbs/arch
Oldest online log sequence     10
Next log sequence to archive   14
Current log sequence           14
SYS@PROD>

```

### 2. force logging 을 database 레벨로 활성화 해야합니다.

```sql
SYS@PROD> alter database force logging;

SYS@PROD> alter database add supplemental log data
          (primary key, unique index) columns;

SYS@PROD> alter system archive log current;

SYS@PROD> alter system switch logfile;

System altered.

SYS@PROD> select name from v$archived_log;

NAME
--------------------------------------------------------------------------------
/u01/app/oracle/product/19.3.0/dbhome_1/dbs/arch1_14_1229442941.dbf
/u01/app/oracle/product/19.3.0/dbhome_1/dbs/arch1_15_1229442941.dbf

SYS@PROD> select force_logging from v$database;

FORCE_LOGGING
--------------------------------------------------------------------------------
YES

shutdown immediate;

```

### 3. PROD 쪽 파라미터 파일을 수정합니다.

```sql

 $ cd $ORACLE_HOME/dbs
 $ vi  initPROD.ora

 #맨 아래쪽에 아래의 내용을 추가한다.
 # 지금부터는 data guard 를 구성하기 위한 파라미터들을 설정 
  
 db_unique_name=PROD

 # 해설: standby db 쪽에서 primary db 이름이 PROD 라는 것을 알아해서  
 # primary db 쪽에 db_unique_name 을 PROD 라고 셋팅해야한다. 

 standby_file_management=auto
 
 # 해설: primary db 쪽에서 테이블 스페이스를 생성하면
 # standby db 쪽에서도 똑같은 테이블 스페이스가 자동으로 
 # 만들어지게 하는 파라미터 

 db_file_name_convert='/home/oracle/SBDB','/u01/app/oracle/oradata/PROD'

#해설: Primary db쪽에는 data file 이 
# /u01/app/oracle/oradata/PROD   <---- 이 위치에 있고

# Standby db 쪽에는 data file 이
# /home/oracle/SBDB   <--------- 이 위치에 있다는것을 알려줌 

log_file_name_convert='/home/oracle/SBDB','/u01/app/oracle/oradata/PROD'

# 해설: Primary db쪽에는 redo log file 이 
# /u01/app/oracle/oradata/PROD   <---- 이 위치에 있고
# Standby db 쪽에는 redo log file  이
# /home/oracle/SBDB   <--------- 이 위치에 있다는것을 알려줌 

log_archive_dest_1='location=/home/oracle/PROD/arch valid_for=(all_logfiles,all_roles)'

# 해설:  primary db 쪽에 아카이브 로그 파일이 생성될 위치 위치

# 저장하고 나와서 위의 파라미터에 관련된 디렉토리를 생성합니다.
[oracle@ora19c ~]$ cd 
[oracle@ora19c ~]$ pwd
/home/oracle
[oracle@ora19c ~]$ mkdir PROD
[oracle@ora19c ~]$
[oracle@ora19c ~]$ cd PROD
[oracle@ora19c PROD]$ mkdir arch
[oracle@ora19c PROD]$ cd arch
[oracle@ora19c arch]$ pwd
/home/oracle/PROD/arch

-- 그리고 다음 파라미터 파일의 initPROD.ora에 맨 밑에 아래의 내용을 저장합니다.

[oracle@ora19c dbs]$ cd $ORACLE_HOME/dbs
[oracle@ora19c dbs]$
[oracle@ora19c dbs]$ pwd
/u01/app/oracle/product/19.3.0/dbhome_1/dbs
[oracle@ora19c dbs]$
[oracle@ora19c dbs]$ vi initPROD.ora

log_archive_dest_2='service=SBDB LGWR SYNC AFFIRM valid_for=(online_logfiles,primary_role)' 

# 해설: standby db 쪽에 생성할 아카이브 로그파일의 위치 

fal_server=SBDB
fal_client=PROD

# 설명: 나중에 primary db 가 standby db 가 될수있기 때문에 미리 적어놓은 파라미터

# 그래서 PROD쪽 initPROD.ORA 의 전체 내용은 다음과 같습니다.

db_name=PROD
compatible=19.3.0
memory_target=1G
processes=300
undo_management=AUTO
undo_tablespace=UNDOTBS1
remote_login_passwordfile=EXCLUSIVE
control_files=('/u01/app/oracle/oradata/PROD/disk1/ctrl1.ctl',
               '/u01/app/oracle/oradata/PROD/disk2/ctrl2.ctl',
               '/u01/app/oracle/oradata/PROD/disk3/ctrl3.ctl')
db_unique_name=PROD
standby_file_management=auto
db_file_name_convert='/home/oracle/SBDB','/u01/app/oracle/oradata/PROD'
log_file_name_convert='/home/oracle/SBDB','/u01/app/oracle/oradata/PROD'
log_archive_dest_1='location=/home/oracle/PROD/arch valid_for=(all_logfiles,all_roles)'
log_archive_dest_2='service=SBDB LGWR SYNC AFFIRM valid_for=(online_logfiles,primary_role)'
fal_server=SBDB
fal_client=PROD

```