#!/bin/bash
echo "=== KONTROLA DISKU A INODOV ==="
df -h
df -i

echo -e "\n=== KONTROLA KERNEL LOGOV (Hľadáme I/O chyby) ==="
dmesg | tail -n 20 | grep -Ei "error|critical|io|sda"
