#!/bin/bash

declare -a urls=(

# Rom URLs
"http://bigota.d.miui.com/7.9.27/miui_MIMIX2_7.9.27_544b5231d0_7.1.zip"
)

command -v dirname >/dev/null 2>&1 && cd "$(dirname "$0")"
for i in "${urls[@]}"
do
   bash extract.sh "$i" || exit 1
done
exit 0
