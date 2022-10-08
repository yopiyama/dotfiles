#!/bin/bash
ip addr show en0 | grep 'inet ' | sed -E 's/[[:space:]]*inet[[:space:]]//g' | sed -E 's/[[:space:]][a-z]*[[:space:]][a-z]*([0-9]+\.){3}[0-9]+.*//g'
