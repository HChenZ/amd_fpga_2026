"""Record byte hashes for the production (nonrecursive root + ascon) RTL set."""
import hashlib
import json
from pathlib import Path
import sys

root=Path(sys.argv[1])
sources=sorted(root.glob('*.v'))+sorted(root.glob('*.vh'))
sources+=sorted(p for p in (root/'ascon').glob('*') if p.suffix in ('.v','.vh') and not p.name.endswith('_tb.v'))
Path(sys.argv[2]).write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sources},indent=2)+'\n',encoding='utf-8')
