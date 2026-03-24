#!/bin/bash

# =================================================================================
# Oracle Partitioned Table/Index Reorg Parallel Execution Script
# =================================================================================

export ORACLE_SID="ORCL"
export ORACLE_HOME="/u01/app/oracle/product/19.3.0/dbhome_1"
export PATH=$ORACLE_HOME/bin:$PATH

SQLPLUS_USER="system"
SQLPLUS_PASS="oracle"
SQLPLUS_CONN="${SQLPLUS_USER}/${SQLPLUS_PASS}"

# ===[ Configuration ]=============================================================
SCHEMA_NAME="SH"
JOB_CONCURRENCY=2
SQL_DOP=4
# =================================================================================

LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/reorg_partition_execute_$(date +%Y%m%d_%H%M%S).log"
TABLE_PARTITION_LIST_FILE="${LOG_DIR}/reorg_table_partition_list.txt"
LOCAL_INDEX_PARTITION_LIST_FILE="${LOG_DIR}/reorg_local_index_partition_list.txt"
GLOBAL_INDEX_LIST_FILE="${LOG_DIR}/reorg_global_index_list.txt"

# --- Pre/Post check report files
PRE_REORG_STATS="${LOG_DIR}/pre_reorg_partition_stats.txt"
POST_REORG_STATS="${LOG_DIR}/post_reorg_partition_stats.txt"
REORG_COMPARISON_REPORT="${LOG_DIR}/reorg_partition_comparison_report.txt"

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

get_schema_stats() {
    local output_file=$1
    log "Capturing partitioned schema stats for ${SCHEMA_NAME} into ${output_file}..."
    local sql_query="SELECT TABLE_NAME || ',' || SUM(BLOCKS) FROM DBA_TAB_PARTITIONS WHERE TABLE_OWNER = '${SCHEMA_NAME}' GROUP BY TABLE_NAME ORDER BY TABLE_NAME;"
    run_sql_spool "${output_file}" "${sql_query}"
}

generate_comparison_report() {
    log "Generating comparison report..."
    
    (
        echo "==========================================================================================="
        echo " Partitioned Table Reorganization Comparison Report for Schema: ${SCHEMA_NAME}"
        echo "==========================================================================================="
        echo " "
        echo "HWM (High Water Mark) is represented by the 'BLOCKS' count."
        echo "A reduction in BLOCKS indicates successful HWM lowering and space reclamation."
        echo " "
        printf "%-35s | %-20s | %-20s | %-10s
" "TABLE_NAME" "TOTAL_BLOCKS (BEFORE)" "TOTAL_BLOCKS (AFTER)" "SAVED"
        echo "-------------------------------------------------------------------------------------------"
    ) > ${REORG_COMPARISON_REPORT}

    total_blocks_before=0
    total_blocks_after=0

    awk -F, '
        BEGIN { OFS="," }
        NR==FNR { before[$1] = $2; next }
        {
            if ($1 in before) {
                diff = before[$1] - $2;
                printf "%-35s | %-20s | %-20s | %-10s
", $1, before[$1], $2, diff;
                total_before += before[$1];
                total_after += $2;
            }
        }
        END {
            total_saved = total_before - total_after;
            printf "
-------------------------------------------------------------------------------------------
";
            printf "TOTALS
";
            printf "%-35s | %-20s | %-20s | %-10s
", " ", total_before, total_after, total_saved;
        }
    ' ${PRE_REORG_STATS} ${POST_REORG_STATS} >> ${REORG_COMPARISON_REPORT}
    
    log "Comparison report generated at ${REORG_COMPARISON_REPORT}"
    cat ${REORG_COMPARISON_REPORT}
}

# ---[ 0. Capture Pre-Reorg Stats ]---
log "Step 0: Capturing pre-reorganization statistics for partitioned tables..."
get_schema_stats "${PRE_REORG_STATS}"

# ---[ 1. Get List of Partitions and Indexes ]---
log "Step 1: Generating list of table partitions to reorganize..."
table_partition_list_sql="SELECT TABLE_NAME || ',' || PARTITION_NAME FROM DBA_TAB_PARTITIONS WHERE TABLE_OWNER = '${SCHEMA_NAME}';"
run_sql_spool "${TABLE_PARTITION_LIST_FILE}" "${table_partition_list_sql}"

log "Step 2: Generating list of local index partitions to rebuild..."
local_index_partition_list_sql="SELECT i.INDEX_NAME || ',' || i.PARTITION_NAME FROM DBA_IND_PARTITIONS i JOIN DBA_INDEXES ix ON (i.INDEX_OWNER = ix.OWNER AND i.INDEX_NAME = ix.INDEX_NAME) WHERE i.INDEX_OWNER = '${SCHEMA_NAME}' AND ix.PARTITIONED = 'YES';"
run_sql_spool "${LOCAL_INDEX_PARTITION_LIST_FILE}" "${local_index_partition_list_sql}"

log "Step 3: Generating list of global indexes to rebuild..."
# Global indexes are non-partitioned indexes on a partitioned table
global_index_list_sql="SELECT INDEX_NAME FROM DBA_INDEXES WHERE OWNER = '${SCHEMA_NAME}' AND PARTITIONED = 'NO' AND TABLE_NAME IN (SELECT DISTINCT TABLE_NAME FROM DBA_PART_TABLES WHERE OWNER = '${SCHEMA_NAME}');"
run_sql_spool "${GLOBAL_INDEX_LIST_FILE}" "${global_index_list_sql}"


if [ ! -s "${TABLE_PARTITION_LIST_FILE}" ]; then
    log "No partitioned tables found for schema ${SCHEMA_NAME}. Exiting."
    exit 0
fi

# ---[ 4. Reorganize Table Partitions ]---
log "Step 4: Reorganizing table partitions in parallel (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
job_count=0
while IFS=',' read -r table partition; do
    (
        log "  -> Moving partition: ${table}.${partition}"
        move_sql="
        ALTER TABLE ${SCHEMA_NAME}.${table} MOVE PARTITION ${partition} PARALLEL ${SQL_DOP};
        "
        run_sql_exec "${move_sql}"
        log "  <- Move complete: ${table}.${partition}"
    ) &

    ((job_count++))
    if [ ${job_count} -ge ${JOB_CONCURRENCY} ]; then
        wait
        job_count=0
    fi
done < "${TABLE_PARTITION_LIST_FILE}"
wait
log "All table partition MOVE operations completed."

# ---[ 5. Rebuild Local Index Partitions ]---
log "Step 5: Rebuilding local index partitions in parallel (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
job_count=0
while IFS=',' read -r index partition; do
    (
        log "  -> Rebuilding local index partition: ${index}.${partition}"
        rebuild_sql="
        ALTER INDEX ${SCHEMA_NAME}.${index} REBUILD PARTITION ${partition} PARALLEL ${SQL_DOP};
        "
        run_sql_exec "${rebuild_sql}"
        log "  <- Rebuild complete: ${index}.${partition}"
    ) &

    ((job_count++))
    if [ ${job_count} -ge ${JOB_CONCURRENCY} ]; then
        wait
        job_count=0
    fi
done < "${LOCAL_INDEX_PARTITION_LIST_FILE}"
wait
log "All local index partition REBUILD operations completed."

# ---[ 6. Rebuild Global Indexes ]---
log "Step 6: Rebuilding global indexes in parallel (Job Concurrency=${JOB_CONCURRENCY}, SQL DOP=${SQL_DOP})..."
job_count=0
for index in $(cat ${GLOBAL_INDEX_LIST_FILE}); do
    (
        log "  -> Rebuilding global index: ${index}"
        rebuild_sql="
        ALTER INDEX ${SCHEMA_NAME}.${index} REBUILD PARALLEL ${SQL_DOP};
        ALTER INDEX ${SCHEMA_NAME}.${index} NOPARALLEL;
        "
        run_sql_exec "${rebuild_sql}"
        log "  <- Rebuild complete: ${index}"
    ) &

    ((job_count++))
    if [ ${job_count} -ge ${JOB_CONCURRENCY} ]; then
        wait
        job_count=0
    fi
done
wait
log "All global index REBUILD operations completed."

# ---[ 7. Set NOPARALLEL for tables and indexes ]---
log "Step 7: Setting NOPARALLEL attribute on all processed tables and indexes..."
# Tables
for table in $(awk -F, '{print $1}' ${TABLE_PARTITION_LIST_FILE} | sort -u); do
    run_sql_exec "ALTER TABLE ${SCHEMA_NAME}.${table} NOPARALLEL;"
done
# Indexes
for index in $(awk -F, '{print $1}' ${LOCAL_INDEX_PARTITION_LIST_FILE} | sort -u); do
    run_sql_exec "ALTER INDEX ${SCHEMA_NAME}.${index} NOPARALLEL;"
done
# Global Indexes already handled in step 6
log "NOPARALLEL setting complete."

# ---[ 8. Gather Statistics ]---
log "Step 8: Gathering fresh statistics for schema ${SCHEMA_NAME}..."
stats_sql="EXEC DBMS_STATS.GATHER_SCHEMA_STATS(ownname => '${SCHEMA_NAME}', estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE, method_opt => 'FOR ALL COLUMNS SIZE AUTO', degree => ${SQL_DOP}, cascade => TRUE);"
run_sql_exec "${stats_sql}"
log "Schema statistics gathering complete."

# ---[ 9. Capture Post-Reorg Stats and Compare ]---
log "Step 9: Capturing post-reorganization statistics..."
get_schema_stats "${POST_REORG_STATS}"

log "Step 10: Generating comparison report..."
generate_comparison_report

log "Partitioned table reorganization script finished successfully."
log "Please check the full log at: ${LOG_FILE}"
log "Comparison report is available at: ${REORG_COMPARISON_REPORT}"

exit 0
