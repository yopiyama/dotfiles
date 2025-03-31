#!/bin/bash
ip addr show en0 | grep 'inet ' | gsed -E 's/\s+inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\/[0-9]+\s+.*$/\1/g'
