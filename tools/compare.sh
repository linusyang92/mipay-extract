#!/bin/bash
cd "$(dirname "$0")/../"
echo "Comparing MIUI China and EU Roms ..."
for top in *-MIM*2-*; do
    ! [ -d $top ] && continue
    pushd $top
    DIR=$PWD
    for d in app priv-app; do
        ! [ -d "$d" ] && 7z x *.img $d
        echo "APK Names" > "$DIR/$d.txt"
        find $d -iname '*.apk' -type f | while read f; do
            DUMP="$(../tools/darwin/aapt dump badging 2>/dev/null $f)"
            echo "$(basename $f) $(echo "$DUMP" \
                   | grep application-label-zh-CN:): $(echo "$DUMP" \
                   | grep package:\ name)" >> "$DIR/$d.txt"
        done
        sort $d.txt -o $d-sort.txt
    done
    cat app.txt priv-app.txt > all.txt
    sort all.txt -o all-sort.txt
    ! [ -f build.prop ] && 7z x *.img build.prop
    popd
done

mkdir -p compare

for d in app priv-app all; do
    diff -Naur miui-*/$d-sort.txt miuieu-*/$d-sort.txt > compare/$d.diff
done
diff -Naur miui-*/build.prop miuieu-*/build.prop > compare/build_prop.diff

echo "Done!"
