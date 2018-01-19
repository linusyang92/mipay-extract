#!/bin/bash

cd "$(dirname "$0")"

mipay_apps="Calendar SecurityCenter"

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python2.7 $tool_dir/sdat2img.py"
patchmethod="python2.7 $tool_dir/patchmethod.py"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.2.1.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.2.1.jar"
keypass="--ks-pass pass:testkey --key-pass pass:testkey"
sign="java -Xmx${heapsize}m -jar $tool_dir/apksigner.jar sign \
      --ks $tool_dir/testkey.jks $keypass"
aria2c_opts="--check-certificate=false --file-allocation=trunc -s10 -x10 -j10 -c"
aria2c="aria2c $aria2c_opts"
sed="sed"

exists() {
  command -v "$1" >/dev/null 2>&1
}

abort() {
    echo "--> $1"
    echo "--> abort"
    exit 1
}

check() {
    for b in $@; do
        exists $b || abort "Missing $b"
    done
}

check java python2.7

if [[ "$OSTYPE" == "darwin"* ]]; then
    aapt="$tool_dir/darwin/aapt"
    zipalign="$tool_dir/darwin/zipalign"
    sevenzip="$tool_dir/darwin/7za"
    aria2c="$tool_dir/darwin/aria2c $aria2c_opts"
    sed="$tool_dir/darwin/gsed"
else
    exists aapt && aapt="aapt" || aapt="$tool_dir/aapt"
    exists zipalign && zipalign="zipalign" || zipalign="$tool_dir/zipalign"
    exists 7z && sevenzip="7z" || sevenzip="$tool_dir/7za"
    exists aria2c || aria2c="$tool_dir/aria2c $aria2c_opts"
    if [[ "$OSTYPE" == "cygwin"* ]]; then
        sdat2img="python2.7 ../tools/sdat2img.py"
        patchmethod="python2.7 ../../tools/patchmethod.py"
        smali="java -Xmx${heapsize}m -jar ../../tools/smali-2.2.1.jar"
        baksmali="java -Xmx${heapsize}m -jar ../../tools/baksmali-2.2.1.jar"
        sign="java -Xmx${heapsize}m -jar ../../tools/apksigner.jar sign \
              --ks ../../tools/testkey.jks $keypass"
    fi
fi

clean() {
    [ -e "$1" ] && rm -R "$1"
    echo "--> abort"
    echo "--> clean $(basename $1)"
    exit 1
}

pushd() {
    command pushd "$@" > /dev/null
}

popd() {
    command popd "$@" > /dev/null
}

deodex() {
    app=$2
    base_dir="$1"
    arch=$3
    deoappdir=system/$4
    deoarch=oat/$arch
    framedir=system/framework
    pushd "$base_dir"
    api=$(grep "ro.build.version.sdk" system/build.prop | cut -d"=" -f2)
    if [ -z "$api" ]; then
        api=25
    fi
    file_list="$($sevenzip l "$deoappdir/$app/$app.apk")"
    if [[ "$file_list" == *"classes.dex"* ]]; then
        echo "--> decompiling $app..."
            dexclass="classes.dex"
            $baksmali d $deoappdir/$app/$app.apk -o $deoappdir/$app/smali || return 1
            if [[ "$app" == "Calendar" ]]; then
                $patchmethod $deoappdir/$app/smali/com/miui/calendar/util/LocalizationUtils.smali \
                             showsDayDiff showsLunarDate showsWidgetHoliday showsWorkFreeDay \
                             -isMainlandChina -isGreaterChina || return 1
            fi

            if [[ "$app" == "Weather" ]]; then
                find $deoappdir/$app/smali -type f -iname "*.smali" | while read i; do
                    if grep -q 'Lmiui/os/Build;->IS_INTERNATIONAL_BUILD' $i; then
                        $sed -i 's|sget-boolean v\([0-9]\+\), Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z|const/4 v\1, 0x0|g' "$i" \
                          || return 1
                        if grep -q 'Lmiui/os/Build;->IS_INTERNATIONAL_BUILD' $i; then
                            echo "----> ! failed to patch: $(basename $i)"
                        else
                            echo "----> patched smali: $(basename $i)"
                        fi
                    fi
                done
                i="$deoappdir/$app/smali/com/miui/weather2/tools/ToolUtils.smali"
                if [ -f "$i" ]; then
                    $patchmethod "$i" -canRequestCommercial -canRequestCommercialInfo || return 1
                fi
            fi

            if [[ "$app" == "SecurityCenter" ]]; then
                i="$deoappdir/$app/smali/com/miui/antivirus/activity/SettingsActivity.smali"
                $sed -i 's|sget-boolean v\([0-9]\+\), Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z|const/4 v\1, 0x0|g' "$i" \
                  || return 1
                if grep -q 'Lmiui/os/Build;->IS_INTERNATIONAL_BUILD' $i; then
                    echo "----> ! failed to patch: $(basename $i)"
                else
                    echo "----> patched smali: $(basename $i)"
                fi
            fi

            $smali assemble -a $api $deoappdir/$app/smali -o $deoappdir/$app/$dexclass || return 1
            rm -rf $deoappdir/$app/smali
            if [[ ! -f $deoappdir/$app/$dexclass ]]; then
                echo "----> failed to baksmali: $deoappdir/$app/$dexclass"
                continue
            fi
        apkfile=$deoappdir/$app/$app.apk
        $sevenzip d "$apkfile" $dexclass >/dev/null
        $aapt add -fk $apkfile $deoappdir/$app/classes.dex || return 1
        rm -f $deoappdir/$app/classes.dex
        $zipalign -f 4 $apkfile $apkfile-2 >/dev/null 2>&1
        mv $apkfile-2 $apkfile
        if [[ "$app" == "Weather" ]]; then
            if $sign $apkfile; then
                echo "----> signed: $app.apk"
            else
                echo "----> cannot sign $app.apk"
                return 1
            fi
        fi
        if ! [ -d $deoappdir/$app/lib ]; then
            $sevenzip x -o$deoappdir/$app $apkfile lib >/dev/null
            if [ -d $deoappdir/$app/lib ]; then
                pushd $deoappdir/$app/lib
                [ -d armeabi-v7a ] && mv armeabi-v7a arm
                [ -d arm64-v8a ] && mv arm64-v8a arm64
                popd
            fi
        fi
    fi
    popd
    return 0
}

extract() {
    model=$1
    ver=$2
    file=$3
    apps=$4
    dir=miuieu-$model-$ver
    img=$dir-system.img

    echo "--> rom: $model v$ver"
    [ -d $dir ] || mkdir $dir
    pushd $dir
    if ! [ -f $img ]; then
        trap "clean \"$PWD/system.new.dat\"" INT
        if ! [ -f system.new.dat ]; then
            $sevenzip x ../$file "system.new.dat" "system.transfer.list" \
            || clean system.new.dat
        fi
    fi
    trap "clean \"$PWD/$img\"" INT
    if ! [ -f $img ]; then
        $sdat2img system.transfer.list system.new.dat $img 2>/dev/null \
        && rm -f "system.new.dat" "system.transfer.list" \
        || clean $img
    fi

    echo "--> image extracted: $img"
    work_dir="$PWD/deodex"
    trap "clean \"$work_dir\"" INT
    rm -Rf deodex
    mkdir -p deodex/system

    echo "--> copying apps"
    $sevenzip x -odeodex/system/ "$img" build.prop >/dev/null || clean "$work_dir"
    for f in $apps; do
        echo "----> copying $f..."
        $sevenzip x -odeodex/system/ "$img" priv-app/$f >/dev/null || clean "$work_dir"
    done
    arch="arm64"
    for f in $apps; do
        deodex "$work_dir" "$f" "$arch" priv-app || clean "$work_dir"
    done

    echo "--> patching weather"
    rm -f ../weather-*.apk
    $sevenzip x -odeodex/system/ "$img" data-app/Weather >/dev/null || clean "$work_dir"
    cp deodex/system/data-app/Weather/Weather.apk ../weather-$model-$ver-orig.apk
    deodex "$work_dir" Weather "$arch" data-app || clean "$work_dir"
    mv deodex/system/data-app/Weather/Weather.apk ../weather-$model-$ver-mod.apk
    rm -rf deodex/system/data-app/

    echo "--> packaging flashable zip"
    pushd deodex
    ubin=META-INF/com/google/android/update-binary
    mkdir -p $(dirname $ubin)
    cp "$tool_dir/update-binary-cleaner" $ubin
    $sed -i "s/ver=.*/ver=$model-$ver/" $ubin
    rm -f ../../eufix-$model-$ver.zip system/build.prop
    $sevenzip a -tzip ../../eufix-$model-$ver.zip . >/dev/null
    trap - INT
    popd
    echo "--> done"
    popd
}

trap "echo '--> abort'; exit 1" INT
declare -a darr=("$@")
for i in "${darr[@]}"; do
    echo "--> Downloading $(basename $i)"
    $aria2c $i || exit 1
done
trap - INT

for f in *.zip; do
    arr=(${f//_/ })
    if [[ "${arr[0]}" != "xiaomi.eu" ]]; then
        continue
    fi
    if [ -f $f.aria2 ]; then
        echo "--> skip incomplete file: $f"
        continue
    fi
    model=${arr[2]}
    ver=${arr[3]}
    extract $model $ver $f "$mipay_apps"
done

echo "--> all done"
