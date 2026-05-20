# ============================================================
# BigC IM Knowledge Hub — Hourly Sync Script
# รันโดย Claude Co-Work ทุกชั่วโมง 10:00–20:00 น.
# Option B: รับ updates จาก HUB_DIR/updates/ (submitted via API)
#           + QA/updates/ (local exports as fallback)
# ============================================================

param([switch]$Manual)

$HUB_DIR          = "D:\bigc-im-hub"
$HUB_UPDATES_DIR  = "$HUB_DIR\updates"          # ← จาก Vercel API (Option B)
$LOCAL_UPDATES_DIR= "D:\Big_C\Portal_IM\QA\updates"  # ← local fallback
$INDEX_FILE       = "$HUB_DIR\index.html"
$SYNCED_LOCAL     = "$LOCAL_UPDATES_DIR\_synced"
$TODAY            = Get-Date -Format "yyyy-MM-dd"
$NOW_ISO          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$NOW_DISPLAY      = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "=== BigC IM Hub Sync — $NOW_DISPLAY ===" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────
# STEP 1 — git pull ดึง updates ที่ทีมส่งมาผ่าน API
# ──────────────────────────────────────────────────────────
Write-Host "Pulling latest from GitHub..." -ForegroundColor Gray
Set-Location $HUB_DIR
$pullResult = git pull origin master 2>&1
Write-Host "  $pullResult" -ForegroundColor Gray

# ──────────────────────────────────────────────────────────
# STEP 2 — รวบรวม JSON files จากทั้งสองแหล่ง
# ──────────────────────────────────────────────────────────
$jsonFiles = @()

# แหล่ง A: HUB_DIR/updates/ (Option B — submitted via API)
if (Test-Path $HUB_UPDATES_DIR) {
    $hubFiles = Get-ChildItem -Path $HUB_UPDATES_DIR -Filter "*.json" -File |
                Where-Object { $_.Name -ne ".gitkeep" }
    if ($hubFiles.Count -gt 0) {
        Write-Host "Found $($hubFiles.Count) file(s) from Hub API: $($hubFiles.Name -join ', ')" -ForegroundColor Green
        $jsonFiles += $hubFiles
    }
}

# แหล่ง B: QA/updates/ (local fallback / morning-boot)
if (Test-Path $LOCAL_UPDATES_DIR) {
    $localFiles = Get-ChildItem -Path $LOCAL_UPDATES_DIR -Filter "*.json" -File |
                  Where-Object { $_.DirectoryName -eq $LOCAL_UPDATES_DIR }
    if ($localFiles.Count -gt 0) {
        Write-Host "Found $($localFiles.Count) file(s) from QA/updates/ (local): $($localFiles.Name -join ', ')" -ForegroundColor Gray
        $jsonFiles += $localFiles
    }
}

if ($jsonFiles.Count -eq 0) {
    Write-Host "No update files found — skipping sync." -ForegroundColor Yellow
    exit 0
}

# ──────────────────────────────────────────────────────────
# STEP 3 — อ่านและ merge entries ทั้งหมด
# ──────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────
# STEP 4 — อ่าน SHARED_UPDATES ที่มีอยู่ใน index.html
# ──────────────────────────────────────────────────────────
$html = Get-Content $INDEX_FILE -Raw -Encoding UTF8

$existingMatch = [regex]::Match($html, 'window\.SHARED_UPDATES\s*=\s*(\[[\s\S]*?\]);')
$existingEntries = @()
if ($existingMatch.Success) {
    try { $existingEntries = $existingMatch.Groups[1].Value | ConvertFrom-Json } catch { }
}

# ──────────────────────────────────────────────────────────
# STEP 5 — Merge + dedup ด้วย id เป็น key
# ──────────────────────────────────────────────────────────
$mergedDict = @{}
foreach ($e in $existingEntries) { $mergedDict["$($e.id)"] = $e }
foreach ($e in $allNew) {
    $key = "$($e.id)"
    if (-not $mergedDict.ContainsKey($key)) {
        $e | Add-Member -NotePropertyName "syncedAt"  -NotePropertyValue $NOW_ISO -Force
        $e | Add-Member -NotePropertyName "syncBatch" -NotePropertyValue $TODAY   -Force
        $mergedDict[$key] = $e
    }
}

$merged = $mergedDict.Values | Sort-Object { [DateTime]$_.ts } -Descending
$totalEntries = $merged.Count
Write-Host "Merged total: $totalEntries entries" -ForegroundColor Green

# ──────────────────────────────────────────────────────────
# STEP 6 — Build new SYNC_META + SHARED_UPDATES
# ──────────────────────────────────────────────────────────
$versionMatch = [regex]::Match($html, '"version"\s*:\s*(\d+)')
$currentVersion = if ($versionMatch.Success) { [int]$versionMatch.Groups[1].Value } else { 0 }
$newVersion = $currentVersion + 1

$sharedJson = $merged | ConvertTo-Json -Depth 10 -Compress
if ($merged.Count -eq 1) { $sharedJson = "[$sharedJson]" }

$syncMetaJson = "{`"syncedAt`":`"$NOW_ISO`",`"lastSyncedBy`":`"Claude Co-Work`",`"totalEntries`":$totalEntries,`"version`":$newVersion,`"nextScheduled`":`"ทุกชั่วโมง 10:00–20:00 น.`"}"

# ──────────────────────────────────────────────────────────
# STEP 7 — อัพเดท index.html
# ──────────────────────────────────────────────────────────
$html = [regex]::Replace($html,
    'window\.SHARED_UPDATES\s*=\s*\[[\s\S]*?\];',
    "window.SHARED_UPDATES = $sharedJson;")

$html = [regex]::Replace($html,
    'window\.SYNC_META\s*=\s*\{[\s\S]*?\};',
    "window.SYNC_META = $syncMetaJson;")

$html = $html -replace 'อัพเดทล่าสุด: \d{4}-\d{2}-\d{2}', "อัพเดทล่าสุด: $TODAY"

[System.IO.File]::WriteAllText($INDEX_FILE, $html, [System.Text.Encoding]::UTF8)
Write-Host "index.html updated ✅" -ForegroundColor Green

# ──────────────────────────────────────────────────────────
# STEP 8 — Archive processed files
# ──────────────────────────────────────────────────────────
$timestamp = Get-Date -Format "HHmm"

# Archive Hub API files (delete from updates/ so git diff stays clean)
foreach ($file in ($jsonFiles | Where-Object { $_.DirectoryName -eq $HUB_UPDATES_DIR })) {
    Remove-Item -Path $file.FullName -Force
    Write-Host "  Removed from updates/: $($file.Name)" -ForegroundColor Gray
}

# Archive local QA/updates/ files
if (-not (Test-Path $SYNCED_LOCAL)) { New-Item -ItemType Directory -Path $SYNCED_LOCAL -Force | Out-Null }
foreach ($file in ($jsonFiles | Where-Object { $_.DirectoryName -eq $LOCAL_UPDATES_DIR })) {
    $dest = "$SYNCED_LOCAL\${TODAY}_${timestamp}_$($file.Name)"
    Move-Item -Path $file.FullName -Destination $dest -Force
    Write-Host "  Archived local: $($file.Name) → _synced/" -ForegroundColor Gray
}

# ──────────────────────────────────────────────────────────
# STEP 9 — Git commit + push → Vercel auto-deploy
# ──────────────────────────────────────────────────────────
Set-Location $HUB_DIR
git add index.html 2>&1 | Out-Null
git commit -m "chore: sync updates $TODAY $(Get-Date -Format 'HHmm') (v$newVersion, $totalEntries entries)" 2>&1
git push origin master 2>&1

Write-Host ""
Write-Host "=== Sync Complete ===" -ForegroundColor Green
Write-Host "  New entries    : $($allNew.Count)"
Write-Host "  Total entries  : $totalEntries"
Write-Host "  Version        : v$newVersion"
Write-Host "  Vercel URL     : https://bigc-im-hub.vercel.app"
Write-Host "  Next sync      : ทุกชั่วโมง 10:00–20:00 น."
