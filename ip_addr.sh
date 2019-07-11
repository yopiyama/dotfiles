#!/bin/bash
ip addr show en0 | grep 'inet ' | sed -E 's/[[:space:]]*inet[[:space:]]//g' | sed -E 's/\/[0-9]*[[:space:]][a-z]*[[:space:]][0-9]*\.[0-9]*\.[0-9]\.[0-9]*[[:space:]]en0//g'

