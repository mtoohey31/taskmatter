#!/usr/bin/env bash

set -euo pipefail

if test -z "$(docker ps --format "{{.Names}}")"; then
  docker run --rm --name taskmatter-dev -it -v $PWD:/usr/src/taskmatter taskmatter-dev
else
  docker exec -it taskmatter-dev /bin/bash
fi
