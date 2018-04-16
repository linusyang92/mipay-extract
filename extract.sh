#!/bin/bash

cd "$(dirname "$0")"

mipay_apps="Mipay TSMClient UPTsmService"
[ -z "$EXTRA" ] || mipay_apps="$mipay_apps $EXTRA"

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python2.7 $tool_dir/sdat2img.py"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.2.1.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.2.1.jar"
libmd="libmd.txt"
libln="libln.txt"
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
    system_img=$4
    deoappdir=system/app
    deoarch=oat/$arch
    framedir=system/framework
    pushd "$base_dir"
    api=$(grep "ro.build.version.sdk" system/build.prop | cut -d"=" -f2)
    if [ -z "$api" ]; then
        api=25
    fi
    file_list="$($sevenzip l "$deoappdir/$app/$app.apk")"
    if [[ "$file_list" == *"classes.dex"* ]]; then
        echo "--> already deodexed $app"
    else
        echo "--> deodexing $app..."
        classes=$($baksmali list dex $deoappdir/$app/$deoarch/$app.odex 2>/dev/null)
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
                orig="$(cat $f)"
                imgpath="${orig#*system/}"
                imglist="$($sevenzip l "$system_img" "$imgpath")"
                if [[ "$imglist" == *"$imgpath"* ]]; then
                    echo "----> copy native library $fname"
                    output_dir=$deoappdir/$app/lib/$arch/tmp
                    $sevenzip x -o"$output_dir" "$system_img" "$imgpath" >/dev/null || return 1
                    mv "$output_dir/$imgpath" $f
                    rm -Rf $output_dir
                else
                    echo "ln -s $orig /system/app/$app/lib/$arch/$fname" >> $libln
                    rm -f "$f"
                fi
            fi
        done
        [ -z "$(ls -A $deoappdir/$app/lib/$arch)" ] && rm -rf "$deoappdir/$app/lib"
    else
        if [[ "$app" == "UPTsmService" ]]; then
            echo "----> extract native library..."
            apkfile=$deoappdir/$app/$app.apk
            path=$deoappdir/$app
            soarch="arm64-v8a"
            if [[ "$arch" == "arm" ]]; then
                soarch="armeabi-v7a"
            fi
            $sevenzip x -o"$path" "$apkfile" "lib/$soarch" >/dev/null || return 1
            mv "$path/lib/$soarch" "$path/lib/$arch"
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
    dir=miui-$model-$ver
    img=$dir-system.img

    echo "--> rom: $model v$ver"
    [ -d $dir ] || mkdir $dir
    pushd $dir
    if ! [ -f $img ]; then
        trap "clean \"$PWD/system.new.dat\"" INT
        if ! [ -f system.new.dat ]; then
            $sevenzip x ../$file "system.new.dat" "system.transfer.list" \
            && rm -f ../$file \
            || clean system.new.dat
            touch ../$file
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
        $sevenzip x -odeodex/system/ "$img" app/$f >/dev/null || clean "$work_dir"
    done
    archs="arm64 x86_64 arm x86"
    arch="arm64"
    frame="$($sevenzip l "$img" framework)"
    for i in $archs; do
        if [[ "$frame" == *"$i"* ]]; then
            arch=$i
            echo "--> framework arch: $arch"
            break
        fi
    done
    $sevenzip x -odeodex/system/ "$img" framework/$arch >/dev/null || clean "$work_dir"
    rm -f "$work_dir"/{$libmd,$libln}
    touch "$work_dir"/{$libmd,$libln}
    for f in $apps; do
        deodex "$work_dir" "$f" "$arch" "$PWD/$img" || clean "$work_dir"
    done

    echo "--> packaging flashable zip"
    pushd deodex
    rm -Rf system/framework
    ubin=META-INF/com/google/android/update-binary
    mkdir -p $(dirname $ubin)
    cp "$tool_dir/update-binary" $ubin
    $sed -i "s/ver=.*/ver=$model-$ver/" $ubin
    $sed -e '/#mkdir_symlink/ {' -e "r $libmd" -e 'd' -e '}' -i $ubin
    $sed -e '/#do_symlink/ {' -e "r $libln" -e 'd' -e '}' -i $ubin
    rm -f ../../mipay-$model-$ver.zip $libmd $libln system/build.prop
    $sevenzip a -tzip ../../mipay-$model-$ver.zip . >/dev/null
    trap - INT
    popd
    echo "--> done"
    popd
}

trap "echo '--> abort'; exit 1" INT
declare -a darr=("$@")
for i in "${darr[@]}"; do
    f="$(basename $i)"
    if [ -f "$f" ] && ! [ -f "$f".aria2 ]; then
        continue
    fi
    echo "--> Downloading $f"
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
