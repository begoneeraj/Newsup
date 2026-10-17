param([switch]$Candidate, [string]$PolicyBaseUrl = '')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (!$Candidate -and !$PolicyBaseUrl.StartsWith('https://')) {
    throw 'Publish the policy files first, then supply -PolicyBaseUrl https://your-public-policy-site/. Use -Candidate only for a non-submittable local build.'
}
if (!(Test-Path 'android/key.properties') -and !$env:RELEASE_STORE_FILE) {
    throw 'Release signing configuration is required; debug signing is not allowed.'
}
$clientConfig = @{}
Get-Content '.env' | ForEach-Object {
    if ($_ -match '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY)=(.*)$') {
        $clientConfig[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
    }
}
if ($clientConfig.Count -ne 2) { throw 'Missing Supabase public client configuration.' }
$flutterPath = 'C:/flutter/bin/flutter.bat'
& $flutterPath build appbundle --release '--dart-define=PLAY_STORE=true' "--dart-define=POLICY_BASE_URL=$PolicyBaseUrl" "--dart-define=SUPABASE_URL=$($clientConfig['SUPABASE_URL'])" "--dart-define=SUPABASE_PUBLISHABLE_KEY=$($clientConfig['SUPABASE_PUBLISHABLE_KEY'])"
if ($LASTEXITCODE -ne 0) { throw 'App bundle build failed.' }
New-Item -ItemType Directory -Force release/play-store | Out-Null
$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)'
$releaseVersion = $versionLine.Matches[0].Groups[1].Value
$bundleName = if ($Candidate) { "TruthLensIndia-$releaseVersion-candidate.aab" } else { "TruthLensIndia-$releaseVersion.aab" }
Copy-Item -LiteralPath 'build/app/outputs/bundle/release/app-release.aab' -Destination "release/play-store/$bundleName"
Get-FileHash -Algorithm SHA256 "release/play-store/$bundleName"
