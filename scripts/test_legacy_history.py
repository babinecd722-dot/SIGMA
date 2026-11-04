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

    # Files from the previous client: remove only recognizable private
    # copies; similarly named user files and symlinks must survive.
    old_backup = root / '.bash_history.sigma-backup-AB12cd34'
    old_backup.write_text(original)
    old_backup.chmod(0o600)
    decoys = [root / '.bash_history.sigma-backup-short',
              root / '.bash_history.sigma-backup-AB12cd3_',
              root / '.bash_history.sigma-backup-EF56gh78',
              root / '.bash_history.sigma-backup-IJ90kl12',
              root / '.bash_history.sigma-backup-MN34op56']
    for item in decoys[:4]:
        item.write_text(original)
        item.chmod(0o600)
    decoys[2].write_text('echo my unrelated private backup\n')
    decoys[3].chmod(0o644)
    decoys[4].symlink_to(decoys[0])
    snapshots = {item: item.read_bytes() for item in decoys}
    run()
    assert bash.read_text() == '#1700000001\n' + '\n'.join(keep) + '\n'
    assert zsh.read_text() == ': 1700000001:0;echo hello\n'
    assert not old_backup.exists()
    assert all(item.read_bytes() == data for item, data in snapshots.items())
    assert decoys[4].is_symlink()
    assert set(root.glob('.*.sigma-backup-*')) == set(decoys)
    assert not list(root.glob('.*.sigma.????????'))
    assert bash.stat().st_mode & 0o777 == 0o640
    before = bash.read_bytes()
    run()
    assert bash.read_bytes() == before
    assert set(root.glob('.*.sigma-backup-*')) == set(decoys)
    assert not list(root.glob('.*.sigma.????????'))
    # A pre-existing shell can save an old entry again. A later cleanup
    # must remove it again without creating a persistent duplicate.
    bash.write_text(legacy + '\necho retained after another shell saved\n')
    run()
    assert bash.read_text() == 'echo retained after another shell saved\n'
    assert set(root.glob('.*.sigma-backup-*')) == set(decoys)
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
    # A literal command inside an unmarked multi-line entry is user data,
    # not evidence that this client owns that entry or an old backup.
    for literal in ["cat <<'END'\n" + legacy + "\nEND\n",
                    "printf '%s\\n' '\n" + legacy + "\n'\n",
                    "(\n" + legacy + "\n)\n"]:
        bash.write_text(literal)
        protected_copy = root / '.bash_history.sigma-backup-Qr78St90'
        protected_copy.write_text(literal)
        protected_copy.chmod(0o600)
        run()
        assert bash.read_text() == literal
        assert protected_copy.read_text() == literal
        protected_copy.unlink()
    # A proven old one-line entry preceding ambiguous user content still
    # retires; the literal occurrence is preserved byte for byte.
    literal = "cat <<'END'\n" + legacy + "\nEND\n"
    bash.write_text(legacy + '\n' + literal)
    run()
    assert bash.read_text() == literal
print('History cleanup: exact-match removal, retained commands/Unicode, no new persistent copies, conservative old-copy removal, permissions, repeated writes, symlinks and file limit PASS')
