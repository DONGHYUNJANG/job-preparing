export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export SQLPATH=/home/oracle/MyOraSql

alias sys="sqlplus / as sysdba"
alias adrci="adrci"
alias dbs="cd $ORACLE_HOME/dbs"
alias oh="cd $ORACLE_HOME"
alias ll="ls -ll"
alias ld="ls -ld"
alias net='cd /u01/app/oracle/product/19.3.0/dbhome_1/network/admin/'
alias trace='cd /u01/app/oracle/diag/rdbms/$(echo $ORACLE_SID | tr '[:upper:]' '[:lower:]')/$(echo $ORACLE_SID | tr '[:lower:]' '[:upper:]')/trace/'
alias alert='tail -f /u01/app/oracle/diag/rdbms/$(echo $ORACLE_SID | tr '[:upper:]' '[:lower:]')/$(echo $ORACLE_SID | tr '[:lower:]' '[:upper:]')/trace/al*'
alias pro='cat /home/oracle/.bash_profile'
alias dbid='$ORACLE_BASE/admin/$ORACLE_SID/adump | grep -H "DBID" *.aud'