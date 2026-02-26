#!/bin/bash
POD_NAME=$(kubectl get pods -n lamp -l app=apache-php --sort-by=.metadata.creationTimestamp | tail -n 1 | awk '{print $1}')
echo "--- Events for Pod: $POD_NAME ---"
kubectl get event -n lamp --field-selector involvedObject.name=$POD_NAME
