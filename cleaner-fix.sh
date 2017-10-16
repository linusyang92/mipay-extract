#!/bin/bash

cd "$(dirname "$0")"

mipay_apps="CleanMaster"

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python2.7 $tool_dir/sdat2img.py"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.2.1.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.2.1.jar"
aria2c_opts="--file-allocation trunc -s10 -x10 -j10 -c"
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
    if [[ "$OSTYPE" == "cygwin"* ]]; then
        sdat2img="python2.7 ../tools/sdat2img.py"
        smali="java -Xmx${heapsize}m -jar ../../tools/smali-2.2.1.jar"
        baksmali="java -Xmx${heapsize}m -jar ../../tools/baksmali-2.2.1.jar"
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
    deoappdir=system/priv-app
    deoarch=oat/$arch
    framedir=system/framework
    pushd "$base_dir"
    api=$(grep "ro.build.version.sdk" system/build.prop | cut -d"=" -f2)
    if [ -z "$api" ]; then
        api=25
    fi
    file_list="$($sevenzip l "$deoappdir/$app/$app.apk")"
    if [[ "$file_list" == *"classes.dex"* ]]; then
        echo "--> deodexing $app..."
            dexclass="classes.dex"
            $baksmali d $deoappdir/$app/$app.apk -o $deoappdir/$app/smali || return 1
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
        $sevenzip x -o$deoappdir/$app $apkfile lib >/dev/null
        if [ -d $deoappdir/$app/lib ]; then
            pushd $deoappdir/$app/lib
            [ -d armeabi* ] && mv armeabi* arm
            [ -d armv8* ] && mv armv8* arm64
            popd
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
    trap "clean \"$PWD/system.new.dat\"" INT
    [ -f system.new.dat ] || \
      $sevenzip x ../$file "system.new.dat" "system.transfer.list" || \
      clean system.new.dat 
    trap "clean \"$PWD/$img\"" INT
    [ -f $img ] || \
      $sdat2img system.transfer.list system.new.dat $img 2>/dev/null || \
      clean $img

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
        deodex "$work_dir" "$f" "$arch" || clean "$work_dir"
    done

    echo "--> packaging flashable zip"
    pushd deodex
    ubin=META-INF/com/google/android/update-binary
    mkdir -p $(dirname $ubin)
    cp "$tool_dir/update-binary-cleaner" $ubin
    $sed -i "s/ver=.*/ver=$model-$ver/" $ubin
    rm -f ../../cleaner-$model-$ver.zip system/build.prop
    $sevenzip a -tzip ../../cleaner-$model-$ver.zip . >/dev/null
    trap - INT
    popd
    echo "--> done"
    popd
}

trap "echo '--> abort'; exit 1" INT
declare -a darr=("$@")
for i in "${darr[@]}"; do
    [[ "$OSTYPE" == "darwin"* ]] || check aria2c
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
