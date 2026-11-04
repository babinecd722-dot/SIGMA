#!/usr/bin/env python3
"""Exercise the real POSIX migration against temporary history files."""
import re
import subprocess
import tempfile
import textwrap
from pathlib import Path

source = (Path(__file__).resolve().parent.parent / 'Terminal/SSH/LegacyShellHistory.swift').read_text()
command = textwrap.dedent(re.search(r'#"""\n(.*?)\n\s*"""#', source, re.S)[1])
assert 'task_history_home="${1:-$HOME}"' in command
name = 'term-4FA9AF5E-E64C-45E4-BE92-4ACC2761F27D'
legacy = f"tmux new-session -d -s '{name}' 2>/dev/null; tmux set-option -t '{name}' status off; exec tmux attach -t '{name}'"
with tempfile.TemporaryDirectory(prefix='sigma-history-check-') as folder:
    root = Path(folder)
    bash, zsh = root / '.bash_history', root / '.zsh_history'
    keep = ['echo hello', "printf 'привет\\n'", 'echo ' + legacy,
            legacy.replace('status off', 'status on'), legacy.replace(name, 'term-user-session'),
            legacy.replace("attach -t '" + name, "attach -t 'term-11111111-1111-1111-1111-111111111111")]
    original = '#1700000000\n' + legacy + '\n#1700000001\n' + '\n'.join(keep) + '\n'
    bash.write_text(original)
    bash.chmod(0o640)
    zsh.write_text(': 1700000000:0;' + legacy + '\n: 1700000001:0;echo hello\n'
                   + legacy.replace('tmux attach -t', 'tmux attach-session -t') + ';exit\n')

    def run():
        subprocess.run(['/bin/sh', '-c', command, 'sigma-history-check', folder], check=True)

    run()
    assert bash.read_text() == '#1700000001\n' + '\n'.join(keep) + '\n'
    assert zsh.read_text() == ': 1700000001:0;echo hello\n'
    backups = list(root.glob('.*.sigma-backup-*'))
    assert len(backups) == 2 and any(p.read_text() == original for p in backups)
    assert all(p.stat().st_mode & 0o777 == 0o600 for p in backups)
    assert bash.stat().st_mode & 0o777 == 0o640
    before = bash.read_bytes()
    run()
    assert bash.read_bytes() == before and len(list(root.glob('.*.sigma-backup-*'))) == 2
    bash.unlink()
    real = root / 'symlink-target'
    real.write_text(legacy + '\n')
    bash.symlink_to(real)
    run()
    assert real.read_text() == legacy + '\n'
    bash.unlink()
    large = b'x' * 4194305
    bash.write_bytes(large)
    run()
    assert bash.read_bytes() == large
print('History migration: exact-match removal, retained commands/Unicode, backups, permissions, idempotence, symlinks and file limit PASS')
