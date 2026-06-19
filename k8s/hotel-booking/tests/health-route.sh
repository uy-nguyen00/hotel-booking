#!/usr/bin/env bash
set -euo pipefail

rendered="$(helm template hotel-booking k8s/hotel-booking --set images.tag=test)"
grep -A8 'path: /health' <<<"$rendered" | grep -q 'name: auth-http'
grep -A8 'path: /health' <<<"$rendered" | grep -q 'number: 3003'
