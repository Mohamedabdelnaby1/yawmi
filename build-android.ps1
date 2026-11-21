param(
    [string]$Flutter = 'flutter',
    [ValidateSet('APK', 'AAB')][string]$Format = 'APK',
    [switch]$Distribution,
    [switch]$GithubUpdates,
    [switch]$Offline,
    [string]$Output,
    [string]$FacebookUrl = '',
    [string]$PrivacyUrl = ''
)

$ErrorActionPreference = 'Stop'
$policyAddress = $null
if ($PrivacyUrl -and (-not [Uri]::TryCreate($PrivacyUrl, [UriKind]::Absolute, [ref]$policyAddress) -or
    $policyAddress.Scheme -ne 'https' -or -not $policyAddress.Host -or $policyAddress.UserInfo)) {
    throw 'PrivacyUrl must use an absolute HTTPS URL without credentials.'
}
if ($Distribution -and ($Format -ne 'AAB' -or -not $PrivacyUrl)) {
    throw 'Distribution requires -Format AAB and -PrivacyUrl.'
}
if ($GithubUpdates -and $Format -ne 'APK') {
    throw 'GitHub in-app updates require an APK.'
}
if (-not $Output) {
    $versionLine = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pubspec.yaml') |
        Select-String '^version: ([^+\s]+)\+' | Select-Object -First 1
    $version = $versionLine.Matches[0].Groups[1].Value
    $file = if ($Format -eq 'APK') { "Yawmi-$version-Android.apk" }
        elseif ($Distribution) { "Yawmi-$version-Play.aab" }
        else { "Yawmi-$version-Unsigned.aab" }
    $Output = Join-Path $PSScriptRoot "outputs\$file"
}
$flutterCommand = (Get-Command $Flutter -ErrorAction Stop).Source
$outputPath = [IO.Path]::GetFullPath($Output)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())

if ($tempRoot -match '[^\x00-\x7F]') {
    throw 'Set TEMP to an accessible path with ASCII characters before building on Windows.'
}

$buildPath = Join-Path $tempRoot ('YawmiBuild-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildPath | Out-Null
$previousSigningMode = $env:YAWMI_SIGNING_MODE
$previousUpdateMode = $env:YAWMI_GITHUB_UPDATES
$env:YAWMI_GITHUB_UPDATES = if ($GithubUpdates) { 'true' } else { 'false' }
$env:YAWMI_SIGNING_MODE = if ($Distribution) { 'release' }
    elseif ($Format -eq 'AAB') { 'unsigned' }
    else { 'testing' }

try {
    foreach ($folder in ('android', 'assets', 'lib')) {
        & robocopy (Join-Path $PSScriptRoot $folder) (Join-Path $buildPath $folder) /E /XD .gradle build /XF local.properties '*.iml' /NJH /NJS /NDL /NFL /NP
        if ($LASTEXITCODE -ge 8) {
            throw "Unable to stage $folder."
        }
    }

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pubspec.yaml'), (Join-Path $PSScriptRoot 'pubspec.lock') -Destination $buildPath
    Push-Location -LiteralPath $buildPath
    try {
        $pubArgs = @('pub', 'get')
        if ($Offline) { $pubArgs += '--offline' }
        & $flutterCommand @pubArgs
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed to resolve.' }
        $target = if ($Format -eq 'AAB') { 'appbundle' } else { 'apk' }
        $buildArgs = @('build', $target, '--release', '--no-pub')
        if ($FacebookUrl) { $buildArgs += "--dart-define=YAWMI_FACEBOOK_URL=$FacebookUrl" }
        if ($PrivacyUrl) { $buildArgs += "--dart-define=YAWMI_PRIVACY_URL=$PrivacyUrl" }
        & $flutterCommand @buildArgs
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
        New-Item -ItemType Directory -Force (Split-Path -Parent $outputPath) | Out-Null
        $artifact = if ($Format -eq 'AAB') { 'build\app\outputs\bundle\release\app-release.aab' }
            else { 'build\app\outputs\flutter-apk\app-release.apk' }
        Copy-Item -LiteralPath $artifact -Destination $outputPath
        Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
    } finally {
        Pop-Location
    }
} finally {
    $env:YAWMI_SIGNING_MODE = $previousSigningMode
    $env:YAWMI_GITHUB_UPDATES = $previousUpdateMode
    $resolvedBuild = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $buildPath).ProviderPath)
    if ($resolvedBuild -eq $buildPath -and
        $resolvedBuild.StartsWith((Join-Path $tempRoot 'YawmiBuild-'), [StringComparison]::OrdinalIgnoreCase)) {
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            try {
                Remove-Item -LiteralPath $resolvedBuild -Recurse -Force
                break
            } catch {
                if ($attempt -eq 2) {
                    Write-Warning "Android build tools are still using the temporary directory: $resolvedBuild"
                } else {
                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }
}
