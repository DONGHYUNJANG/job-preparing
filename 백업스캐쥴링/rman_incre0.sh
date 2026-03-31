export ORACLE_SID=orcl                        
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

LOG_DIR=/home/oracle/rman_logs
mkdir -p $LOG_DIR
LOG_FILE=$LOG_DIR/rman_inc0_$(date +%Y%m%d_%H%M%S).log

rman target / << EOF  >> $LOG_FILE 2>&1
backup incremental level 0 database;
EOF

