#!/bin/bash
set -euo pipefail
EXTERNAL_IP="34.89.208.249.nip.io"
echo "🔍 Spúšťam smoke testy..."
echo -n "GraphQL: "
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://graphql.$EXTERNAL_IP -H "Content-Type: application/json" -d '{"query":"{ products { id } }"}' | grep -q 200 || exit 1
echo -n "API products: "
curl -s -o /dev/null -w "%{http_code}\n" http://api.$EXTERNAL_IP/products | grep -q 200 || exit 1
echo -n "Frontend: "
curl -s -o /dev/null -w "%{http_code}\n" http://shop.$EXTERNAL_IP | grep -q 200 || exit 1
echo "✅ Všetky smoke testy prešli."
