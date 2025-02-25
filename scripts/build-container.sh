#!/usr/bin/env bash

set -euo pipefail

docker build -t taskmatter-dev -f Dockerfile.dev
