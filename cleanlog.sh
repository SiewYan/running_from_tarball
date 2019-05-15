#!/bin/bash

set -e 
echo "before, `(du -h ./logs)`"
find ./logs -maxdepth 1 -name "*.out" -print0 | xargs -0 rm
find ./logs -maxdepth 1 -name "*.err" -print0 | xargs -0 rm
find ./logs -maxdepth 1 -name "*.log" -print0 | xargs -0 rm
echo "after, `(du -h ./logs)`"