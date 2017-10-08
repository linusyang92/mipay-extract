#!/bin/bash

cd "$(dirname "$0")"

mipay_apps="Mipay TSMClient UPTsmService"

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python $tool_dir/sdat2img/sdat2img.py"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.2.1.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.2.1.jar"
libmd="libmd.txt"
libln="libln.txt"
aria2c="aria2c --file-allocation trunc -s10 -x10 -j10 -c"

exists() {
  command -v "$1" >/dev/null 2>&1
}

exists aapt && aapt="aapt" || aapt="$tool_dir/aapt"
exists zipalign && zipalign="zipalign" || zipalign="$tool_dir/zipalign"

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

abort() {
    echo "--> $1"
    echo "--> abort"
    exit 1
}

deodex() {
    app=$2
    base_dir="$1"
    arch=$3
    deoappdir=system/app
    deoarch=oat/$arch
    framedir=system/framework
    pushd "$base_dir"
    api=$(grep "ro.build.version.sdk" system/build.prop | cut -d"=" -f2)
    if [ -z "$api" ]; then
        api=25
    fi
    file_list="$(7z l "$deoappdir/$app/$app.apk")"
    if [[ "$file_list" == *"classes.dex"* ]]; then
        echo "--> already deodexed $app"
    else
        echo "--> deodexing $app..."
        classes=$($baksmali list dex $deoappdir/$app/$deoarch/$app.odex 2>&1)
        echo "----> classes: $classes"
        echo "$classes" | while read line; do
            apkdex=$(basename $(echo "$line"))
            if [[ $(echo "$apkdex" | grep classes) = "" ]]; then
                dexclass="classes.dex"
            else
                dexclass=$(echo "$apkdex" | cut -d":" -f2-)
            fi
            $baksmali deodex -b $framedir/$arch/boot.oat $deoappdir/$app/$deoarch/$app.odex/$apkdex -o $deoappdir/$app/$deoarch/smali || return 1
            $smali assemble -a $api $deoappdir/$app/$deoarch/smali -o $deoappdir/$app/$deoarch/$dexclass || return 1
            rm -rf $deoappdir/$app/$deoarch/smali
            if [[ ! -f $deoappdir/$app/$deoarch/$dexclass ]]; then
                echo "----> failed to baksmali: $deoappdir/$app/$deoarch/$dexclass"
                continue
            fi
        done
        $aapt add -fk $deoappdir/$app/$app.apk $deoappdir/$app/$deoarch/classes*.dex || return 1
        apkfile=$deoappdir/$app/$app.apk
        $zipalign -f 4 $apkfile $apkfile-2 >/dev/null 2>&1
        mv $apkfile-2 $apkfile
    fi
    rm -rf $deoappdir/$app/oat
    if [ -d "$deoappdir/$app/lib/$arch" ]; then
        echo "mkdir -p /system/app/$app/lib/$arch" >> $libmd
        for f in $deoappdir/$app/lib/$arch/*.so; do
            if ! grep -q ELF $f; then
                fname=$(basename $f)
                echo "ln -s $(cat $f) /system/app/$app/lib/$arch/$fname" >> $libln
            fi
        done
        rm -rf "$deoappdir/$app/lib"
    fi
    popd
    return 0
}

extract() {
    model=$1
    ver=$2
    file=$3
    apps=$4
    dir=miui-$model-$ver
    img=$dir-system.img

    echo "--> rom: $model v$ver"
    [ -d $dir ] || mkdir $dir
    pushd $dir
    trap "clean \"$PWD/system.new.dat\"" INT
    [ -f system.new.dat ] || \
      7z x ../$file "system.new.dat" "system.transfer.list" || \
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
    7z x -odeodex/system/ "$img" build.prop >/dev/null || clean "$work_dir"
    for f in $apps; do
        echo "----> copying $f..."
        7z x -odeodex/system/ "$img" app/$f >/dev/null || clean "$work_dir"
    done
    archs="arm64 x86_64 arm x86"
    arch="arm64"
    frame="$(7z l "$img" framework)"
    for i in $archs; do
        if [[ "$frame" == *"$i"* ]]; then
            arch=$i
            echo "--> framework arch: $arch"
            break
        fi
    done
    7z x -odeodex/system/ "$img" framework/$arch >/dev/null || clean "$work_dir"
    rm -f "$work_dir"/{$libmd,$libln}
    touch "$work_dir"/{$libmd,$libln}
    for f in $apps; do
        deodex "$work_dir" "$f" "$arch" || clean "$work_dir"
    done

    echo "--> packaging flashable zip"
    pushd deodex
    rm -Rf system/framework
    ubin=META-INF/com/google/android/update-binary
    mkdir -p $(dirname $ubin)
    cp "$tool_dir/update-binary" $ubin
    sed -i "s/ver=.*/ver=$model-$ver/" $ubin
    sed -e '/#mkdir_symlink/ {' -e "r $libmd" -e 'd' -e '}' -i $ubin
    sed -e '/#do_symlink/ {' -e "r $libln" -e 'd' -e '}' -i $ubin
    rm -f ../mipay-$model-$ver.zip $libmd $libln system/build.prop
    7z a -tzip ../../mipay-$model-$ver.zip . >/dev/null
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
    if [[ "${arr[0]}" != "miui" ]]; then
        continue
    fi
    if [ -f $f.aria2 ]; then
        echo "--> skip incomplete file: $f"
        continue
    fi
    model=${arr[1]}
    ver=${arr[2]}
    extract $model $ver $f "$mipay_apps"
done

echo "--> all done"
