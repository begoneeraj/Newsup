# Local dev runner for the Pixel 6 emulator — reads Supabase creds from
# .env (gitignored) so the values only live in one place.
$envFile = Join-Path $PSScriptRoot ".env"
$vars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)=(.*)$') {
        $vars[$matches[1]] = $matches[2]
    }
}

flutter run -d emulator-5554 `
    --dart-define=SUPABASE_URL=$($vars['SUPABASE_URL']) `
    --dart-define=SUPABASE_PUBLISHABLE_KEY=$($vars['SUPABASE_PUBLISHABLE_KEY'])
