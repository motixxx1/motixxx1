#!/bin/sh
# ProMarket server — Linux / macOS / Raspberry Pi.  Run:  ./start.sh
cd "$(dirname "$0")" || exit 1
if [ -x ./node/bin/node ]; then NODE=./node/bin/node; else NODE=node; fi
if ! "$NODE" -e "process.exit(+process.versions.node.split('.')[0] >= 20 ? 0 : 1)" 2>/dev/null; then
  echo "Node.js 20+ is required. Download the package that includes Node (linux-x64 / linux-arm64), or install Node 22."
  exit 1
fi
exec "$NODE" src/server.js
