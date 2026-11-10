# Downloads the RMD and ADR .TAB files for sols 1500-1513 from the PDS Atmospheres
# Node REMS archive into  Downloads\rems_sols  (about 15 MB per sol).
#
# Run from PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\download_rems.ps1
#
# Safe to re-run: files already downloaded are skipped.
# Keep this to these sols; the site asks automated clients not to bulk-download.

$ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads much slower
$base = "https://atmos.nmsu.edu/PDS/data/mslrem_1001/DATA/SOL_01418_01514"
$out  = Join-Path $HOME "Downloads\rems_sols"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Exact file IDs for every sol from 1500 to 1513, taken from the archive links.
# If you change the sol range above, a sol missing from this table is looked
# up by reading its folder listing instead.
$knownIds = @{
    1500 = '530608083'
    1501 = '530696857'
    1502 = '530785632'
    1503 = '530874406'
    1504 = '530963181'
    1505 = '531051955'
    1506 = '531140729'
    1507 = '531229504'
    1508 = '531318278'
    1509 = '531407053'
    1510 = '531495827'
    1511 = '531584601'
    1512 = '531673376'
    1513 = '531762150'
}

foreach ($sol in 1500..1513) {
    $dir = "$base/SOL{0:D5}/" -f $sol
    $names = @()

    if ($knownIds.ContainsKey($sol)) {
        $id = $knownIds[$sol]
        foreach ($kind in 'RMD', 'ADR') {
            $names += "RME_$id$kind${sol}0000000_______P2.TAB"
        }
    } else {
        try {
            $page = Invoke-WebRequest -Uri $dir -UseBasicParsing
            $names = [regex]::Matches($page.Content, 'RME_\d+(?:RMD|ADR)\d+_+P2\.TAB') |
                ForEach-Object { $_.Value } | Sort-Object -Unique
        } catch {
            Write-Host "sol ${sol}: could not open $dir ($($_.Exception.Message))"
            continue
        }
        if (-not $names) {
            Write-Host "sol ${sol}: no RMD/ADR .TAB files found in the listing"
            continue
        }
    }

    foreach ($name in $names) {
        $dest = Join-Path $out $name
        if (Test-Path $dest) {
            Write-Host "sol ${sol}: have $name"
            continue
        }
        Write-Host "sol ${sol}: downloading $name"
        try {
            Invoke-WebRequest -Uri ($dir + $name) -OutFile $dest -UseBasicParsing
        } catch {
            Write-Host "sol ${sol}: FAILED $name ($($_.Exception.Message))"
            if (Test-Path $dest) { Remove-Item $dest }
        }
        Start-Sleep -Seconds 2
    }
}
Write-Host ""
Write-Host "Done. Files are in $out"
Get-ChildItem $out | Measure-Object | ForEach-Object { Write-Host "$($_.Count) files" }
