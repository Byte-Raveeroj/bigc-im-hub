# ============================================================
# BigC IM Knowledge Hub — Daily Sync Script
# รันโดย Claude Co-Work ทุกวัน 09:03 น.
# ============================================================

param([switch]$Manual)

$HUB_DIR     = "D:\bigc-im-hub"
$UPDATES_DIR = "D:\Big_C\Portal_IM\QA\updates"
$INDEX_FILE  = "$HUB_DIR\index.html"
$SYNCED_DIR  = "$UPDATES_DIR\_synced"
$TODAY       = Get-Date -Format "yyyy-MM-dd"
$NOW_ISO     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$NOW_DISPLAY = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "=== BigC IM Hub Sync — $NOW_DISPLAY ===" -ForegroundColor Cyan

# 1. สแกนหาไฟล์ JSON ใน QA/updates/
if (-not (Test-Path $UPDATES_DIR)) {
    New-Item -ItemType Directory -Path $UPDATES_DIR -Force | Out-Null
    Write-Host "Created QA/updates/ folder. No files to sync today." -ForegroundColor Yellow
    exit 0
}

$jsonFiles = Get-ChildItem -Path $UPDATES_DIR -Filter "*.json" -File |
             Where-Object { $_.DirectoryName -eq $UPDATES_DIR }

if ($jsonFiles.Count -eq 0) {
    Write-Host "No update files found in QA/updates/ — skipping sync." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($jsonFiles.Count) file(s): $($jsonFiles.Name -join ', ')" -ForegroundColor Green

# 2. อ่านและ merge entries ทั้งหมด
$allNew = @()
foreach ($file in $jsonFiles) {
    try {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $data    = $content | ConvertFrom-Json
        $entries = if ($data.entries) { $data.entries } else { $data }
        if ($entries -is [Array] -or $entries -is [System.Collections.ArrayList]) {
            $allNew += $entries
            Write-Host "  Read $($entries.Count) entries from $($file.Name)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Warning: Could not parse $($file.Name) — skipping" -ForegroundColor Yellow
    }
}

if ($allNew.Count -eq 0) {
    Write-Host "No valid entries found — skipping sync." -ForegroundColor Yellow
    exit 0
}

# 3. อ่าน SHARED_UPDATES ที่มีอยู่ใน index.html (ถ้ามี)
$html = Get-Content $INDEX_FILE -Raw -Encoding UTF8

$existingMatch = [regex]::Match($html, 'window\.SHARED_UPDATES\s*=\s*(\[[\s\S]*?\]);')
$existingEntries = @()
if ($existingMatch.Success) {
    try {
        $existingEntries = $existingMatch.Groups[1].Value | ConvertFrom-Json
    } catch { }
}

# 4. Merge + dedup โดยใช้ id เป็น key
$mergedDict = @{}
foreach ($e in $existingEntries) { $mergedDict["$($e.id)"] = $e }
foreach ($e in $allNew) {
    $key = "$($e.id)"
    if (-not $mergedDict.ContainsKey($key)) {
        # เพิ่ม sync metadata
        $e | Add-Member -NotePropertyName "syncedAt"   -NotePropertyValue $NOW_ISO   -Force
        $e | Add-Member -NotePropertyName "syncBatch"  -NotePropertyValue $TODAY     -Force
        $mergedDict[$key] = $e
    }
}

# Sort descending by ts
$merged = $mergedDict.Values | Sort-Object { [DateTime]$_.ts } -Descending

$totalEntries = $merged.Count
Write-Host "Merged total: $totalEntries entries" -ForegroundColor Green

# 5. อ่าน version ปัจจุบัน แล้ว +1
$versionMatch = [regex]::Match($html, '"version"\s*:\s*(\d+)')
$currentVersion = if ($versionMatch.Success) { [int]$versionMatch.Groups[1].Value } else { 0 }
$newVersion = $currentVersion + 1

# 6. สร้าง JSON strings
$sharedJson = $merged | ConvertTo-Json -Depth 10 -Compress
if ($merged.Count -eq 1) { $sharedJson = "[$sharedJson]" }  # ensure array

$syncMetaJson = "{`"syncedAt`":`"$NOW_ISO`",`"lastSyncedBy`":`"Claude Co-Work (09:03)`",`"totalEntries`":$totalEntries,`"version`":$newVersion,`"nextScheduled`":`"09:00 น. ทุกวัน`"}"

# 7. อัพเดท HTML
$html = [regex]::Replace($html,
    'window\.SHARED_UPDATES\s*=\s*\[[\s\S]*?\];',
    "window.SHARED_UPDATES = $sharedJson;")

$html = [regex]::Replace($html,
    'window\.SYNC_META\s*=\s*\{[\s\S]*?\};',
    "window.SYNC_META = $syncMetaJson;")

# อัพเดท footer date
$html = $html -replace 'อัพเดทล่าสุด: \d{4}-\d{2}-\d{2}', "อัพเดทล่าสุด: $TODAY"

# บันทึก
[System.IO.File]::WriteAllText($INDEX_FILE, $html, [System.Text.Encoding]::UTF8)
Write-Host "index.html updated ✅" -ForegroundColor Green

# 8. ย้ายไฟล์ JSON ที่ sync แล้วไป _synced/
if (-not (Test-Path $SYNCED_DIR)) {
    New-Item -ItemType Directory -Path $SYNCED_DIR -Force | Out-Null
}
$timestamp = Get-Date -Format "HHmm"
foreach ($file in $jsonFiles) {
    $dest = "$SYNCED_DIR\${TODAY}_${timestamp}_$($file.Name)"
    Move-Item -Path $file.FullName -Destination $dest -Force
    Write-Host "  Archived: $($file.Name) → _synced/" -ForegroundColor Gray
}

# 9. Git commit + push → Vercel auto-deploy
Set-Location $HUB_DIR
git add index.html 2>&1 | Out-Null
git commit -m "chore: sync team updates $TODAY (v$newVersion, $totalEntries entries)" 2>&1
git push origin master 2>&1

Write-Host ""
Write-Host "=== Sync Complete ===" -ForegroundColor Green
Write-Host "  Entries synced : $($allNew.Count) new + $($existingEntries.Count) existing = $totalEntries total"
Write-Host "  Version        : v$newVersion"
Write-Host "  Vercel URL     : https://bigc-im-hub.vercel.app"
Write-Host "  Next sync      : Tomorrow 09:03"
