# hdiff.sh - Line-by-Line Documentation

## Overview
`hdiff.sh` is a bash script that compares log files across 2 or more directories using MD5 hashing. It identifies:
- **SAME**: Files identical in all directories (safe to delete duplicates)
- **DIFFERENT**: Same filename but different content
- **UNIQUE**: Files that exist in only one directory

---

## Line 1: Shebang
```bash
#!/usr/bin/env bash
```
- Tells the system to run this using the bash interpreter
- `#!/usr/bin/env bash` is portable across different systems

---

## Line 2: Version
```bash
VERSION="1.7"
```
- Script version number for reference

---

## Line 3: Temp Directory
```bash
WDIR="/tmp/hdiff_$$"
```
- `$$` = current process ID
- Creates unique temp folder like `/tmp/hdiff_12345`
- All temporary work happens here

---

## Line 4-5: Input Validation
```bash
[ $# -lt 2 ] && echo "Usage: $0 dir1 dir2 [dir3...]" && exit 1
```
- `$#` = number of arguments passed
- Requires at least 2 directories
- Shows usage syntax if failed
- Exits with error code 1

---

## Line 6-7: Cleanup Function
```bash
cleanup() { rm -rf "$WDIR"; }
trap cleanup EXIT
```
- `cleanup()` removes the temp directory
- `trap cleanup EXIT` runs cleanup when script exits (success, Ctrl+C, or error)
- Prevents temp files from piling up in /tmp

---

## Line 8: Create Working Directory
```bash
mkdir -p "$WDIR"
```
- Creates the temp directory
- `-p` means "no error if exists"

---

## Line 9: Start Timer
```bash
START=$(date +%s)
```
- Records start time in seconds since 1970 (Unix epoch)
- Used to calculate total runtime

---

## Line 10-11: Store Directories
```bash
DIRS=("$@")
num_dirs=$#
```
- `DIRS=("$@")` = array of all passed directories
- `$#` = count of arguments (number of directories)

---

## Line 12-14: Header Output
```bash
echo "=========================================="
echo "hDIFF v$VERSION (MD5, $num_dirs dirs)"
echo "=========================================="
```
- Prints banner showing version and number of directories

---

## Line 15-27: DIRECTORY SCANNING LOOP
```bash
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
```

**What it does:**
- `for ((idx=0; idx<num_dirs; idx++))` = loop through each directory index (0, 1, 2...)
- `find "$dir" -type f \( -name "*.log" -o ... \)` = finds specific file types
  - `.log`, `.txt`, `.json`, `.csv`, `.gz`, `.evtx` (Windows logs)
- `${f##*/}` = extracts just the filename (removes path)
- `echo "$fn|$idx|$f"` = writes "filename|directory_index|full_path" to all.txt
- Shows progress: "[0] Scanning: /path" then "[+] /path: 35 files"

**Output format:** `filename|dir_index|full_path`
Example: `dnf.log|0|/var/log/dnf.log`

---

## Line 28-30: Comparison Header
```bash
echo "[*] Comparing $num_dirs directories..."
```

---

## Line 32-40: CREATE HASH FILE
```bash
while read line; do
    fn="${line%%|*}"
    idx="${line%%|*}"
    idx="${line#*|}"
    idx="${idx%%|*}"
    fp="${line##*|}"
    h=$(md5sum "$fp" 2>/dev/null | cut -d' ' -f1)
    echo "$fn|$idx|$h|$fp"
done < "$WDIR/all.txt" > "$WDIR/hashes.txt"
```

**What it does:**
- Reads each line from all.txt
- Parses into parts: filename, directory index, full path
- Computes MD5 hash of each file: `md5sum "$fp" | cut -d' ' -f1`
- Writes to hashes.txt

**Parsing breakdown:**
- `fn="${line%%|*}"` = everything before first `|`
- `idx="${line#*|}"` = remove filename + first `|`, get directory index
- `fp="${line##*|}"` = everything after last `|` (full path)

**Output format:** `filename|dir_index|md5_hash|full_path`
Example: `dnf.log|0|a1b2c3d4|/var/log/dnf.log`

---

## Line 42-44: Initialize Output Files
```bash
> "$WDIR/same.txt"
> "$WDIR/diff.txt"
> "$WDIR/unique.txt"
```
- Creates empty files to store results
- `>` = write (overwrites if exists)

---

## Line 46-72: COMPARISON LOGIC
```bash
cut -d'|' -f1 "$WDIR/hashes.txt" | sort -u | while read fn; do
    [ -z "$fn" ] && continue

    entries=$(grep "^$fn|" "$WDIR/hashes.txt")
    count=$(echo "$entries" | wc -l)

    if [ "$count" -eq "$num_dirs" ]; then
        hashes=$(echo "$entries" | cut -d'|' -f3 | sort -u | wc -l)
        if [ "$hashes" -eq 1 ]; then
            paths=$(echo "$entries" | cut -d'|' -f4 | tr '\n' '|')
            echo "$fn|${paths%|}" >> "$WDIR/same.txt"
        else
            paths=$(echo "$entries" | cut -d'|' -f4 | tr '\n' '|')
            echo "$fn|${paths%|}" >> "$WDIR/diff.txt"
        fi
    elif [ "$count" -eq 1 ]; then
        path=$(echo "$entries" | cut -d'|' -f4)
        echo "$fn|$path" >> "$WDIR/unique.txt"
    else
        paths=$(echo "$entries" | cut -d'|' -f4 | tr '\n' '|')
        echo "$fn|${paths%|}" >> "$WDIR/diff.txt"
    fi
done
```

**Logic breakdown:**

1. `cut -d'|' -f1 ... | sort -u` = get unique filenames
2. `grep "^$fn|"` = find all entries for this filename
3. `count=$(wc -l)` = how many directories have this file

**Three cases:**

| Condition | Meaning | Action |
|----------|---------|--------|
| count == num_dirs | File in ALL dirs | Check hashes |
| count == 1 | File in ONE dir only | It's UNIQUE |
| count > 1 but < num_dirs | Some dirs | Mark as DIFFERENT |

**Hash comparison:**
- Get unique hashes: `cut -d'|' -f3 | sort -u | wc -l`
- If only 1 unique hash → SAME
- If multiple hashes → DIFFERENT

---

## Line 74-76: Count Results
```bash
same=$(wc -l < "$WDIR/same.txt")
diffc=$(wc -l < "$WDIR/diff.txt")
unique=$(wc -l < "$WDIR/unique.txt")
```
- Counts lines in each output file
- `wc -l` = word count (lines)

---

## Line 78: Total Files
```bash
total=$(wc -l < "$WDIR/all.txt")
```

---

## Line 80: End Timer
```bash
END=$(date +%s)
DURATION=$((END - START))
```
- Records end time
- Calculates duration in seconds

---

## Line 82-118: GENERATE REPORT
```bash
out="hdiff_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "..."
} > "$out"
```

**Report sections:**
1. Header with version and hash algorithm
2. Directory listing with file counts
3. Summary (SAME/DIFFERENT/UNIQUE counts)
4. FILES TO DELETE (SAME - identical in all dirs)
5. FILES TO REVIEW (DIFFERENT - same name, different content)
6. FILES TO KEEP (UNIQUE - only in one dir)

Each file shows:
- `[DEL]/[?!]/[KEEP]` marker
- Filename
- Path in each directory

---

## Line 120: Output and Finish
```bash
cat "$out"
echo "[+] $out"
```
- Displays report to screen
- Shows output filename

---

## Usage
```bash
./hdiff.sh /path1 /path2           # 2 directories
./hdiff.sh /path1 /path2 /path3   # 3 directories
```

## Return Codes
- `0` = success
- `1` = error (less than 2 directories provided)

---

*Last updated: 2026-04-14*