param(
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$NotesFile,
    [Parameter(Mandatory)][string]$BuildTools
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:GIT_TERMINAL_PROMPT = '0'
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$notes = Get-Content -LiteralPath $NotesFile -Raw -Encoding utf8
$buildToolsPath = (Resolve-Path -LiteralPath $BuildTools).Path
$root = Split-Path -Parent $PSScriptRoot
$project = 'Mohamedabdelnaby1/yawmi'
$api = "https://api.github.com/repos/$project"

Push-Location -LiteralPath $root
try {
    if (git status --porcelain --untracked-files=no) {
        throw 'Commit the release source before publishing.'
    }
    $commit = (git rev-parse HEAD).Trim()
    $versionLine = Get-Content -LiteralPath 'pubspec.yaml' | Select-String '^version: (\d+\.\d+\.\d+)\+(\d+)$'
    if (!$versionLine) { throw 'Release version is missing.' }
    $version = $versionLine.Matches[0].Groups[1].Value
    $build = $versionLine.Matches[0].Groups[2].Value
    $tag = "v$version"
    $badging = & "$buildToolsPath/aapt2.exe" dump badging $apkPath
    if ($LASTEXITCODE -ne 0 -or !($badging -match "^package: name='app.yawmi.journal' versionCode='$build' versionName='$version'")) {
        throw 'APK package or version differs from the source.'
    }
    $manifest = & "$buildToolsPath/aapt2.exe" dump xmltree --file AndroidManifest.xml $apkPath
    if ($LASTEXITCODE -ne 0 -or !($manifest -match 'android.permission.REQUEST_INSTALL_PACKAGES')) {
        throw 'Build the APK with -GithubUpdates.'
    }
    $verified = & "$buildToolsPath/apksigner.bat" verify --print-certs $apkPath
    $official = 'f74ebb7ce04fec9a545e73676ba8a6330bd9210991a27229f4d24f1095f5db92'
    if ($LASTEXITCODE -ne 0 -or !($verified -match "certificate SHA-256 digest: $official$")) {
        throw 'APK must use the existing Yawmi direct-download signing certificate.'
    }
    & "$buildToolsPath/zipalign.exe" -c -P 16 4 $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'APK alignment is invalid.' }

    $request = "protocol=https`nhost=github.com`nusername=Mohamedabdelnaby1`n`n"
    $credentials = $request | git -c credential.interactive=never credential fill 2>$null
    $credential = $credentials | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if (!$credential) { throw 'Sign in to GitHub Git Credential Manager first.' }
    $headers = @{
        Authorization = 'Bearer ' + $credential.Substring(9)
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $remote = Invoke-RestMethod -Headers $headers -Uri "$api/branches/main"
    if ($remote.commit.sha -ne $commit) { throw 'Push this commit to GitHub main before publishing.' }
    $latest = Invoke-RestMethod -Headers $headers -Uri "$api/releases/latest"
    if ([version]$version -le [version]($latest.tag_name.TrimStart('v'))) {
        throw 'The new release must be newer than the latest public release.'
    }

    $releases = Invoke-RestMethod -Headers $headers -Uri "$api/releases?per_page=30"
    $release = $releases | Where-Object { $_.tag_name -eq $tag } | Select-Object -First 1
    if (!$release) {
        $release = Invoke-RestMethod -Method Post -Headers $headers -Uri "$api/releases" -ContentType 'application/json' -Body (@{
            tag_name = $tag
            target_commitish = $commit
            name = "يومي · Yawmi $version"
            body = $notes
            draft = $true
            prerelease = $false
        } | ConvertTo-Json)
    }
    if (!$release.draft -or $release.target_commitish -ne $commit) { throw 'Existing release does not match this commit.' }

    $upload = $release.upload_url.Split('{')[0]
    if (([uri]$upload).Scheme -ne 'https' -or ([uri]$upload).Host -ne 'uploads.github.com') {
        throw 'Unexpected GitHub upload endpoint.'
    }
    $hash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumPath = [IO.Path]::GetTempFileName()
    try {
        "$hash  Yawmi-Android.apk" | Set-Content -Encoding ascii -LiteralPath $checksumPath
        foreach ($file in @(
            @{ name = 'Yawmi-Android.apk'; path = $apkPath; type = 'application/vnd.android.package-archive' },
            @{ name = 'Yawmi-Android.apk.sha256'; path = $checksumPath; type = 'text/plain' }
        )) {
            $fileHash = (Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash.ToLowerInvariant()
            $asset = $release.assets | Where-Object { $_.name -eq $file.name } | Select-Object -First 1
            if (!$asset) {
                $asset = Invoke-RestMethod -Method Post -Uri ($upload + '?name=' + [uri]::EscapeDataString($file.name)) -Headers $headers -ContentType $file.type -InFile $file.path
            }
            if ($asset.state -ne 'uploaded' -or $asset.digest -ne "sha256:$fileHash") {
                throw "Unable to verify $($file.name) in draft release."
            }
            Write-Output "Verified $($file.name)"
        }
    } finally {
        Remove-Item -LiteralPath $checksumPath
    }
    $published = Invoke-RestMethod -Method Patch -Headers $headers -Uri "$api/releases/$($release.id)" -ContentType 'application/json' -Body '{"draft":false,"make_latest":"true"}'
    if ($published.draft -or $published.tag_name -ne $tag) { throw 'Unexpected release state.' }
    Write-Output $published.html_url
} finally {
    Pop-Location
}
