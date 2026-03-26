#!/bin/bash

# =============================================================================
# Oracle Table/Index Reorg Parallel Execution Script (Refactored)
# =============================================================================

#export ORACLE_SID="ORCL"
#export ORACLE_HOME="/u01/app/oracle/product/19.3.0/dbhome_1"
#export PATH=$ORACLE_HOME/bin:$PATH

#SQLPLUS_USER="system"
#SQLPLUS_PASS="oracle"
#SQLPLUS_CONN="${SQLPLUS_USER}/${SQLPLUS_PASS}"

SQLPLUS_CONN=" / as  sysdba"

# ===[ Configuration ]=========================================================
export SCHEMA_NAME="SH2"
export JOB_CONCURRENCY=2
export SQL_DOP=2
# =============================================================================

LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/reorg_execute_$(date +%Y%m%d_%H%M%S).log"
TABLE_LIST_FILE="${LOG_DIR}/reorg_table_list.txt"
INDEX_LIST_FILE="${LOG_DIR}/reorg_index_list.txt"

# --- Pre/Post check report files
PRE_REORG_STATS="${LOG_DIR}/pre_reorg_stats.txt"
POST_REORG_STATS="${LOG_DIR}/post_reorg_stats.txt"
REORG_COMPARISON_REPORT="${LOG_DIR}/reorg_comparison_report.txt"

# Create log directory if it doesn't exist
mkdir -p ${LOG_DIR}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

run_sql_spool() {
    sqlplus -S "${SQLPLUS_CONN}" <<EOF
SET HEADING OFF FEEDBACK OFF VERIFY OFF TERMOUT OFF LINES 200 PAGESIZE 0 TRIMSPOOL ON ECHO OFF
SPOOL $1;
$2
SPOOL OFF;
EXIT;
EOF
}

run_sql_exec() {
    sqlplus -S "${SQLPLUS_CONN}" <<EOF
SET FEEDBACK OFF VERIFY OFF SERVEROUTPUT ON
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;
$1
/
EXIT;
EOF
}

# [NEW] Function to get schema stats (Blocks and HWM)
get_schema_stats() {
    local output_file=$1
    log "Capturing schema stats for ${SCHEMA_NAME} into ${output_file}..."
    local sql_query="SELECT TABLE_NAME || ',' || BLOCKS || ',' || EMPTY_BLOCKS FROM DBA_TABLES WHERE OWNER = '${SCHEMA_NAME}' AND TABLE_NAME IN (SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = '${SCHEMA_NAME}' AND PARTITIONED = 'NO' AND IOT_TYPE IS NULL AND TEMPORARY = 'N' AND NESTED = 'NO' AND SECONDARY = 'N' AND CLUSTER_NAME IS NULL AND TABLE_NAME NOT LIKE 'AQ\$%' AND TABLE_NAME NOT LIKE 'MLOG\$%' AND TABLE_NAME NOT LIKE 'RUPD\$%' AND DROPPED = 'NO') ORDER BY TABLE_NAME;"
    run_sql_spool "${output_file}" "${sql_query}"
}

# [NEW] Function to compare pre and post stats
generate_comparison_report() {
    log "Generating comparison report..."
    
    (
        echo "==========================================================================================="
        echo " Reorganization Comparison Report for Schema: ${SCHEMA_NAME}"
        echo "==========================================================================================="
        echo " "
        echo "HWM (High Water Mark) is represented by the 'BLOCKS' count."
        echo "A reduction in BLOCKS indicates successful HWM lowering and space reclamation."
        echo " "
        printf "%-35s | %-20s | %-20s | %-10s\n" "TABLE_NAME" "BLOCKS (BEFORE)" "BLOCKS (AFTER)" "SAVED"
        echo "-------------------------------------------------------------------------------------------"
    ) > ${REORG_COMPARISON_REPORT}

    total_blocks_before=0
    total_blocks_after=0

    # Use awk to join files and calculate differences
    awk -F, '
        BEGIN { OFS="," }
        NR==FNR { before[$1] = $2; next }
        {
            if ($1 in before) {
                diff = before[$1] - $2;
                printf "%-35s | %-20s | %-20s | %-10s\n", $1, before[$1], $2, diff;
                total_before += before[$1];
                total_after += $2;
            }
        }
        END {
            total_saved = total_before - total_after;
            printf "\n-------------------------------------------------------------------------------------------\n";
            printf "TOTALS\n";
            printf "%-35s | %-20s | %-20s | %-10s\n", " ", total_before, total_after, total_saved;
        }
    ' ${PRE_REORG_STATS} ${POST_REORG_STATS} >> ${REORG_COMPARISON_REPORT}
    
    log "Comparison report generated at ${REORG_COMPARISON_REPORT}"
    cat ${REORG_COMPARISON_REPORT}
}


# ---[ 0. Capture Pre-Reorg Stats ]---
log "Step 0: Capturing pre-reorganization statistics..."
get_schema_stats "${PRE_REORG_STATS}"

# ---[ 1. Get List of Tables and Indexes ]---
log "Step 1: Generating list of tables to reorganize..."
table_list_sql="SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = '${SCHEMA_NAME}' AND PARTITIONED = 'NO' AND IOT_TYPE IS NULL AND TEMPORARY = 'N' AND NESTED = 'NO' AND SECONDARY = 'N' AND CLUSTER_NAME IS NULL AND TABLE_NAME NOT LIKE 'AQ\$%' AND TABLE_NAME NOT LIKE 'MLOG\$%' AND TABLE_NAME NOT LIKE 'RUPD\$%' AND DROPPED = 'NO';"
run_sql_spool "${TABLE_LIST_FILE}" "${table_list_sql}"

log "Step 2: Generating list of indexes to rebuild..."
index_list_sql="SELECT INDEX_NAME FROM DBA_INDEXES WHERE OWNER = '${SCHEMA_NAME}' AND INDEX_TYPE = 'NORMAL' AND TABLE_NAME IN (SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = '${SCHEMA_NAME}' AND PARTITIONED = 'NO' AND IOT_TYPE IS NULL AND TEMPORARY = 'N' AND NESTED = 'NO' AND SECONDARY = 'N' AND CLUSTER_NAME IS NULL AND TABLE_NAME NOT LIKE 'AQ\$%' AND TABLE_NAME NOT LIKE 'MLOG\$%' AND TABLE_NAME NOT LIKE 'RUPD\$%' AND DROPPED = 'NO');"
run_sql_spool "${INDEX_LIST_FILE}" "${index_list_sql}"

if [ ! -s "${TABLE_LIST_FILE}" ]; then
    log "No tables found for schema ${SCHEMA_NAME}. Exiting."
    exit 0
fi

# ---[ 3. Reorganize Tables ]---
log "Step 3: Reorganizing tables in parallel (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
job_count=0
for table in $(cat ${TABLE_LIST_FILE}); do
    (
        log "  -> Moving table: ${table}"
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


# ---[ 4. Rebuild Indexes ]---
log "Step 4: Rebuilding indexes in parallel (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
job_count=0
for index in $(cat ${INDEX_LIST_FILE}); do
    (
        log "  -> Rebuilding index: ${index}"
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
log "All index REBUILD operations completed."

# ---[ 5. Gather Statistics ]---
log "Step 5: Gathering fresh statistics for schema ${SCHEMA_NAME}..."
stats_sql="EXEC DBMS_STATS.GATHER_SCHEMA_STATS(ownname => '${SCHEMA_NAME}', estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE, method_opt => 'FOR ALL COLUMNS SIZE AUTO', degree => DBMS_STATS.AUTO_DEGREE, cascade => TRUE);"
run_sql_exec "${stats_sql}"
log "Schema statistics gathering complete."

# ---[ 6. Capture Post-Reorg Stats and Compare ]---
log "Step 6: Capturing post-reorganization statistics..."
get_schema_stats "${POST_REORG_STATS}"

log "Step 7: Generating comparison report..."
generate_comparison_report

log "Reorganization script finished successfully."
log "Please check the full log at: ${LOG_FILE}"
log "Comparison report is available at: ${REORG_COMPARISON_REPORT}"

exit 0
