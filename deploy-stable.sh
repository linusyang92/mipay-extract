#!/bin/bash

declare -a urls=(

# Rom URLs
'http://bigota.d.miui.com/V9.5.2.0.ODECNFA/miui_MIMIX2_V9.5.2.0.ODECNFA_19d8e623ed_8.0.zip'

)

EU_VER=V9.5.2.0.ODECNFA
EU_VER_MIUI=v9.5
EU_VER_ANDR=8.0

declare -a eu_urls=(

# EU Rom URLs
"https://jaist.dl.sourceforge.net/project/xiaomi-eu-multilang-miui-roms/xiaomi.eu/MIUI-STABLE-RELEASES/MIUI${EU_VER_MIUI}/xiaomi.eu_multi_MIMix2_${EU_VER}_v9-${EU_VER_ANDR}.zip"

)

command -v dirname >/dev/null 2>&1 && cd "$(dirname "$0")"
if [[ "$1" == "rom" ]]; then
    base_dir=/sdcard/TWRP
    [ -z "$2" ] && VER="$EU_VER" || VER=$2
    [ -d "$base_dir" ] || base_dir=.
    aria2c_opts="--check-certificate=false --file-allocation=trunc -s10 -x10 -j10 -c"
    aria2c="aria2c $aria2c_opts -d $base_dir/$VER"
    for i in "${eu_urls[@]}"
    do
        $aria2c ${i//$EU_VER/$VER}
    done
    base_url="https://github.com/linusyang92/mipay-extract/releases/download/stable"
    $aria2c $base_url/eufix-MiMix2-$VER.zip
    $aria2c $base_url/mipay-MIMIX2-$VER.zip
    $aria2c $base_url/weather-MiMix2-$VER-mod.apk
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
