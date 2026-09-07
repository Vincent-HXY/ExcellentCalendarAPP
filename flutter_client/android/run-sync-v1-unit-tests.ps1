param(
    [string]$GradleCache = "$env:USERPROFILE/.gradle/caches/modules-2/files-2.1",
    [ValidateSet('all', 'foundation')][string]$Suite = 'all'
)
$ErrorActionPreference = 'Stop'

# Independent JVM entry while unrelated Flutter/legacy test compilation is blocked.
# All versions below are already pinned/resolved by the Android build; no downloads or upgrades.
function Resolve-CachedJar([string]$Group, [string]$Artifact, [string]$Version) {
    $directory = Join-Path $GradleCache "$Group/$Artifact/$Version"
    $matches = @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter "$Artifact-$Version.jar")
    if ($matches.Count -ne 1) { throw "Expected one cached $Artifact $Version jar. Run the existing Gradle dependency resolution first." }
    return $matches[0].FullName
}

$stdlib = Resolve-CachedJar 'org.jetbrains.kotlin' 'kotlin-stdlib' '2.2.20'
$compiler = @(
    (Resolve-CachedJar 'org.jetbrains.kotlin' 'kotlin-compiler-embeddable' '2.2.20'),
    $stdlib,
    (Resolve-CachedJar 'org.jetbrains.kotlin' 'kotlin-script-runtime' '2.2.20'),
    (Resolve-CachedJar 'org.jetbrains.kotlin' 'kotlin-reflect' '1.6.10'),
    (Resolve-CachedJar 'org.jetbrains.kotlin' 'kotlin-daemon-embeddable' '2.2.20'),
    (Resolve-CachedJar 'org.jetbrains.kotlinx' 'kotlinx-coroutines-core-jvm' '1.8.0'),
    (Resolve-CachedJar 'org.jetbrains' 'annotations' '13.0')
)
$runtime = @(
    $stdlib,
    (Resolve-CachedJar 'junit' 'junit' '4.13.2'),
    (Resolve-CachedJar 'org.hamcrest' 'hamcrest-core' '1.3'),
    (Resolve-CachedJar 'org.json' 'json' '20240303')
)
$packagePath = 'kotlin/com/excellentcalendar/excellent_calendar/bridge/sync'
$mainSources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "app/src/main/$packagePath") -File -Filter '*.kt')
$testSources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "app/src/test/$packagePath") -File -Filter '*.kt')
$testClasses = @($testSources | Where-Object { $_.BaseName.EndsWith('Test') } | ForEach-Object {
    "com.excellentcalendar.excellent_calendar.bridge.sync.$($_.BaseName)"
})
if ($Suite -eq 'foundation') {
    Write-Output 'FOUNDATION SUBSET ONLY: excludes the unresolved Contract preflight; not a plan completion gate.'
    $testClasses = @($testClasses | Where-Object { -not $_.EndsWith('.ContractPreflightTest') })
}
$outputDirectory = Join-Path $PSScriptRoot "../build/sync-v1-jvm/$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$jar = Join-Path $outputDirectory 'tests.jar'
$arguments = @('-cp', ($compiler -join [IO.Path]::PathSeparator), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
    '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', ($runtime -join [IO.Path]::PathSeparator), '-d', $jar)
$arguments += @($mainSources.FullName) + @($testSources.FullName)
& java @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$arguments = @('-cp', ((@($jar) + $runtime) -join [IO.Path]::PathSeparator), 'org.junit.runner.JUnitCore') + $testClasses
Push-Location $PSScriptRoot
try {
    & java @arguments 2>&1 | Tee-Object -FilePath (Join-Path $outputDirectory 'junit.txt')
    $testExitCode = $LASTEXITCODE
} finally { Pop-Location }
Write-Output "Evidence: $outputDirectory"
exit $testExitCode
