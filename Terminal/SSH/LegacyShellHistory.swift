import Foundation

/// Retires the exact bootstrap emitted by older clients. Runs once over a
/// separate SSH exec channel, never through the interactive terminal.
/// Unknown formats, symlinks, large files and concurrent changes are skipped.
enum LegacyShellHistory {
    static let cleanupCommand = #"""
    (
      umask 077
      task_history_home="${1:-$HOME}"
      for h in "$task_history_home/.bash_history" "$task_history_home/.zsh_history"; do
        [ -f "$h" ] && [ ! -L "$h" ] && [ -r "$h" ] && [ -w "$h" ] || continue
        n=$(wc -c < "$h") || continue
        [ "$n" -le 4194304 ] 2>/dev/null || continue
        work=$(mktemp -d "${h}.sigma.XXXXXXXX") || continue
        if ! cp -p "$h" "$work/original"; then rm -f "$work/original"; rmdir "$work"; continue; fi
        if awk '
          function bootstrap(line, s, id, parts, count, q, expected) {
            s=line
            sub(/^: [0-9]+:[0-9]+;/, "", s)
            gsub(/[\t ]+/, " ", s)
            sub(/;exit$/, "", s)
            if (!match(s, /term-[A-Fa-f0-9-]+/)) return 0
            id=substr(s,RSTART,RLENGTH)
            count=split(substr(id,6),parts,"-")
            if (count!=5 || length(parts[1])!=8 || length(parts[2])!=4 || length(parts[3])!=4 || length(parts[4])!=4 || length(parts[5])!=12) return 0
            q=sprintf("%c",39)
            expected="tmux new-session -d -s " q id q " 2>/dev/null; tmux set-option -t " q id q " status off; exec tmux attach -t " q id q
            sub(/exec tmux attach-session -t /, "exec tmux attach -t ", s)
            return s==expected || s==expected ";"
          }
          /^#[0-9]+$/ { if (stamp!="") print stamp; stamp=$0; next }
          { if (bootstrap($0)) { removed++; stamp=""; next }
            if (stamp!="") { print stamp; stamp="" }
            print }
          END { if (stamp!="") print stamp; if (!removed) exit 3 }
        ' "$work/original" > "$work/filtered"; then
          if cmp -s "$h" "$work/original" && cp -p "$work/original" "$work/replacement" &&
             cat "$work/filtered" > "$work/replacement"; then
            backup=$(mktemp "${h}.sigma-backup-XXXXXXXX") || backup=""
            if [ -n "$backup" ]; then
              if cat "$work/original" > "$backup" && cmp -s "$backup" "$work/original"; then
                if cmp -s "$h" "$work/original"; then mv -f "$work/replacement" "$h"; fi
              else
                rm -f "$backup"
              fi
            fi
          fi
        fi
        rm -f "$work/original" "$work/filtered" "$work/replacement"
        rmdir "$work"
      done
    ) >/dev/null 2>&1
    """#
}
