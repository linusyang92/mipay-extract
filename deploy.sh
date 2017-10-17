#!/bin/bash

declare -a urls=(

# Rom URLs
"http://bigota.d.miui.com/7.10.12/miui_MIMIX2_7.10.12_c1c2bdeca7_7.1.zip"

)

EU_VER=7.10.12

declare -a eu_urls=(

# EU Rom URLs
"https://jaist.dl.sourceforge.net/project/xiaomi-eu-multilang-miui-roms/xiaomi.eu/MIUI-WEEKLY-RELEASES/${EU_VER}/xiaomi.eu_multi_MIMix2_${EU_VER}_v9-7.1.zip"

)

command -v dirname >/dev/null 2>&1 && cd "$(dirname "$0")"
for i in "${urls[@]}"
do
   bash extract.sh "$i" || exit 1
done
for i in "${eu_urls[@]}"
do
   bash cleaner-fix.sh "$i" || exit 1
done
exit 0
