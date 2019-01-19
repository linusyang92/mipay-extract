#!/bin/bash

cd "$(dirname "$0")"

darr=()
while [[ $# -gt 0 ]]; do
key="$1"

case $key in
    --trafficfix)
    EXTRA_PRIV="framework/services.jar $EXTRA_PRIV"
    echo "--> Increase threshold (50M) to prevent high cpu of traffic monitoring"
    shift
    ;;
    --clock)
    regular_apps="DeskClock $regular_apps"
    echo "--> Modify Clock to support work day alarms"
    shift
    ;;
    --nofbe)
    NO_EXTRA_FBE="yes"
    shift
    ;;
    *)
    darr+=("$1")
    shift
    ;;
esac
done

mipay_apps="Calendar SecurityCenter"
private_apps=""
[ -z "$EXTRA_PRIV" ] || private_apps="$private_apps $EXTRA_PRIV"

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python2.7 $tool_dir/sdat2img.py"
patchmethod="python2.7 $tool_dir/patchmethod.py"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.2.5.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.2.5.jar"
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
    brotli="$tool_dir/darwin/brotli"
else
    exists aapt && aapt="aapt" || aapt="$tool_dir/aapt"
    exists zipalign && zipalign="zipalign" || zipalign="$tool_dir/zipalign"
    exists 7z && sevenzip="7z" || sevenzip="$tool_dir/7za"
    exists aria2c || aria2c="$tool_dir/aria2c $aria2c_opts"
    exists brotli && brotli="brotli" || brotli="$tool_dir/brotli"
    if [[ "$OSTYPE" == "cygwin"* ]]; then
        sdat2img="python2.7 ../tools/sdat2img.py"
        patchmethod="python2.7 ../../tools/patchmethod.py"
        smali="java -Xmx${heapsize}m -jar ../../tools/smali-2.2.5.jar"
        baksmali="java -Xmx${heapsize}m -jar ../../tools/baksmali-2.2.5.jar"
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

update_international_build_flag() {
    path=$1
    pattern="Lmiui/os/Build;->IS_INTERNATIONAL_BUILD"
    
    if [ -d $path ]; then
        found=()
        if [[ "$OSTYPE" == "cygwin"* ]]; then
            pushd "$path"
            cmdret="$(findstr /sm /c:${pattern} '*.*' | tr -d '\015')"
            popd
            result="${cmdret//\\//}"
            while read i; do
                found+=("${path}/$i")
            done <<< "$result"
        else
            files="$(find $path -type f -iname "*.smali")"
            while read i; do
                if grep -q -F "$pattern" $i; then
                    found+=("$i")
                fi
            done <<< "$files"
        fi
    fi
    if [ -f $path ]; then
        found=($path)
    fi

    for i in "${found[@]}"; do
        $sed -i 's|sget-boolean \([a-z]\)\([0-9]\+\), Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z|const/4 \1\2, 0x0|g' "$i" \
            || return 1
        if grep -q -F "$pattern" $i; then
            echo "----> ! failed to patch: $(basename $i)"
        else
            echo "----> patched smali: $(basename $i)"
        fi
    done
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
    apkdir=$deoappdir/$app
    apkfile=$apkdir/$app.apk
    if [[ "$app" == *".jar" ]]; then
        apkdir=$deoappdir
        apkfile=$apkdir/$app
    fi
    file_list="$($sevenzip l "$apkfile")"
    if [[ "$file_list" == *"classes.dex"* ]]; then
        echo "--> decompiling $app..."
            dexclass="classes.dex"
            $baksmali d $apkfile -o $apkdir/smali || return 1
            if [[ "$app" == "Calendar" ]]; then
                $patchmethod $apkdir/smali/com/miui/calendar/util/LocalizationUtils.smali \
                             showsDayDiff showsLunarDate showsWidgetHoliday -showsWorkFreeDay \
                             -isMainlandChina -isGreaterChina || return 1
            fi

            if [[ "$app" == "Weather" ]]; then
                echo "----> searching smali..."
                update_international_build_flag "$apkdir/smali/com/miui/weather2"
                i="$apkdir/smali/com/miui/weather2/tools/ToolUtils.smali"
                if [ -f "$i" ]; then
                    $patchmethod "$i" -canRequestCommercial -canRequestCommercialInfo || return 1
                fi
            fi

            if [[ "$app" == "SecurityCenter" ]]; then
                update_international_build_flag "$apkdir/smali/com/miui/antivirus/activity/SettingsActivity.smali"
            fi

            if [[ "$app" == "DeskClock" ]]; then
                echo "----> searching smali..."
                update_international_build_flag "$apkdir/smali/"
            fi

            if [[ "$app" == "services.jar" ]]; then
                i="$apkdir/smali/com/android/server/net/NetworkStatsService.smali"
                $sed -i 's|, 0x200000$|, 0x5000000|g' "$i" || return 1
                $sed -i 's|, 0x20000$|, 0x1000000|g' "$i" || return 1
                if grep -q -F ', 0x20000' $i; then
                    echo "----> ! failed to patch: $(basename $i)"
                else
                    echo "----> patched smali: $(basename $i)"
                fi
            fi

            $smali assemble -a $api $apkdir/smali -o $apkdir/$dexclass || return 1
            rm -rf $apkdir/smali
            if [[ ! -f $apkdir/$dexclass ]]; then
                echo "----> failed to baksmali: $apkdir/$dexclass"
                continue
            fi
        $sevenzip d "$apkfile" $dexclass >/dev/null
        pushd $apkdir
        adderror=false
        $aapt add -fk "$(basename $apkfile)" classes.dex || adderror=true
        popd
        if $adderror; then
            return 1
        fi
        rm -f $apkdir/classes.dex
        $zipalign -f 4 $apkfile $apkfile-2 >/dev/null 2>&1
        mv $apkfile-2 $apkfile
        if [[ "$deoappdir" == "system/data-app" ]]; then
            if $sign $apkfile; then
                echo "----> signed: $app.apk"
            else
                echo "----> cannot sign $app.apk"
                return 1
            fi
        fi
        if ! [ -d $apkdir/lib ]; then
            $sevenzip x -o$apkdir $apkfile lib >/dev/null
            if [ -d $apkdir/lib ]; then
                pushd $apkdir/lib
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
    priv_apps=$5
    regular_apps=$6
    dir=miuieu-$model-$ver
    img=$dir-system.img

    echo "--> rom: $model v$ver"
    [ -d $dir ] || mkdir $dir
    pushd $dir
    if ! [ -f $img ]; then
        trap "clean \"$PWD/system.new.dat\"" INT
        if ! [ -f system.new.dat ]; then
            filelist="$($sevenzip l ../"$file")"
            if [[ "$filelist" == *system.new.dat.br* ]]; then
                $sevenzip x ../$file "system.new.dat.br" "system.transfer.list" \
                || clean system.new.dat.br
                $brotli -d system.new.dat.br && rm -f system.new.dat.br
            else
                $sevenzip x ../$file "system.new.dat" "system.transfer.list" \
                || clean system.new.dat
            fi
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
    file_list="$($sevenzip l "$img" priv-app/Weather)"
    if [[ "$file_list" == *Weather* ]]; then
        apps="$apps Weather"
    fi
    for f in $apps; do
        echo "----> copying $f..."
        $sevenzip x -odeodex/system/ "$img" priv-app/$f >/dev/null || clean "$work_dir"
    done
    for f in $regular_apps; do
        echo "----> copying $f..."
        $sevenzip x -odeodex/system/ "$img" app/$f >/dev/null || clean "$work_dir"
    done
    for f in $priv_apps; do
        echo "----> copying $f..."
        $sevenzip x -odeodex/system/ "$img" $f >/dev/null || clean "$work_dir"
    done
    arch="arm64"
    for f in $apps; do
        deodex "$work_dir" "$f" "$arch" priv-app || clean "$work_dir"
    done
    for f in $regular_apps; do
        deodex "$work_dir" "$f" "$arch" app || clean "$work_dir"
    done
    for f in $priv_apps; do
        deodex "$work_dir" "$(basename $f)" "$arch" "$(dirname $f)" || clean "$work_dir"
    done

    file_list="$($sevenzip l "$img" data-app/Weather)"
    if [[ "$file_list" == *Weather* ]]; then
    echo "--> patching weather"
    rm -f ../weather-*.apk
    $sevenzip x -odeodex/system/ "$img" data-app/Weather >/dev/null || clean "$work_dir"
    cp deodex/system/data-app/Weather/Weather.apk ../weather-$model-$ver-orig.apk
    deodex "$work_dir" Weather "$arch" data-app || clean "$work_dir"
    mv deodex/system/data-app/Weather/Weather.apk ../weather-$model-$ver-mod.apk
    rm -rf deodex/system/data-app/
    fi

    echo "--> packaging flashable zip"
    pushd deodex
    ubin=META-INF/com/google/android/update-binary
    mkdir -p $(dirname $ubin)
    cp "$tool_dir/update-binary-cleaner" $ubin
    $sed -i "s/ver=.*/ver=$model-$ver/" $ubin
    rm -f ../../eufix-$model-$ver.zip system/build.prop
    $sevenzip a -tzip ../../eufix-$model-$ver.zip . >/dev/null

    if [ -z "$NO_EXTRA_FBE" ]; then
        cp "$tool_dir/update-binary-fbe" $ubin
        rm -f eufix-force-fbe-oreo.zip
        $sevenzip a -tzip -x!system ../../eufix-force-fbe-oreo.zip . >/dev/null
    fi

    trap - INT
    popd
    echo "--> done"
    popd
}

trap "echo '--> abort'; exit 1" INT
for i in "${darr[@]}"; do
    f="$(basename $i)"
    if [ -f "$f" ] && ! [ -f "$f".aria2 ]; then
        continue
    fi
    echo "--> Downloading $f"
    $aria2c $i || exit 1
done
trap - INT

hasfile=false
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
    extract $model $ver $f "$mipay_apps" "$private_apps" "$regular_apps"
    hasfile=true
done

if $hasfile; then
    echo "--> all done"
else
    echo "--> Error: no eu rom detected"
fi
