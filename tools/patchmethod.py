#!/usr/bin/env python2.7

import sys
import re
import os

STUB_METHOD = '''\
    .locals 1
    const/4 v0, 0x1
    return v0
'''

def main():
    if len(sys.argv) < 2:
        print("No input file")
        return 1

    smali_path = sys.argv[1]
    method_list = sys.argv[2:]
    if len(method_list) == 0:
        return 0
    method_set = set(method_list)

    with open(smali_path, 'r') as f:
        smali = f.read()
    method_name = ''
    patched = ''
    overwriting = False
    for line in smali.splitlines():
        method_line = re.search(r'\.method\s+(?:public\s+)?(?:static\s+)?([^\(]+)\(', line)
        if method_line:
            method_name = method_line.group(1)
            if method_name in method_set:
                overwriting = True
            patched += line + '\n'
        elif '.end method' in line:
            if overwriting:
                overwriting = False
                patched += STUB_METHOD + line + '\n'
                print('----> patched method: ' + method_name)
            else:
                patched += line + '\n'
        else:
            if not overwriting:
                patched += line + '\n'
    with open(smali_path, 'w') as f:
        f.write(patched)

if __name__ == "__main__":
    main()
