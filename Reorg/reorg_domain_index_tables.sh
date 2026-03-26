#!/bin/bash

# =============================================================================
# Oracle Domain Index Table Reorganization Script
# =============================================================================
#
# Description:
#   This script finds tables with Domain (e.g., Oracle Text) indexes, 
#   reorganizes them, rebuilds the indexes, captures before/after block 
#   counts, and generates a comparison report.
#
# Usage:
#   1. Configure the environment variables below.
#   2. Grant execute permission: chmod +x reorg_domain_index_tables.sh
#   3. Run the script: ./reorg_domain_index_tables.sh
#
# =============================================================================

# ---[ 1. User Configuration ]-------------------------------------------------
# !! Set your environment and connection details !!
#export ORACLE_SID="ORCL"
#export ORACLE_HOME="/u01/app/oracle/product/19c/dbhome_1" # Your Oracle Home
#export PATH=$ORACLE_HOME/bin:$PATH

# -- Connection Details
#SQLPLUS_USER="system"
#SQLPLUS_PASS="your_password" # Use the actual password
#SQLPLUS_CONN="${SQLPLUS_USER}/${SQLPLUS_PASS}"

SQLPLUS_CONN=" / as sysdba"


# -- Target Schema and Parallelism
SCHEMA_NAME="SH2"
DOP=2 # Parallelism level, adjust based on CPU resources
# -----------------------------------------------------------------------------

# ---[ 2. Script Setup ]-------------------------------------------------------
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/reorg_domain_tables_execute_$(date +%Y%m%d_%H%M%S).log"
TABLES_TO_REORG_LIST_FILE="${LOG_DIR}/reorg_domain_index_tables_list.txt"
DOMAIN_INDEXES_LIST_FILE="${LOG_DIR}/reorg_domain_indexes_list.txt"

# --- Pre/Post check report files
PRE_REORG_STATS="${LOG_DIR}/pre_reorg_domain_table_stats.txt"
POST_REORG_STATS="${LOG_DIR}/post_reorg_domain_table_stats.txt"
REORG_COMPARISON_REPORT="${LOG_DIR}/reorg_domain_table_comparison_report.txt"

# Create log directory if it doesn't exist
mkdir -p ${LOG_DIR}
# -----------------------------------------------------------------------------

# ---[ 3. Functions ]----------------------------------------------------------
# Function to log messages to both console and log file
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to spool SQL query results to a file
run_sql_spool() {
    local output_file=$1
    local sql_query=$2
    sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
SET HEADING OFF FEEDBACK OFF VERIFY OFF TERMOUT OFF LINES 200 PAGESIZE 0 TRIMSPOOL ON ECHO OFF
SPOOL ${output_file};
${sql_query}
SPOOL OFF;
EXIT;
EOF
}

get_table_stats() {
    local output_file=$1
    log "Capturing Domain Index table stats for ${SCHEMA_NAME} into ${output_file}..."
    local sql_query="
    SELECT T.TABLE_NAME || ',' || T.BLOCKS
    FROM DBA_TABLES T
    WHERE T.OWNER = UPPER('${SCHEMA_NAME}')
      AND T.TABLE_NAME IN (SELECT DISTINCT TABLE_NAME FROM DBA_INDEXES WHERE OWNER = UPPER('${SCHEMA_NAME}') AND INDEX_TYPE = 'DOMAIN')
    ORDER BY T.TABLE_NAME;"
    run_sql_spool "${output_file}" "${sql_query}"
}

generate_comparison_report() {
    log "Generating comparison report..."
    
    (
        echo "==========================================================================================="
        echo "    Domain Index Table Reorganization Comparison Report for Schema: ${SCHEMA_NAME}"
        echo "==========================================================================================="
        echo " "
        echo "HWM (High Water Mark) is represented by the 'BLOCKS' count for the table segment."
        echo "A reduction in BLOCKS indicates successful HWM lowering and space reclamation."
        echo " "
        printf "%-35s | %-20s | %-20s | %-10s
" "TABLE_NAME" "TOTAL_BLOCKS (BEFORE)" "TOTAL_BLOCKS (AFTER)" "SAVED"
        echo "-------------------------------------------------------------------------------------------"
    ) > ${REORG_COMPARISON_REPORT}

    total_blocks_before=0
    total_blocks_after=0

    local awk_script='
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
	    printf "-------------------------------------------------------------------------------------------\n";
	    printf "%-35s | %-20s | %-20s | %-10s\n", "TOTALS", total_before, total_after, total_saved;
	}
'
    awk -F, "${awk_script}" ${PRE_REORG_STATS} ${POST_REORG_STATS} >> ${REORG_COMPARISON_REPORT}    

    log "Comparison report generated at ${REORG_COMPARISON_REPORT}"
    cat ${REORG_COMPARISON_REPORT} | tee -a ${LOG_FILE}
}
# -----------------------------------------------------------------------------


# ---[ 4. Main Execution ]-----------------------------------------------------
log "======= Starting Domain Index Table Reorganization for Schema: ${SCHEMA_NAME} ======="

# --- Step 0: Get list of tables and indexes to process ---
log "Step 0: Generating list of tables with Domain Indexes to reorganize..."
tables_sql="SELECT DISTINCT table_name FROM dba_indexes WHERE owner = UPPER('${SCHEMA_NAME}') AND index_type = 'DOMAIN';"
run_sql_spool "${TABLES_TO_REORG_LIST_FILE}" "${tables_sql}"

log "Step 0: Generating list of Domain Indexes to rebuild..."
indexes_sql="SELECT index_name FROM dba_indexes WHERE owner = UPPER('${SCHEMA_NAME}') AND index_type = 'DOMAIN';"
run_sql_spool "${DOMAIN_INDEXES_LIST_FILE}" "${indexes_sql}"


if [ ! -s "${TABLES_TO_REORG_LIST_FILE}" ]; then
    log "No tables with Domain Indexes found for schema ${SCHEMA_NAME}. Exiting."
    exit 0
fi

# --- Step 1: Capture Pre-Reorg Stats ---
log "Step 1: Capturing pre-reorganization statistics..."
get_table_stats "${PRE_REORG_STATS}"

# --- Step 2: Reorganize Tables ---
log "Step 2: Reorganizing tables..."
for table in $(cat ${TABLES_TO_REORG_LIST_FILE}); do
    log "  -> Moving table: ${table}"
    sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
    WHENEVER SQLERROR EXIT 1 ROLLBACK;
    ALTER TABLE ${SCHEMA_NAME}.${table} MOVE PARALLEL ${DOP};
    ALTER TABLE ${SCHEMA_NAME}.${table} NOPARALLEL;
EOF
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to move table ${table}. Check log for details."
        exit 1
    fi
done
log "Table reorganization completed successfully."


# --- Step 3: Rebuild All Domain (Text) Indexes ---
log "Step 3: Rebuilding all Domain (e.g., Oracle Text) indexes..."
for index in $(cat ${DOMAIN_INDEXES_LIST_FILE}); do
    log "  -> Rebuilding Domain index: ${index}"
    sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
    WHENEVER SQLERROR CONTINUE;
    ALTER INDEX ${SCHEMA_NAME}.${index} REBUILD;
EOF
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to rebuild Domain index ${index}. Check the log for details."
    fi
done
log "Domain index rebuild process complete."


# --- Step 4: Gather Statistics on Affected Tables ---
log "Step 4: Gathering statistics for reorganized tables..."
for table in $(cat ${TABLES_TO_REORG_LIST_FILE}); do
    log "  -> Gathering stats for table: ${table}"
    sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
    WHENEVER SQLERROR CONTINUE;
    BEGIN
      DBMS_STATS.GATHER_TABLE_STATS(ownname => UPPER('${SCHEMA_NAME}'),
                                  tabname => '${table}',
                                  estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                  method_opt => 'FOR ALL COLUMNS SIZE AUTO',
                                  degree => ${DOP},
                                  cascade => TRUE);
    END;
    /
EOF
done
log "Table statistics gathering complete."

# --- Step 5: Capture Post-Reorg Stats ---
log "Step 5: Capturing post-reorganization statistics..."
get_table_stats "${POST_REORG_STATS}"

# --- Step 6: Generate Comparison Report ---
log "Step 6: Generating comparison report..."
generate_comparison_report


log "======= Domain Index Table Reorganization Script Finished Successfully ======="
log "Full log is available at: ${LOG_FILE}"
# -----------------------------------------------------------------------------

exit 0
