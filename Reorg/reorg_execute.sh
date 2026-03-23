#!/bin/bash

# =============================================================================
# Oracle Table/Index Reorg Parallel Execution Script (Refactored)
# =============================================================================
#
# !! WARNING !!
# 1. Run this script outside of peak hours.
# 2. Ensure a full backup is completed before execution.
# 3. This script is intended for NON-PARTITIONED, NON-IOT tables.
#

# ---[ 1. User Configuration ]-------------------------------------------------
# !! Set your environment and connection details !!
export ORACLE_SID="ORCL"                  # Your Oracle SID
export ORACLE_HOME="/u01/app/oracle/product/19c/dbhome_1" # Your Oracle Home
export PATH=$ORACLE_HOME/bin:$PATH

# -- Connection (Option 1: OS Authentication)
# SQLPLUS_CONN="/ as sysdba"

# -- Connection (Option 2: User/Password)
SQLPLUS_USER="system"
SQLPLUS_PASS="your_password"
SQLPLUS_CONN="${SQLPLUS_USER}/${SQLPLUS_PASS}"

# -- Target Schema and Parallelism
SCHEMA_NAME="SH"
# [Refactored 1] Separated Shell Concurrency and SQL Parallelism
JOB_CONCURRENCY=2  # Number of tables/indexes to process simultaneously at the shell level.
SQL_DOP=4          # Degree of Parallelism for each SQL operation (ALTER TABLE/INDEX).

# ---[ 2. Script Setup ]-------------------------------------------------------
# Get the directory where the script is located, for robust file path handling.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

LOG_FILE="${SCRIPT_DIR}/reorg_execute_$(date +%Y%m%d_%H%M%S).log"
TABLE_LIST_FILE="${SCRIPT_DIR}/reorg_table_list.txt"
INDEX_LIST_FILE="${SCRIPT_DIR}/reorg_index_list.txt"
UNUSABLE_INDEX_LIST_FILE="${SCRIPT_DIR}/reorg_unusable_indexes.txt"
INVALID_OBJECT_LIST_FILE="${SCRIPT_DIR}/reorg_invalid_objects.txt"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# [Refactored 2] Enhanced spooling options for cleaner files
run_sql_spool() {
    sqlplus -S "${SQLPLUS_CONN}" <<EOF
SET HEADING OFF FEEDBACK OFF VERIFY OFF TERMOUT OFF LINES 200 PAGESIZE 0 TRIMSPOOL ON ECHO OFF
$1
EXIT;
EOF
}

# [Refactored 3] Added error handling to stop on SQL errors
run_sql_exec() {
    sqlplus -S "${SQLPLUS_CONN}" <<EOF
SET FEEDBACK OFF VERIFY OFF SERVEROUTPUT ON
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;
$1
EXIT;
EOF
}


# ---[ 3. Main Execution ]-----------------------------------------------------

log ">>>>> Table Reorg Script Started. <<<<<"
log "Target Schema: ${SCHEMA_NAME}"
log "Job Concurrency (Shell): ${JOB_CONCURRENCY}"
log "SQL DOP (Oracle): ${SQL_DOP}"

# ---[ 3-1. Generate Table List ]---
log "Step 1: Generating list of tables to reorganize..."
run_sql_spool "SPOOL ${TABLE_LIST_FILE};
SELECT TABLE_NAME FROM DBA_TABLES
WHERE OWNER = '${SCHEMA_NAME}'
  AND PARTITIONED = 'NO'
  AND IOT_TYPE IS NULL
  AND TEMPORARY = 'N'
  AND NESTED = 'NO'
  AND SECONDARY = 'N'
  AND CLUSTER_NAME IS NULL
  AND TABLE_NAME NOT LIKE 'AQ\$%'
  AND TABLE_NAME NOT LIKE 'MLOG\$%'
  AND TABLE_NAME NOT LIKE 'RUPD\$%'
  AND DROPPED = 'NO';
SPOOL OFF;"

if [ ! -s "${TABLE_LIST_FILE}" ]; then
    log "ERROR: No tables found for schema ${SCHEMA_NAME} or failed to generate table list."
    exit 1
fi
log "Table list generated: ${TABLE_LIST_FILE}"


# ---[ 3-2. Reorganize Tables ]---
log "Step 2: Reorganizing tables (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
job_count=0
for table in $(cat ${TABLE_LIST_FILE}); do
    (
        log "  -> Moving table: ${table}"
        # [Refactored 4] Added NOPARALLEL to reset table properties after MOVE
        move_sql="
        ALTER TABLE ${SCHEMA_NAME}.${table} MOVE PARALLEL ${SQL_DOP};
        ALTER TABLE ${SCHEMA_NAME}.${table} NOPARALLEL;
        "
        run_sql_exec "${move_sql}"
        log "  <- Move & Noparallel complete: ${table}"
    ) &

    ((job_count++))
    if [ ${job_count} -ge ${JOB_CONCURRENCY} ]; then
        wait
        job_count=0
    fi
done
wait
log "All table MOVE operations completed."


# ---[ 3-3. Rebuild Indexes ]---
log "Step 3: Rebuilding indexes (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
run_sql_spool "SPOOL ${INDEX_LIST_FILE};
SELECT INDEX_NAME FROM DBA_INDEXES WHERE OWNER = '${SCHEMA_NAME}' AND TABLE_NAME IN (
    SELECT TABLE_NAME FROM DBA_TABLES
    WHERE OWNER = '${SCHEMA_NAME}'
      AND PARTITIONED = 'NO'
      AND IOT_TYPE IS NULL
      AND TEMPORARY = 'N'
      AND NESTED = 'NO'
      AND SECONDARY = 'N'
      AND CLUSTER_NAME IS NULL
      AND TABLE_NAME NOT LIKE 'AQ\$%'
      AND TABLE_NAME NOT LIKE 'MLOG\$%'
      AND TABLE_NAME NOT LIKE 'RUPD\$%'
      AND DROPPED = 'NO'
);
SPOOL OFF;"

if [ ! -s "${INDEX_LIST_FILE}" ]; then
    log "WARNING: No indexes found for tables in schema ${SCHEMA_NAME}."
else
    log "Index list generated: ${INDEX_LIST_FILE}"
    job_count=0
    for index in $(cat ${INDEX_LIST_FILE}); do
        (
            log "  -> Rebuilding index: ${index}"
            # [Refactored 5] Added NOPARALLEL to reset index properties after REBUILD
            rebuild_sql="
            ALTER INDEX ${SCHEMA_NAME}.${index} REBUILD PARALLEL ${SQL_DOP};
            ALTER INDEX ${SCHEMA_NAME}.${index} NOPARALLEL;
            "
            run_sql_exec "${rebuild_sql}"
            log "  <- Rebuild & Noparallel complete: ${index}"
        ) &

        ((job_count++))
        if [ ${job_count} -ge ${JOB_CONCURRENCY} ]; then
            wait
            job_count=0
        fi
    done
    wait
fi
log "All index REBUILD operations completed."


# ---[ 3-4. Validate Index Status ]---
log "Step 4: Validating index status..."
run_sql_spool "SPOOL ${UNUSABLE_INDEX_LIST_FILE};
SELECT OWNER, INDEX_NAME, STATUS FROM DBA_INDEXES WHERE OWNER = '${SCHEMA_NAME}' AND STATUS = 'UNUSABLE';
SPOOL OFF;"

# -s checks if file exists and is not empty
if [ -s "${UNUSABLE_INDEX_LIST_FILE}" ]; then
    log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    log "ERROR: Found UNUSABLE indexes after rebuild. Please check."
    cat "${UNUSABLE_INDEX_LIST_FILE}" | tee -a ${LOG_FILE}
    log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
else
    log "All indexes are valid."
fi


# ---[ 3-5. Check for Invalid Objects ]---
log "Step 5: Checking for invalid objects..."
run_sql_spool "SPOOL ${INVALID_OBJECT_LIST_FILE};
SELECT OWNER, OBJECT_NAME, OBJECT_TYPE, STATUS FROM DBA_OBJECTS WHERE OWNER = '${SCHEMA_NAME}' AND STATUS = 'INVALID';
SPOOL OFF;"

if [ -s "${INVALID_OBJECT_LIST_FILE}" ]; then
    log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    log "WARNING: Found INVALID objects. Please review them."
    cat "${INVALID_OBJECT_LIST_FILE}" | tee -a ${LOG_FILE}
    log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
else
    log "No invalid objects found."
fi


# ---[ 3-6. Gather Schema Statistics ]---
log "Step 6: Gathering schema statistics..."
log "This may take a while..."
run_sql_exec "BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => '${SCHEMA_NAME}');
END;"
log "Schema statistics gathered successfully."


# ---[ 4. Finalization ]-------------------------------------------------------

log "Cleaning up temporary files..."
rm -f ${TABLE_LIST_FILE} ${INDEX_LIST_FILE} ${UNUSABLE_INDEX_LIST_FILE} ${INVALID_OBJECT_LIST_FILE}

log ">>>>> Table Reorg Script Finished Successfully. <<<<<"

exit 0
