# Writes the default settings of the mod as "name<TAB>value" lines, the way
# Windhawk names them (e.g. weights[0].apps[2]), for the test harness.
# Usage: python settings_defaults.py ../tile-windows.wh.cpp settings.txt
import re
import sys

import yaml

source = open(sys.argv[1], encoding='utf-8').read()
block = re.search(r'// ==WindhawkModSettings==\s*/\*(.*?)\*/', source, re.S)
items = yaml.safe_load(block.group(1))


def flatten(prefix, value, out):
    if isinstance(value, list):
        for i, v in enumerate(value):
            if isinstance(v, list):  # one entry of an array of nested settings
                for setting in v:
                    for k, sv in setting.items():
                        if not k.startswith('$'):
                            flatten(f'{prefix}[{i}].{k}', sv, out)
            else:
                flatten(f'{prefix}[{i}]', v, out)
    elif isinstance(value, bool):
        out.append((prefix, '1' if value else '0'))
    else:
        out.append((prefix, str(value)))


out = []
for item in items:
    for key, value in item.items():
        if not key.startswith('$'):
            flatten(key, value, out)
with open(sys.argv[2], 'w', encoding='utf-8', newline='\n') as f:
    for name, value in out:
        f.write(f'{name}\t{value}\n')
