#!/bin/bash

declare -a urls=(

# Rom URLs
'http://bigota.d.miui.com/7.11.16/miui_MIMIX2_7.11.16_953b17eb74_7.1.zip'

)

EU_VER=7.11.16

declare -a eu_urls=(

# EU Rom URLs
"https://jaist.dl.sourceforge.net/project/xiaomi-eu-multilang-miui-roms/xiaomi.eu/MIUI-WEEKLY-RELEASES/${EU_VER}/xiaomi.eu_multi_MIMix2_${EU_VER}_v9-7.1.zip"

)

command -v dirname >/dev/null 2>&1 && cd "$(dirname "$0")"
if [[ "$1" == "rom" ]]; then
    aria2c_opts="--file-allocation trunc -s10 -x10 -j10 -c"
    aria2c="aria2c $aria2c_opts -d /sdcard/TWRP/rom/$EU_VER"
    for i in "${eu_urls[@]}"
    do
        $aria2c $i
    done
    base_url="https://github.com/linusyang92/mipay-extract/releases/download/$EU_VER"
    $aria2c $base_url/eufix-MiMix2-$EU_VER.zip
    $aria2c $base_url/mipay-MIMIX2-$EU_VER.zip
    $aria2c $base_url/weather-MiMix2-$EU_VER-mod.apk
    exit 0
fi
for i in "${urls[@]}"
do
   bash extract.sh "$i" || exit 1
done
[[ "$1" == "keep"  ]] || rm -rf miui-*/
for i in "${eu_urls[@]}"
do
   bash cleaner-fix.sh "$i" || exit 1
done
exit 0
