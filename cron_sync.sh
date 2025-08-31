#!/bin/bash
# Script de synchronisation automatique D1 vers MySQL

LOG_FILE="/home/yalala/vincent/cron/sync_d1.log"
SCRIPT_PATH="/home/yalala/vincent/cron/sync_d1_to_sql.py"

echo "========================================" >> $LOG_FILE
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Début synchronisation" >> $LOG_FILE

# Lancer la synchronisation
/usr/bin/python3 $SCRIPT_PATH >> $LOG_FILE 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fin synchronisation" >> $LOG_FILE