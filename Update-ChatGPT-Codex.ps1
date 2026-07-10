[CmdletBinding()]
param(
    [string]$StoreUrl = 'https://apps.microsoft.com/detail/9plm9xgg6vks?hl=zh-CN&gl=CN',
    [string]$DownloadDirectory = (Join-Path $env:USERPROFILE 'Downloads'),
    [ValidateSet('RP', 'Retail')]
    [string]$Ring = 'RP',
    [switch]$DownloadOnly,
    [switch]$ForceDownload,
    [switch]$ResolveOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$GeneratorHome = 'https://store.rg-adguard.net/'
$GeneratorApi = 'https://store.rg-adguard.net/api/GetFiles'
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/138.0.0.0 Safari/537.36'
$CurlPath = (Get-Command 'curl.exe' -ErrorAction Stop).Source
$TempDirectory = Join-Path ([IO.Path]::GetTempPath()) ("chatgpt-store-msix-updater-{0}" -f $PID)
$CookiePath = Join-Path $TempDirectory 'cookies.txt'
$HomePath = Join-Path $TempDirectory 'home.html'
$ResponsePath = Join-Path $TempDirectory 'packages.html'

function Write-Step {
    param([string]$Message)
    Write-Host ("`n==> {0}" -f $Message) -ForegroundColor Cyan
}

function ConvertFrom-HtmlFragment {
    param([string]$Html)
    $withoutTags = [regex]::Replace($Html, '<[^>]+>', '')
    return [System.Net.WebUtility]::HtmlDecode($withoutTags).Trim()
}

function ConvertTo-ByteSize {
    param([string]$Text)

    $match = [regex]::Match(
        $Text.Trim(),
        '^(?<number>\d+(?:\.\d+)?)\s*(?<unit>Bytes|KB|MB|GB)$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success) {
        return [long]0
    }

    $number = [double]::Parse($match.Groups['number'].Value, [Globalization.CultureInfo]::InvariantCulture)
    $multiplier = switch ($match.Groups['unit'].Value.ToUpperInvariant()) {
        'KB' { 1KB }
        'MB' { 1MB }
        'GB' { 1GB }
        default { 1 }
    }
    return [long]($number * $multiplier)
}

function Get-X64MsixCandidates {
    param([string]$Html)

    $rowPattern = '<tr\b[^>]*>(?<row>.*?)</tr>'
    $anchorPattern = '<a\b[^>]*\bhref\s*=\s*["''](?<href>[^"'']+)["''][^>]*>(?<name>.*?)</a>'
    $cellPattern = '<td\b[^>]*>(?<cell>.*?)</td>'
    $options = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline

    foreach ($rowMatch in [regex]::Matches($Html, $rowPattern, $options)) {
        $row = $rowMatch.Groups['row'].Value
        $anchor = [regex]::Match($row, $anchorPattern, $options)
        if (-not $anchor.Success) {
            continue
        }

        $fileName = ConvertFrom-HtmlFragment $anchor.Groups['name'].Value
        $nameMatch = [regex]::Match(
            $fileName,
            '^(?<package>.+)_(?<version>\d+(?:\.\d+){3})_x64__(?<publisher>[^\\/]+)\.msix$',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if (-not $nameMatch.Success) {
            continue
        }

        $cells = @([regex]::Matches($row, $cellPattern, $options))
        if ($cells.Count -lt 4) {
            continue
        }

        $sha1 = ConvertFrom-HtmlFragment $cells[2].Groups['cell'].Value
        if ($sha1 -notmatch '^[0-9a-fA-F]{40}$') {
            continue
        }

        $href = [System.Net.WebUtility]::HtmlDecode($anchor.Groups['href'].Value)
        try {
            $downloadUri = [Uri]$href
            $version = [Version]$nameMatch.Groups['version'].Value
        }
        catch {
            continue
        }

        if (-not $downloadUri.IsAbsoluteUri -or $downloadUri.Scheme -notin @('http', 'https')) {
            continue
        }
        if ($downloadUri.Host -notmatch '(^|\.)dl\.delivery\.mp\.microsoft\.com$') {
            continue
        }

        $size = ConvertFrom-HtmlFragment $cells[3].Groups['cell'].Value
        [PSCustomObject]@{
            FileName = $fileName
            PackageName = $nameMatch.Groups['package'].Value
            Version = $version
            DownloadUri = $downloadUri.AbsoluteUri
            Sha1 = $sha1.ToUpperInvariant()
            Expires = ConvertFrom-HtmlFragment $cells[1].Groups['cell'].Value
            Size = $size
            SizeBytes = ConvertTo-ByteSize $size
        }
    }
}

function Resolve-LatestPackage {
    $lastReason = 'The site returned no matching package.'

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Host ("Resolving package links (attempt {0}/3)..." -f $attempt)
        Remove-Item -LiteralPath $HomePath, $ResponsePath -Force -ErrorAction SilentlyContinue

        $homeArguments = @(
            '--silent', '--show-error', '--location', '--compressed',
            '--connect-timeout', '20', '--max-time', '60',
            '--retry', '2', '--retry-delay', '1',
            '--user-agent', $UserAgent,
            '--cookie-jar', $CookiePath,
            '--output', $HomePath,
            $GeneratorHome
        )
        & $CurlPath @homeArguments
        if ($LASTEXITCODE -ne 0) {
            $lastReason = 'Could not open the rg-adguard home page.'
            Start-Sleep -Seconds $attempt
            continue
        }

        $postArguments = @(
            '--silent', '--show-error', '--location', '--compressed',
            '--connect-timeout', '20', '--max-time', '120',
            '--retry', '2', '--retry-delay', '1',
            '--user-agent', $UserAgent,
            '--referer', $GeneratorHome,
            '--cookie', $CookiePath,
            '--cookie-jar', $CookiePath,
            '--header', 'Content-Type: application/x-www-form-urlencoded',
            '--data-urlencode', 'type=url',
            '--data-urlencode', ("url={0}" -f $StoreUrl),
            '--data-urlencode', ("ring={0}" -f $Ring),
            '--data-urlencode', 'lang=zh-CN',
            '--output', $ResponsePath,
            $GeneratorApi
        )
        & $CurlPath @postArguments
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ResponsePath)) {
            $lastReason = 'The rg-adguard API request failed.'
            Start-Sleep -Seconds $attempt
            continue
        }

        $html = Get-Content -LiteralPath $ResponsePath -Raw -Encoding UTF8
        if ($html -match 'Just a moment|cf-chl|challenge-platform|Enable JavaScript and cookies') {
            $lastReason = 'Cloudflare asked for an interactive browser check.'
            Start-Sleep -Seconds (2 * $attempt)
            continue
        }

        $candidates = @(Get-X64MsixCandidates -Html $html)
        if ($candidates.Count -gt 0) {
            # A Store response can also contain framework dependencies. The primary
            # app family is normally the largest x64 MSIX family in this product's
            # response; after finding that family, choose its newest version.
            $families = @(
                $candidates |
                    Group-Object -Property PackageName |
                    ForEach-Object {
                        [PSCustomObject]@{
                            PackageName = $_.Name
                            LargestBytes = ($_.Group | Measure-Object -Property SizeBytes -Maximum).Maximum
                        }
                    }
            )
            $primaryFamily = $families | Sort-Object -Property LargestBytes -Descending | Select-Object -First 1
            return $candidates |
                Where-Object { $_.PackageName -eq $primaryFamily.PackageName } |
                Sort-Object -Property Version -Descending |
                Select-Object -First 1
        }

        $lastReason = 'No x64 MSIX link was found in the response for this Store product.'
        Start-Sleep -Seconds $attempt
    }

    throw ("Could not resolve a download link after three attempts. {0} Open {1} in a browser once, complete any check, and run this script again." -f $lastReason, $GeneratorHome)
}

function Get-InstalledStorePackage {
    param([string]$Name)

    return Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
}

function Test-FileSha1 {
    param(
        [string]$Path,
        [string]$ExpectedSha1
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA1).Hash
    return $actual -eq $ExpectedSha1
}

try {
    $storeUri = [Uri]$StoreUrl
    if (-not $storeUri.IsAbsoluteUri -or $storeUri.Scheme -ne 'https' -or $storeUri.Host -ne 'apps.microsoft.com') {
        throw 'StoreUrl must be an https://apps.microsoft.com/ link.'
    }

    New-Item -ItemType Directory -Force -Path $TempDirectory | Out-Null

    Write-Step 'Checking the Microsoft Store package list via rg-adguard'
    $latest = Resolve-LatestPackage
    Write-Host ("Latest x64 package : {0}" -f $latest.FileName) -ForegroundColor Green
    Write-Host ("Internal app name  : {0}" -f $latest.PackageName)
    Write-Host ("Version            : {0}" -f $latest.Version)
    Write-Host ("Size               : {0}" -f $latest.Size)
    Write-Host ("Microsoft host     : {0}" -f ([Uri]$latest.DownloadUri).Host)

    if ($ResolveOnly) {
        Write-Host 'Resolve-only check completed successfully.' -ForegroundColor Green
        return
    }

    $installed = Get-InstalledStorePackage -Name $latest.PackageName
    if ($null -ne $installed) {
        $installedVersion = [Version]$installed.Version
        Write-Host ("Installed version  : {0}" -f $installedVersion)
        if (-not $DownloadOnly -and -not $ForceDownload -and $installedVersion -ge $latest.Version) {
            Write-Host 'The installed x64 app is already up to date. Nothing was downloaded.' -ForegroundColor Green
            return
        }
    }
    else {
        Write-Host 'Installed version  : not found'
    }

    New-Item -ItemType Directory -Force -Path $DownloadDirectory | Out-Null
    $destinationPath = Join-Path $DownloadDirectory $latest.FileName
    $partialPath = "{0}.partial" -f $destinationPath

    Write-Step ("Downloading to {0}" -f $destinationPath)
    if (Test-FileSha1 -Path $destinationPath -ExpectedSha1 $latest.Sha1) {
        Write-Host 'The complete package is already in the download folder; reusing it.' -ForegroundColor Green
    }
    else {
        $downloadArguments = @(
            '--fail', '--location',
            '--connect-timeout', '30',
            '--retry', '5', '--retry-delay', '2',
            '--continue-at', '-',
            '--output', $partialPath,
            '--progress-bar',
            $latest.DownloadUri
        )
        & $CurlPath @downloadArguments
        if ($LASTEXITCODE -ne 0) {
            throw ("Download failed with curl exit code {0}. The partial file was kept so the next run can resume it." -f $LASTEXITCODE)
        }

        Write-Host 'Checking SHA-1...'
        if (-not (Test-FileSha1 -Path $partialPath -ExpectedSha1 $latest.Sha1)) {
            Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
            throw 'The downloaded file hash did not match the package list. The invalid partial file was deleted.'
        }
        Move-Item -LiteralPath $partialPath -Destination $destinationPath -Force
    }

    Write-Step 'Checking the MSIX digital signature'
    $signature = Get-AuthenticodeSignature -LiteralPath $destinationPath
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw ("The MSIX signature is not valid (status: {0}). The package was not installed." -f $signature.Status)
    }
    Write-Host ("Valid signer: {0}" -f $signature.SignerCertificate.Subject) -ForegroundColor Green

    if ($DownloadOnly) {
        Write-Host ("Download completed: {0}" -f $destinationPath) -ForegroundColor Green
        return
    }

    if ($null -ne $installed -and ([Version]$installed.Version) -ge $latest.Version) {
        Write-Host 'The package was downloaded, but installation was skipped because this version (or a newer one) is already installed.' -ForegroundColor Green
        return
    }

    Write-Step 'Installing the x64 MSIX package'
    $addAppxCommand = Get-Command Add-AppxPackage -ErrorAction Stop
    $installParameters = @{
        Path = $destinationPath
        ErrorAction = 'Stop'
    }
    if ($addAppxCommand.Parameters.ContainsKey('ForceApplicationShutdown')) {
        $installParameters['ForceApplicationShutdown'] = $true
    }
    Add-AppxPackage @installParameters

    $verified = Get-InstalledStorePackage -Name $latest.PackageName
    if ($null -eq $verified -or ([Version]$verified.Version) -lt $latest.Version) {
        throw 'Add-AppxPackage returned, but the installed version could not be verified.'
    }

    Write-Host ("Update completed successfully. Installed version: {0}" -f $verified.Version) -ForegroundColor Green
    Write-Host ("Package kept at: {0}" -f $destinationPath)
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $TempDirectory) {
        Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
