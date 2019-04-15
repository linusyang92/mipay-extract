#!/bin/bash

cd "$(dirname "$0")"

darr=()
while [[ $# -gt 0 ]]; do
key="$1"

case $key in
    --appvault)
    EXTRA_PRIV="priv-app/PersonalAssistant app/MetokNLP $EXTRA_PRIV"
    echo "--> Enabled app vault extract"
    shift
    ;;
    *)
    darr+=("$1")
    shift
    ;;
esac
done

mipay_apps="Mipay NextPay TSMClient UPTsmService"
private_apps=""
[ -z "$EXTRA" ] || mipay_apps="$mipay_apps $EXTRA"
[ -z "$EXTRA_PRIV" ] || private_apps="$private_apps $EXTRA_PRIV"

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python2.7 $tool_dir/sdat2img.py"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.2.5.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.2.5.jar"
libmd="libmd.txt"
libln="libln.txt"
privapp="privapp.txt"
aria2c_opts="--check-certificate=false --file-allocation=trunc -s10 -x10 -j10 -c"
aria2c="aria2c $aria2c_opts"
sed="sed"
vdex="vdexExtractor"
cdex="$tool_dir/cdex/compact_dex_converter_linux"
patchmethod="python2.7 $tool_dir/patchmethod.py"
imgroot=""
imgexroot="system/"

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
    brotli="$tool_dir/darwin/brotli"
    vdex="$tool_dir/darwin/vdexExtractor"
    aria2c="$tool_dir/darwin/aria2c $aria2c_opts"
    sed="$tool_dir/darwin/gsed"
    cdex="$tool_dir/cdex/compact_dex_converter_mac"
else
    exists aapt && aapt="aapt" || aapt="$tool_dir/aapt"
    exists zipalign && zipalign="zipalign" || zipalign="$tool_dir/zipalign"
    exists 7z && sevenzip="7z" || sevenzip="$tool_dir/7za"
    exists aria2c || aria2c="$tool_dir/aria2c $aria2c_opts"
    exists brotli && brotli="brotli" || brotli="$tool_dir/brotli"
    exists vdexExtractor || vdex="$tool_dir/vdexExtractor"
    if [[ "$OSTYPE" == "cygwin"* ]]; then
        sdat2img="python2.7 ../tools/sdat2img.py"
        patchmethod="python2.7 ../../tools/patchmethod.py"
        smali="java -Xmx${heapsize}m -jar ../../tools/smali-2.2.5.jar"
        baksmali="java -Xmx${heapsize}m -jar ../../tools/baksmali-2.2.5.jar"
        cdex_top="../../../../../../../tools/cdex"
        cdex="./flinux.exe compact_dex_converter_linux"
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
    deoappdir=system/$5
    deoarch=oat/$arch
    framedir=system/framework
    pushd "$base_dir"
    api=$(grep "ro.build.version.sdk" system/build.prop | cut -d"=" -f2)
    if [ -z "$api" ]; then
        api=25
    fi
    hasvdex=false
    if [ -f "$deoappdir/$app/$deoarch/$app.vdex" ]; then
        echo "--> vdex detected"
        hasvdex=true
    fi
    file_list="$($sevenzip l "$deoappdir/$app/$app.apk")"
    if [[ "$file_list" == *"classes.dex"* ]]; then
        echo "--> already deodexed $app"
    else
        echo "--> deodexing $app..."
        if $hasvdex; then
            classes="classes.dex"
        else
            classes=$($baksmali list dex $deoappdir/$app/$deoarch/$app.odex 2>/dev/null | tr -d '\015' | sort -V)
            echo "----> classes: $classes"
        fi
        while read line; do
            apkdex=$(basename $(echo "$line"))
            if [[ $(echo "$apkdex" | grep classes) = "" ]]; then
                dexclass="classes.dex"
            else
                dexclass=$(echo "$apkdex" | cut -d":" -f2-)
            fi
            if $hasvdex; then
                pushd $deoappdir/$app/$deoarch
                $vdex -i $app.vdex || return 1
                for f in ${app}_*; do
                    dexfile="${f/${app}_/}"
                    mv $f $dexfile || return 1
                    if [[ "$dexfile" == *.cdex ]]; then
                        if [ -z "$cdex" ]; then
                            echo "--> error: cdex not supported"
                            popd
                            return 1
                        fi
                        cdex_bin_copy=false
                        if ! [ -z "$cdex_top" ]; then
                            cdex_bin_copy=true
                            if ! [ -d "$cdex_top" ]; then
                                echo "--> error: path error $cdex_top"
                                return 1
                            fi
                            for cdex_bin in $cdex; do
                                if ! cp "$cdex_top/$cdex_bin" .; then
                                    echo "--> error: failed to copy $cdex_bin"
                                    return 1
                                else
                                    echo "----> prepare $cdex_bin"
                                fi
                            done
                        fi
                        echo -ne "----> "
                        $cdex "$dexfile" || return 1
                        mv "$dexfile".new "${dexfile/cdex/dex}" || return 1
                        dexfile="${dexfile/cdex/dex}"
                        if $cdex_bin_copy; then
                            for cdex_bin in $cdex; do
                                rm -f "$cdex_bin"
                            done
                        fi
                    fi
                    echo "----> classes: ${dexfile}"
                done
                popd
            else
                $baksmali deodex -b $framedir/$arch/boot.oat $deoappdir/$app/$deoarch/$app.odex/$apkdex -o $deoappdir/$app/$deoarch/smali || return 1
                $smali assemble -a $api $deoappdir/$app/$deoarch/smali -o $deoappdir/$app/$deoarch/$dexclass || return 1
                rm -rf $deoappdir/$app/$deoarch/smali
                if [[ ! -f $deoappdir/$app/$deoarch/$dexclass ]]; then
                    echo "----> failed to baksmali: $deoappdir/$app/$deoarch/$dexclass"
                    continue
                fi
            fi
        done <<< "$classes"
        pushd $deoappdir/$app/$deoarch
        adderror=false
        $aapt add -fk ../../$app.apk classes*.dex || adderror=true
        popd
        if $adderror; then
            return 1
        fi
        apkfile=$deoappdir/$app/$app.apk
        $zipalign -f 4 $apkfile $apkfile-2 >/dev/null 2>&1
        mv $apkfile-2 $apkfile
    fi
    rm -rf $deoappdir/$app/oat
    if [[ "$app" == "PersonalAssistant" ]]; then
        echo "----> extract native library..."
        apkfile=$deoappdir/$app/$app.apk
        path=$deoappdir/$app
        pa_arch=arm
        pa_soarch="armeabi"
        $sevenzip x -o"$path" "$apkfile" "lib/$pa_soarch" >/dev/null || return 1
        mv "$path/lib/$pa_soarch/"* "$path/lib/$pa_arch/"
        rm -r "$path/lib/$pa_soarch"

        echo "----> decompiling $app..."
        classes=$($baksmali list dex $apkfile 2>/dev/null | tr -d '\015' | sort -V)

        while read dexclass; do
        paths="$($baksmali list classes $apkfile/$dexclass 2>/dev/null)"
        echo "-----> testing $dexclass"
        [[ "$paths" == *"com/miui/home/launcher/assistant/ui"* ]] || continue
        [[ "$paths" == *"com/miui/personalassistant"* ]] || continue
        echo "-----> found $dexclass"
        $baksmali disassemble --debug-info false --output $deoappdir/$app/smali $apkfile/$dexclass || return 1
        $patchmethod $deoappdir/$app/smali/com/miui/home/launcher/assistant/ui/AssistHolderController.smali \
                     -needUpgradeApk || return 1
        $patchmethod $deoappdir/$app/smali/com/miui/personalassistant/favorite/sync/MiuiFavoriteReceiver.smali \
                     --onReceive || return 1
        $sed -i '\|Lcom/miui/home/launcher/assistant/module/loader/RecommendManager;->initRecommend()V|d' \
            $deoappdir/$app/smali/com/miui/home/launcher/assistant/ui/AssistHolderController'$1'.smali || return 1
        $sed -i '\|Lcom/miui/home/launcher/assistant/ui/view/AssistHolderView;->initAi()V|d' \
            $deoappdir/$app/smali/com/miui/home/launcher/assistant/ui/view/AssistHolderView.smali || return 1
        $sed -i 's|sget-boolean \([a-z]\)\([0-9]\+\), Lmiui/os/Build;->IS_GLOBAL_BUILD:Z|const/4 \1\2, 0x0|g' \
            $deoappdir/$app/smali/com/miui/personalassistant/provider/PersonalAssistantProvider.smali || return 1

        $smali assemble -a $api $deoappdir/$app/smali -o $deoappdir/$app/$dexclass || return 1
        rm -rf $deoappdir/$app/smali
        if ! [ -f "$deoappdir/$app/$dexclass" ]; then
            echo "----> failed to patch: $deoappdir/$app/$dexclass"
            return 1
        fi
        $sevenzip d "$apkfile" $dexclass >/dev/null
        break
        done <<< "$classes"

        pushd $deoappdir/$app
        adderror=false
        $aapt add -fk $app.apk classes*.dex || adderror=true
        popd
        if $adderror; then
            return 1
        fi
        rm -f $deoappdir/$app/classes*.dex
        $zipalign -f 4 $apkfile $apkfile-2 >/dev/null 2>&1
        mv $apkfile-2 $apkfile
    elif [ -d "$deoappdir/$app/lib/$arch" ]; then
        echo "mkdir -p /system/app/$app/lib/$arch" >> $libmd
        for f in $deoappdir/$app/lib/$arch/*.so; do
            if ! grep -q ELF $f; then
                fname=$(basename $f)
                orig="$(cat $f)"
                imgpath="${orig#*system/}"
                imglist="$($sevenzip l "$system_img" "${imgroot}$imgpath")"
                if [[ "$imglist" == *"$imgpath"* ]]; then
                    echo "----> copy native library $fname"
                    output_dir=$deoappdir/$app/lib/$arch/tmp
                    $sevenzip x -o"$output_dir" "$system_img" "${imgroot}$imgpath" >/dev/null || return 1
                    mv "$output_dir/${imgroot}$imgpath" $f
                    rm -Rf $output_dir
                else
                    echo "ln -s $orig /system/app/$app/lib/$arch/$fname" >> $libln
                    rm -f "$f"
                fi
            fi
        done
        [ -z "$(ls -A $deoappdir/$app/lib/$arch)" ] && rm -rf "$deoappdir/$app/lib"
    else
        if [[ "$app" == "UPTsmService" ]] || [[ "$app" == "MetokNLP" ]]; then
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
    priv_apps=$5
    dir=miui-$model-$ver
    img=$dir-system.img
    has_priv_apps=false

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

    detect="$($sevenzip l "$img" system/build.prop)"
    if [[ "$detect" == *"build.prop"* ]]; then
        echo "--> detected new image structure"
        imgroot="system/"
        imgexroot=""
    fi

    echo "--> copying apps"
    $sevenzip x -odeodex/${imgexroot} "$img" ${imgroot}build.prop >/dev/null || clean "$work_dir"
    for f in $apps; do
        echo "----> copying $f..."
        $sevenzip x -odeodex/${imgexroot} "$img" ${imgroot}app/$f >/dev/null || clean "$work_dir"
    done
    echo "system/priv-app" > "$work_dir"/$privapp
    echo "$privapp" >> "$work_dir"/$privapp
    for f in $priv_apps; do
        echo "----> copying $f..."
        has_priv_apps=true
        echo "system/$f" >> "$work_dir"/$privapp
        $sevenzip x -odeodex/${imgexroot} "$img" ${imgroot}$f >/dev/null || clean "$work_dir"
    done
    archs="arm64 x86_64 arm x86"
    arch="arm64"
    frame="$($sevenzip l "$img" ${imgroot}framework)"
    for i in $archs; do
        if [[ "$frame" == *"$i"* ]]; then
            arch=$i
            echo "--> framework arch: $arch"
            break
        fi
    done
    $sevenzip x -odeodex/${imgexroot} "$img" ${imgroot}framework/$arch >/dev/null || clean "$work_dir"
    rm -f "$work_dir"/{$libmd,$libln}
    touch "$work_dir"/{$libmd,$libln}
    for f in $apps; do
        deodex "$work_dir" "$f" "$arch" "$PWD/$img" app || clean "$work_dir"
    done
    for f in $priv_apps; do
        deodex "$work_dir" "$(basename $f)" "$arch" "$PWD/$img" "$(dirname $f)" || clean "$work_dir"
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
    $sevenzip a -tzip -x@"$privapp" ../../mipay-$model-$ver.zip . >/dev/null

    if $has_priv_apps; then
        cp "$tool_dir/update-binary-cleaner" $ubin
        cat << EOF > "$privapp"
print "Patching dns and izat.conf..."
rmprop net.dns1 /system/build.prop
rmprop net.dns2 /system/build.prop
rmprop OSNLP_PACKAGE /system/vendor/etc/izat.conf
rmprop OSNLP_ACTION /system/vendor/etc/izat.conf
EOF
        $sed -i "s/ver=.*/ver=$model-$ver/" $ubin
        $sed -e '/#extra_patches/ {' -e "r $privapp" -e 'd' -e '}' -i $ubin
        rm -f ../../eufix-appvault-$model-$ver.zip $privapp
        file_list=""
        for f in $priv_apps; do
            file_list="$file_list system/$f"
        done
        $sevenzip a -tzip ../../eufix-appvault-$model-$ver.zip META-INF $file_list >/dev/null
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
    if [[ "${arr[0]}" != "miui" ]]; then
        continue
    fi
    if [ -f $f.aria2 ]; then
        echo "--> skip incomplete file: $f"
        continue
    fi
    model=${arr[1]}
    ver=${arr[2]}
    extract $model $ver $f "$mipay_apps" "$private_apps"
    hasfile=true
done

if $hasfile; then
    echo "--> all done"
else
    echo "--> Error: no miui rom detected"
fi
