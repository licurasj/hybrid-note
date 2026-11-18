# Builds the portfolio demo (T-18, DEMO_BUILD=true) into build/web without
# Google's sign-in script (PX-2, Q-144). Real builds are not affected.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_demo_web.ps1
#
# The public reCAPTCHA site key comes from -SiteKey or the RECAPTCHA_SITE_KEY
# environment variable, as for the real web build; it is never printed.
# -Flutter names the flutter command when it is not on PATH (for example
# D:\DevTools\flutter\bin\flutter.bat).
#
# For the build only, a temporary pubspec_overrides.yaml points
# google_sign_in_web at the do-nothing stub in tool/demo_stubs/. Afterwards,
# also on failure, the file is removed, pubspec.lock is put back byte for byte
# and `flutter pub get` restores the normal package set.
param(
  [string]$SiteKey = $env:RECAPTCHA_SITE_KEY,
  [string]$Flutter = 'flutter'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SiteKey)) {
  Write-Error 'No site key: pass -SiteKey or set RECAPTCHA_SITE_KEY.'
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$overrides = Join-Path $root 'pubspec_overrides.yaml'
$lockPath = Join-Path $root 'pubspec.lock'
if (Test-Path $overrides) {
  Write-Error 'pubspec_overrides.yaml already exists; remove it first.'
}

function Invoke-Flutter([string[]]$arguments) {
  & $Flutter @arguments
  if ($LASTEXITCODE -ne 0) { throw "flutter $($arguments[0..1] -join ' ') failed ($LASTEXITCODE)" }
}

$lock = [IO.File]::ReadAllBytes($lockPath)
$failed = $false
try {
  $text = "# Temporary, written by tool/build_demo_web.ps1 (T-18 PX-2); never commit.`n" +
    "dependency_overrides:`n" +
    "  google_sign_in_web:`n" +
    "    path: tool/demo_stubs/google_sign_in_web`n"
  [IO.File]::WriteAllText($overrides, $text)

  Invoke-Flutter @('pub', 'get')
  Write-Host 'flutter build web --release --base-href /demos/hybrid-notes/ --no-web-resources-cdn --dart-define=DEMO_BUILD=true --dart-define=RECAPTCHA_SITE_KEY=<hidden>'
  Invoke-Flutter @('build', 'web', '--release', '--base-href', '/demos/hybrid-notes/',
    '--no-web-resources-cdn', '--dart-define=DEMO_BUILD=true',
    "--dart-define=RECAPTCHA_SITE_KEY=$SiteKey")

  $web = Join-Path $root 'build/web'
  # Nothing registers the service worker (web/flutter_bootstrap.js); drop the file.
  Remove-Item (Join-Path $web 'flutter_service_worker.js') -ErrorAction SilentlyContinue
  if (Select-String -Path (Join-Path $web 'main.dart.js') -SimpleMatch 'gsi/client' -Quiet) {
    throw 'build/web/main.dart.js still refers to gsi/client: the stub was not used.'
  }
} catch {
  $failed = $true
  Write-Host "Demo build failed: $_" -ForegroundColor Red
} finally {
  Remove-Item $overrides -ErrorAction SilentlyContinue
  [IO.File]::WriteAllBytes($lockPath, $lock)
  try { Invoke-Flutter @('pub', 'get') } catch {
    Write-Host "Restoring packages failed ($_); run flutter pub get by hand." -ForegroundColor Red
    $failed = $true
  }
}
if ($failed) { exit 1 }
Write-Host 'Demo build ready in build/web (no gsi/client, no service worker file).'
