"""usage: check-excluded-markdown-links.py CONFIG

md-dead-link-check cannot decode `%20`, so CONFIG, its configuration, excludes
the links that need it. Each `exclude_links` entry is a link as
Documentation/Manual.md spells it, relative to Documentation/. This decodes each
entry, prints the path it names, and exits non-zero when one does not exist.
"""

import os
import sys
from urllib.parse import unquote

try:
    import tomllib
except ImportError:  # Python 3.10, which the checker's action sets up, has tomli from installing the checker.
    import tomli as tomllib

with open(sys.argv[1], "rb") as config:
    links = tomllib.load(config)["tool"]["md_dead_link_check"]["exclude_links"]
repository = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
missing = 0
for link in links:
    path = os.path.normpath(os.path.join(repository, "Documentation", unquote(link)))
    exists = os.path.exists(path)
    missing += 0 if exists else 1
    print(f"{'found' if exists else 'missing'}: {link} -> {os.path.relpath(path, repository)}")
sys.exit(1 if missing else 0)
