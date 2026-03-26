#!/bin/bash

# =============================================================================
# Oracle LOB Reorganization Script
# =============================================================================
#
# Description:
#   This script orchestrates the reorganization of LOB (Large Object) segments
#   for a given schema. It first generates the necessary SQL commands and then
#   executes them.
#
# Usage:
#   1. Configure the environment variables below.
#   2. Grant execute permission: chmod +x reorg_lob_execute.sh
#   3. Run the script: ./reorg_lob_execute.sh
#
# =============================================================================

# ---[ 1. User Configuration ]-------------------------------------------------
# !! Set your environment and connection details !!
export ORACLE_SID="ORCL"
export ORACLE_HOME="/u01/app/oracle/product/19c/dbhome_1" # Your Oracle Home
export PATH=$ORACLE_HOME/bin:$PATH

# -- Connection Details
SQLPLUS_USER="system"
SQLPLUS_PASS="your_password" # Use the actual password
SQLPLUS_CONN="${SQLPLUS_USER}/${SQLPLUS_PASS}"

# -- Target Schema and Parallelism
SCHEMA_NAME="SH"
DOP=4 # Parallelism level, adjust based on CPU resources
# -----------------------------------------------------------------------------

# ---[ 2. Script Setup ]-------------------------------------------------------
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/reorg_lob_execute_$(date +%Y%m%d_%H%M%S).log"
GENERATED_SQL_FILE="_generated_lob_reorg_commands.sql"

# Create log directory if it doesn't exist
mkdir -p ${LOG_DIR}
# -----------------------------------------------------------------------------

# ---[ 3. Functions ]----------------------------------------------------------
# Function to log messages to both console and log file
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to execute a SQL script and handle errors
run_sql_script() {
    local sql_script_path=$1
    log "Executing SQL script: ${sql_script_path}..."
    sqlplus -S "${SQLPLUS_CONN}" @"${sql_script_path}" >> ${LOG_FILE} 2>&1
    
    if [ $? -ne 0 ]; then
        log "ERROR: SQL script '${sql_script_path}' failed to execute."
        log "Check ${LOG_FILE} for details."
        exit 1
    fi
    log "Successfully executed ${sql_script_path}."
}
# -----------------------------------------------------------------------------


# ---[ 4. Main Execution ]-----------------------------------------------------
log "======= Starting LOB Reorganization for Schema: ${SCHEMA_NAME} ======="

# --- Step 1: Generate Reorganization Commands ---
log "Step 1: Generating LOB reorganization commands..."
sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;
@generate_lob_reorg_sql.sql ${SCHEMA_NAME}
EOF

if [ $? -ne 0 ] || [ ! -s "${GENERATED_SQL_FILE}" ]; then
    log "ERROR: Failed to generate LOB reorg commands. Check log for details."
    exit 1
fi
log "Successfully generated commands in ${GENERATED_SQL_FILE}."

# --- Step 2: Execute Generated Commands ---
log "Step 2: Executing the generated LOB reorganization and index rebuild commands..."
sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
WHENEVER SQLERROR EXIT 1 ROLLBACK;
SET FEEDBACK ON
SET TIMING ON

@${GENERATED_SQL_FILE}

EXIT;
EOF

if [ $? -ne 0 ]; then
    log "ERROR: An error occurred during LOB reorganization. Check the log for details."
    exit 1
fi
log "LOB reorganization and index rebuilds completed successfully."

# --- Step 3: Gather Statistics on Affected Tables ---
log "Step 3: Gathering statistics for tables with reorganized LOBs..."
AFFECTED_TABLES_SQL="SET HEADING OFF FEEDBACK OFF PAGESIZE 0; SELECT DISTINCT table_name FROM dba_lobs WHERE owner = '${SCHEMA_NAME}';"
AFFECTED_TABLES=$(sqlplus -S "${SQLPLUS_CONN}" <<< "${AFFECTED_TABLES_SQL}")

for table in ${AFFECTED_TABLES}; do
    log "  -> Gathering stats for table: ${table}"
    sqlplus -S "${SQLPLUS_CONN}" <<EOF >> ${LOG_FILE} 2>&1
    WHENEVER SQLERROR CONTINUE;
    EXEC DBMS_STATS.GATHER_TABLE_STATS(ownname => '${SCHEMA_NAME}', tabname => '${table}', estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE, method_opt => 'FOR ALL COLUMNS SIZE AUTO', degree => ${DOP}, cascade => TRUE);
EOF
done
log "Table statistics gathering complete."


log "======= LOB Reorganization Script Finished Successfully ======="
log "Full log is available at: ${LOG_FILE}"
# -----------------------------------------------------------------------------

exit 0
