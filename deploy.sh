#!/bin/bash

declare -a urls=(

# Rom URLs
"http://bigota.d.miui.com/7.9.22/miui_MIMIX2_7.9.22_85b021fe33_7.1.zip"

)

command -v dirname >/dev/null 2>&1 && cd "$(dirname "$0")"
for i in "${urls[@]}"
do
   bash extract.sh "$i" || break
done
exit 0
