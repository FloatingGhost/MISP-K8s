from pyaml import yaml
from collections import MutableMapping

with open("/config/config.yaml", "r") as f:
    config = yaml.load(f)
# Recursively extract config
with open("/var/www/MISP/app/Config/bootstrap.php", "a") as f:
    def flatten(d, parent_key='', sep='.'):
        items = []
        for k, v in d.items():
            new_key = '{0}{1}{2}'.format(parent_key,sep,k) if parent_key else k
            if isinstance(v, MutableMapping):
                items.extend(flatten(v, new_key, sep=sep).items())
            elif isinstance(v, list):
                # apply itself to each element of the list - that's it!
                items.append((new_key, map(flatten, v)))
            else:
                items.append((new_key, v))
        return dict(items)
    flattened = flatten(config)
    for key, value in flattened.items():
        if isinstance(value, str):
            f.write("Configure::write('{}', '{}');\n".format(key, value))
        else:
            f.write("Configure::write('{}', {});\n".format(key, value))
