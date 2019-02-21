#!/usr/bin/env python2.7

import sys
import re
import os

STUB_METHOD = '''\
    .locals 1
    const/4 v0, 0x%s
    return v0
'''

STUB_VOID = '''\
    .locals 0
    return-void
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
    if not os.path.isfile(smali_path):
        print("----> Ignore patch: \"%s\" not found" % os.path.basename(smali_path))
        return 0

    with open(smali_path, 'r') as f:
        smali = f.read()
    method_name = ''
    patched = ''
    overwriting = False
    overvalue = '1'
    for line in smali.splitlines():
        method_line = re.search(r'\.method\s+(?:(?:public|private)\s+)?(?:static\s+)?([^\(]+)\(', line)
        if method_line:
            method_name = method_line.group(1)
            if method_name in method_set:
                overwriting = True
                overvalue = '1'
            if ('-' + method_name) in method_set:
                overwriting = True
                overvalue = '0'
            if ('--' + method_name) in method_set:
                overwriting = True
                overvalue = '-1'
            patched += line + '\n'
        elif '.end method' in line:
            if overwriting:
                overwriting = False
                if overvalue == '-1':
                    patched += STUB_VOID + line + '\n'
                    print('----> patched method: ' + method_name + ' => void')
                else:
                    patched += (STUB_METHOD % overvalue) + line + '\n'
                    print('----> patched method: ' + method_name + \
                          ' => ' + ('true' if overvalue == '1' else 'false'))
            else:
                patched += line + '\n'
        else:
            if not overwriting:
                patched += line + '\n'
    with open(smali_path, 'w') as f:
        f.write(patched)

if __name__ == "__main__":
    main()
