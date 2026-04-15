#!/usr/bin/env bash
VERSION="9.0.0-NDIR"
WDIR="/tmp/diffy2_$$"

[ $# -lt 2 ] && echo "Usage: $0 dir1 dir2 [dir3...]" && exit 1

cleanup() { rm -rf "$WDIR"; }
trap cleanup EXIT
mkdir -p "$WDIR"

START=$(date +%s)
DIRS=("$@")
num_dirs=$#

echo "=========================================="
echo "DIFFY2 v$VERSION (MD5, $num_dirs dirs)"
echo "=========================================="

# Scan each directory
for ((idx=0; idx<num_dirs; idx++)); do
    dir="${DIRS[$idx]}"
    echo "[$idx] Scanning: $dir"
    count=0
    for f in $(find "$dir" -type f \( -name "*.log" -o -name "*.txt" -o -name "*.json" -o -name "*.csv" -o -name "*.gz" -o -name "*.evtx" \) 2>/dev/null); do
        fn="${f##*/}"
        echo "$fn|$idx|$f" >> "$WDIR/all.txt"
        count=$((count + 1))
    done
    echo "[+] $dir: $count files"
done

echo "[*] Comparing $num_dirs directories..."

# Create indexed hash file
while read line; do
    fn="${line%%|*}"
    idx="${line%%|*}"
    idx="${line#*|}"
    idx="${idx%%|*}"
    fp="${line##*|}"
    h=$(md5sum "$fp" 2>/dev/null | cut -d' ' -f1)
    echo "$fn|$idx|$h|$fp"
done < "$WDIR/all.txt" > "$WDIR/hashes.txt"

# Initialize output files
> "$WDIR/same.txt"
> "$WDIR/diff.txt"
> "$WDIR/unique.txt"

# Get all unique filenames
cut -d'|' -f1 "$WDIR/hashes.txt" | sort -u | while read fn; do
    [ -z "$fn" ] && continue
    
    # Get all entries for this filename
    entries=$(grep "^$fn|" "$WDIR/hashes.txt")
    count=$(echo "$entries" | wc -l)
    
    if [ "$count" -eq "$num_dirs" ]; then
        # File exists in ALL dirs - check hash
        hashes=$(echo "$entries" | cut -d'|' -f3 | sort -u | wc -l)
        if [ "$hashes" -eq 1 ]; then
            # Same content in all dirs
            paths=$(echo "$entries" | cut -d'|' -f4 | tr '\n' '|')
            echo "$fn|${paths%|}" >> "$WDIR/same.txt"
        else
            # Different content
            paths=$(echo "$entries" | cut -d'|' -f4 | tr '\n' '|')
            echo "$fn|${paths%|}" >> "$WDIR/diff.txt"
        fi
    elif [ "$count" -eq 1 ]; then
        # UNIQUE - only in one dir
        path=$(echo "$entries" | cut -d'|' -f4)
        echo "$fn|$path" >> "$WDIR/unique.txt"
    else
        # In some dirs but not all
        paths=$(echo "$entries" | cut -d'|' -f4 | tr '\n' '|')
        echo "$fn|${paths%|}" >> "$WDIR/diff.txt"
    fi
done

same=$(wc -l < "$WDIR/same.txt")
diffc=$(wc -l < "$WDIR/diff.txt")
unique=$(wc -l < "$WDIR/unique.txt")

total=$(wc -l < "$WDIR/all.txt")
END=$(date +%s)
DURATION=$((END - START))

out="diffy2_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "======================================================================"
    echo "          DIFFY2 - MULTI-DIRECTORY COMPARE"
    echo "======================================================================"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Hash: MD5 | Directories: $num_dirs"
    echo ""
    
    for ((idx=0; idx<num_dirs; idx++)); do
        c=$(grep "|$idx|" "$WDIR/all.txt" 2>/dev/null | wc -l)
        echo "Dir$((idx+1)): ${DIRS[$idx]}"
        echo "       $c files"
    done
    
    echo ""
    echo "Total: $total files"
    echo "Time: ${DURATION}s"
    echo ""
    echo "=== SUMMARY ==="
    echo "SAME (identical in all $num_dirs dirs): $same"
    echo "DIFFERENT (same name, diff content): $diffc"
    echo "UNIQUE (only in one dir): $unique"
    echo ""
    echo "======================================================================"
    echo "=== FILES TO DELETE (Identical in All $num_dirs Dirs) ==="
    echo "======================================================================"
    if [ $same -gt 0 ]; then
        while IFS='|' read fn paths; do
            [ -z "$fn" ] && continue
            echo "[DEL] $fn"
            for ((idx=0; idx<num_dirs; idx++)); do
                p=$(echo "$paths" | cut -d'|' -f$((idx+1)))
                [ -n "$p" ] && echo "     Dir$((idx+1)): $p"
            done
        done < "$WDIR/same.txt"
    else
        echo "  (none)"
    fi
    echo ""
    echo "======================================================================"
    echo "=== FILES TO REVIEW (Content Differs) ==="
    echo "======================================================================"
    if [ $diffc -gt 0 ]; then
        while IFS='|' read fn paths; do
            [ -z "$fn" ] && continue
            echo "[?!] $fn"
            for ((idx=0; idx<num_dirs; idx++)); do
                p=$(echo "$paths" | cut -d'|' -f$((idx+1)))
                [ -n "$p" ] && echo "     Dir$((idx+1)): $p"
            done
        done < "$WDIR/diff.txt"
    else
        echo "  (none)"
    fi
    echo ""
    echo "======================================================================"
    echo "=== FILES TO KEEP (Unique - Only in One Dir) ==="
    echo "======================================================================"
    if [ $unique -gt 0 ]; then
        while IFS='|' read fn path; do
            [ -z "$fn" ] && continue
            echo "[KEEP] $fn"
            echo "     $path"
        done < "$WDIR/unique.txt"
    else
        echo "  (none)"
    fi
} > "$out"

cat "$out"
echo "[+] $out"
