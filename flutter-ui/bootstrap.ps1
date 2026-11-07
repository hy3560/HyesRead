param([switch]$NoTest)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$localFlutter = Join-Path $PSScriptRoot '.flutter_sdk\bin\flutter.bat'
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $localFlutter) {
    $flutterExe = $localFlutter
} elseif ($null -ne $flutterCommand) {
    $flutterExe = $flutterCommand.Source
} else {
    throw 'Flutter SDK missing. See https://docs.flutter.dev/get-started/install/windows .'
}

$protected = @(
    'pubspec.yaml',
    'lib\main.dart',
    'lib\data\book_entry.dart',
    'lib\data\library_repository.dart',
    'lib\data\text_blocks.dart',
    'lib\ui\app_shell.dart',
    'lib\ui\app_theme.dart',
    'lib\ui\glass_widgets.dart',
    'lib\ui\paper_dock.dart',
    'lib\design\tokens.dart',
    'lib\design\motion.dart',
    'lib\widgets\book_cover.dart',
    'lib\widgets\book_spine_wall.dart',
    'lib\widgets\appearance_paper.dart',
    'lib\debug\demo_shelf.dart',
    'lib\widgets\empty_shelf_art.dart',
    'lib\widgets\paper_controls.dart',
    'lib\widgets\rive_ink_waves.dart',
    'lib\widgets\ink_stamp.dart',
    'lib\widgets\paper_button.dart',
    'lib\widgets\resume_carousel.dart',
    'lib\widgets\book_open_route.dart',
    'lib\widgets\shelf_filter_bar.dart',
    'lib\widgets\import_arrival.dart',
    'assets\fonts\HyesSerifSC-SemiBold.ttf',
    'assets\fonts\LICENSE_NOTICE.md',
    'lib\ui\reader_page.dart',
    'lib\ui\reader_controls.dart',
    'lib\ui\reader_views.dart',
    'lib\ui\reader_typography.dart',
    'lib\ui\text_page_layout.dart',
    'lib\ui\sample_book_preview.dart',
    'lib\widgets\text_page_reader.dart',
    'test\library_repository_test.dart',
    'test\text_blocks_test.dart',
    'test\reader_typography_test.dart',
    'test\glass_widgets_test.dart',
    'test\paper_dock_test.dart',
    'test\book_cover_test.dart',
    'test\demo_shelf_test.dart',
    'test\motion_stack_test.dart',
    'test\ui_shell_test.dart',
    'test\text_page_turn_test.dart',
    'test\paper_page_visual_test.dart',
    'test\goldens\desktop-focus-reader.png',
    'test\goldens\desktop-paged-reader.png',
    'test\goldens\desktop-resume.png',
    'test\goldens\phone-books-large-text.png',
    'test\goldens\paper-covers-light.png',
    'test\goldens\paper-covers-dark.png',
    'test\goldens\demo-shelf-light.png',
    'test\goldens\demo-shelf-dark.png',
    'windows\CMakeLists.txt',
    'windows\runner\main.cpp',
    'windows\runner\Runner.rc',
    'tool\build_windows_portable.ps1',
    'tool\package_windows_portable.ps1',
    'WINDOWS_PREVIEW.md'
)
$hashes = @{}
foreach ($rel in $protected) {
    if (-not (Test-Path -LiteralPath $rel)) { throw ('Missing source file: ' + $rel) }
    $hashes[$rel] = (Get-FileHash -LiteralPath $rel -Algorithm SHA256).Hash
}

Write-Host 'Checking Flutter environment...'
& $flutterExe doctor -v
if ($LASTEXITCODE -ne 0) { throw 'Flutter doctor failed.' }

# --overwrite deliberately absent; preserve all authored Dart files.
if (-not (Test-Path -LiteralPath 'windows\CMakeLists.txt') -or
    -not (Test-Path -LiteralPath 'android\app\build.gradle.kts')) {
    Write-Host 'Creating missing Windows/Android runner templates...'
    & $flutterExe create --platforms=android,windows --project-name hyesread_flutter --org com.hyes .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter create failed.' }
} else {
    Write-Host 'Existing independent Windows/Android runner templates found.'
}

foreach ($rel in $protected) {
    $current = (Get-FileHash -LiteralPath $rel -Algorithm SHA256).Hash
    if ($current -ne $hashes[$rel]) {
        throw ('Flutter template changed source file: ' + $rel)
    }
}

Write-Host 'Resolving dependencies...'
& $flutterExe pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get failed. On Windows plugin symlinks may require Windows Developer Mode.' }

if (-not $NoTest) {
    Write-Host 'Running Flutter analyzer...'
    & $flutterExe analyze --no-pub --no-fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed. Do not ship.' }
    Write-Host 'Running Flutter tests...'
    & $flutterExe test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter test failed. Do not ship.' }
}

Write-Host 'Tool checks processed; Windows/Android still require flutter run and real device QA.'
