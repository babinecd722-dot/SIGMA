import Foundation

/// Retires the exact bootstrap emitted by older clients over a separate
/// SSH exec channel. No persistent copies, shell hooks or helper files.
/// Unknown formats, symlinks, large files and concurrent changes are skipped.
enum LegacyShellHistory {
    static let cleanupCommand = #"""
    (
      umask 077
      task_history_home="${1:-$HOME}"
      work=""
      cleanup_work() {
        if [ -n "$work" ]; then
          rm -f "$work/original" "$work/filtered" "$work/replacement"
          rmdir "$work" 2>/dev/null
          work=""
        fi
      }
      trap 'cleanup_work' 0
      trap 'exit 1' 1 2 3 15
      filter_legacy() {
        awk '
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
          function uncertain_record(line, s, i, c, quote, escaped, sq) {
            # Unmarked multiline shell history has no reliable record
            # boundary. Stop matching after an ambiguous construct rather
            # than deleting a literal bootstrap inside a here-doc/string.
            s=line
            sub(/^: [0-9]+:[0-9]+;/, "", s)
            if (index(s,"<<") || index(s,"$(") || index(s,sprintf("%c",96)) || s ~ /\\[ \t]*$/) return 1
            sq=sprintf("%c",39)
            for (i=1; i<=length(s); i++) {
              c=substr(s,i,1)
              if (escaped) { escaped=0; continue }
              if (c=="\\" && quote!=sq) { escaped=1; continue }
              if (quote!="") { if (c==quote) quote=""; continue }
              if (c==sq || c=="\"") { quote=c; continue }
              if (c=="(" || c=="{") return 1
            }
            return quote!=""
          }
          /^#[0-9]+$/ { if (stamp!="") print stamp; stamp=$0; next }
          { if (!uncertain && bootstrap($0)) { removed++; stamp=""; next }
            if (stamp!="") { print stamp; stamp="" }
            print
            if (uncertain_record($0)) uncertain=1 }
          END { if (stamp!="") print stamp; if (!removed) exit 3 }
        ' "$1"
      }
      task_history_uid=$(id -u) || exit 1
      for h in "$task_history_home/.bash_history" "$task_history_home/.zsh_history"; do
        # Retire only recognizable copies made by the old migration:
        # exact generated name, private regular file owned by this user,
        # single link, bounded size, and a matching legacy bootstrap.
        for backup in "${h}.sigma-backup-"????????; do
          [ -f "$backup" ] && [ ! -L "$backup" ] || continue
          suffix=${backup#"${h}.sigma-backup-"}
          case "$suffix" in *[!A-Za-z0-9]*) continue ;; esac
          [ "${#suffix}" -eq 8 ] || continue
          [ -n "$(find "$backup" -prune -type f -user "$task_history_uid" -perm 0600 -links 1 -print)" ] || continue
          n=$(wc -c < "$backup") || continue
          [ "$n" -le 4194304 ] 2>/dev/null || continue
          if filter_legacy "$backup" >/dev/null; then rm -f "$backup"; fi
        done
        [ -f "$h" ] && [ ! -L "$h" ] && [ -r "$h" ] && [ -w "$h" ] || continue
        n=$(wc -c < "$h") || continue
        [ "$n" -le 4194304 ] 2>/dev/null || continue
        work=$(mktemp -d "${h}.sigma.XXXXXXXX") || continue
        if ! cp -p "$h" "$work/original"; then cleanup_work; continue; fi
        if filter_legacy "$work/original" > "$work/filtered"; then
          if cmp -s "$h" "$work/original" && cp -p "$work/original" "$work/replacement" &&
             cat "$work/filtered" > "$work/replacement"; then
            if cmp -s "$h" "$work/original"; then mv -f "$work/replacement" "$h"; fi
          fi
        fi
        cleanup_work
      done
    ) >/dev/null 2>&1
    """#
}
