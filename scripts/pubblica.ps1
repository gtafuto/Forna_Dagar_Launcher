<#
.SYNOPSIS
  Compila Windows su questo PC e pubblica una nuova versione come Release di
  GitHub (zip + manifest.json), da cui la scarica il Forna Dagar Launcher.

.DESCRIPTION
  Alternativa alla compilazione su GitHub Actions: piu veloce (usa la cache
  della tua compilazione locale) e non consuma i minuti gratuiti di GitHub.
  Il launcher degli utenti funziona in modo identico.

  Cosa fa, in ordine:
    1. controlla i prerequisiti e che il codice sia su GitHub e senza modifiche
    2. flutter pub get + flutter build windows --release
    3. crea lo zip e il manifest.json (versione, SHA-256, dimensione)
    4. crea la Release con GitHub CLI

  Prerequisiti (una tantum): Flutter, Git, GitHub CLI (https://cli.github.com)
  e l'accesso con:  gh auth login

.PARAMETER Version
  Versione da pubblicare, senza la "v" (es. 0.1.1 oppure 0.1.1-test1).

.PARAMETER Notes
  Testo della Release (facoltativo).

.PARAMETER Yes
  Non chiedere conferma.

.PARAMETER NoPublish
  Prova: compila e prepara zip e manifest, ma non pubblica nulla.

.EXAMPLE
  .\scripts\pubblica.ps1 0.1.1

.EXAMPLE
  .\scripts\pubblica.ps1 0.1.1-test1 -NoPublish
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,
    [string]$Notes,
    [switch]$Yes,
    [switch]$NoPublish
)

$ErrorActionPreference = 'Stop'

# ---- Configurazione di questo progetto (l'unica parte che cambia tra i repository) ----
$AppId   = 'forna_dagar_launcher'
$AppName = 'Forna Dagar Launcher'
$ExeName = 'forna_dagar_launcher.exe'
$Repo    = 'gtafuto/Forna_Dagar_Launcher'
# ---------------------------------------------------------------------------------------

function Step([string]$Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Fail([string]$Text) {
    Write-Host ''
    Write-Host "ERRORE: $Text" -ForegroundColor Red
    exit 1
}

# Esegue un comando esterno e si ferma se fallisce.
function Run-Native([string]$What, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        Fail "$What non e riuscito (codice $LASTEXITCODE)."
    }
}

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
    Fail "Non trovo pubspec.yaml nella cartella ${root} (lo script deve stare nella sottocartella scripts del progetto)."
}

# ---- 1. Prerequisiti ----
Step 'Controllo dei prerequisiti'
foreach ($tool in 'flutter', 'git', 'tar') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Fail "Non trovo '$tool' nel PATH."
    }
}
if (-not $NoPublish) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Fail 'Non trovo GitHub CLI (gh). Installala da https://cli.github.com e poi esegui: gh auth login'
    }
    cmd /c 'gh auth status >nul 2>&1'
    if ($LASTEXITCODE -ne 0) {
        Fail 'GitHub CLI non e collegata al tuo account. Esegui: gh auth login'
    }
}

if ($Version -notmatch '^\d+\.\d+\.\d+([-.][0-9A-Za-z.]+)?$') {
    Fail "Versione non valida: '$Version' (atteso es. 0.1.1 oppure 0.1.1-test1)."
}
$tag = "v$Version"

# ---- Stato del repository ----
Step 'Controllo del repository'
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$sha = (git rev-parse HEAD).Trim()
$short = $sha.Substring(0, 7)
# pubspec.lock e analysis_options.yaml sono esclusi: Flutter li aggiorna da solo a ogni "pub get",
# e senza questa esclusione lo script si rifiuterebbe di ripartire dopo la prima esecuzione.
$dirty = @(git status --porcelain -- . ':(exclude)pubspec.lock' ':(exclude)analysis_options.yaml').Count
if ($dirty -gt 0) {
    $msg = "Ci sono $dirty file modificati non salvati (vedi git status): la versione pubblicata non corrisponderebbe al codice su GitHub."
    if ($NoPublish) { Write-Host "ATTENZIONE: $msg" -ForegroundColor Yellow } else { Fail "$msg Fai commit e push, poi riprova." }
}
git fetch origin --quiet
$onRemote = @(git branch -r --contains $sha).Count
if ($onRemote -eq 0) {
    $msg = "Il commit $short non e ancora su GitHub."
    if ($NoPublish) { Write-Host "ATTENZIONE: $msg" -ForegroundColor Yellow } else { Fail "$msg Esegui prima: git push" }
}
if (-not $NoPublish) {
    cmd /c "gh release view $tag --repo $Repo >nul 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Fail "La Release $tag esiste gia su $Repo. Scegli un'altra versione."
    }
}

Write-Host ''
Write-Host "  Progetto : $AppName ($Repo)"
Write-Host "  Ramo     : $branch"
Write-Host "  Commit   : $short"
Write-Host "  Versione : $Version (tag $tag)"
if ($NoPublish) { Write-Host '  MODALITA PROVA: non viene pubblicato nulla' -ForegroundColor Yellow }
if (-not $Yes) {
    $answer = Read-Host 'Procedo? (s/N)'
    if ($answer -notmatch '^[sSyY]') { Fail 'Annullato.' }
}

# ---- 2. Compilazione ----
Step 'flutter pub get'
Run-Native 'flutter pub get' { flutter pub get }

Step 'Compilazione Windows (release)'
Run-Native 'La compilazione' { flutter build windows --release }

$exe = Get-ChildItem (Join-Path $root 'build\windows') -Recurse -Filter $ExeName -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Release' } |
    Select-Object -First 1
if (-not $exe) {
    Fail "Non trovo $ExeName nella cartella di build."
}

# ---- 3. Zip e manifest ----
Step 'Creazione di zip e manifest'
$out = Join-Path $env:TEMP "pubblica_$AppId"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

$zipName = "$AppId-windows.zip"
$zip = Join-Path $out $zipName
$buildDir = $exe.DirectoryName
# tar di Windows crea uno zip standard (percorsi con "/") ed e molto piu veloce di Compress-Archive.
Run-Native 'La creazione dello zip' { tar -a -c -f $zip -C $buildDir . }
$item = Get-Item $zip
$sizeMb = [math]::Round($item.Length / 1MB, 1)
Write-Host "Zip pronto: $sizeMb MB"

$manifestFile = Join-Path $out 'manifest.json'
$manifest = [ordered]@{
    id      = $AppId
    name    = $AppName
    version = $Version
    exe     = $ExeName
    asset   = $zipName
    sha256  = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    size    = [int64]$item.Length
    commit  = $sha
} | ConvertTo-Json
[System.IO.File]::WriteAllText($manifestFile, $manifest, (New-Object System.Text.UTF8Encoding($false)))

if ($NoPublish) {
    Step 'Modalita prova: nulla e stato pubblicato'
    Write-Host "File pronti in: $out"
    Write-Host "Tempo impiegato: $([math]::Round($watch.Elapsed.TotalMinutes, 1)) minuti"
    exit 0
}

# ---- 4. Pubblicazione ----
Step 'Pubblicazione della Release su GitHub'
if (-not $Notes) { $Notes = "Build di $AppName $Version dal commit $short." }
$title = "$AppName $Version"
Run-Native 'La creazione della Release' { gh release create $tag $zip $manifestFile --repo $Repo --title $title --notes $Notes --target $sha }

$names = gh release view $tag --repo $Repo --json assets --jq '.assets[].name'
foreach ($expected in $zipName, 'manifest.json') {
    if ($names -notcontains $expected) {
        Fail "Manca l'allegato $expected nella Release: controlla su GitHub."
    }
}

Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "FATTO: $AppName $Version pubblicato in $([math]::Round($watch.Elapsed.TotalMinutes, 1)) minuti." -ForegroundColor Green
Write-Host "https://github.com/$Repo/releases/tag/$tag"
Write-Host 'Gli utenti vedono "Aggiorna" nel launcher (Controlla aggiornamenti).'
