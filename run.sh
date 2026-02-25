#!/bin/bash
set -e

SCRIPT_DIR="/scripts"

log_section() { echo ""; echo "═══════════════════════════════════════════════════════"; echo "  🔷 $1"; echo "═══════════════════════════════════════════════════════"; }

log_section "SPÚŠŤAM INŠTALÁCIU"
echo "📅 $(date)"

bash $SCRIPT_DIR/01-kubernetes.sh
bash $SCRIPT_DIR/02-traefik.sh
bash $SCRIPT_DIR/03-flux.sh
bash $SCRIPT_DIR/04-wait-and-fix.sh
bash $SCRIPT_DIR/05-monitoring.sh
bash $SCRIPT_DIR/06-health-check.sh

log_section "INŠTALÁCIA DOKONČENÁ"
echo "📅 $(date)"
