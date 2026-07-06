<#
.SYNOPSIS
    Extrait l'audio d'une vidéo (MKV, MP4, ...) et le découpe en un fichier par chapitre.

.PREREQUIS
    ffmpeg et ffprobe doivent être installés et accessibles dans le PATH.
    Téléchargement : https://www.gyan.dev/ffmpeg/builds/ (choisir "release full" ou "essentials")
    -> dézipper, puis ajouter le dossier "bin" au PATH Windows (ou placer ffmpeg.exe /
       ffprobe.exe à côté de ce script).

.USAGE
    .\Extraire-ChapitresAudio.ps1 -Video "video.mkv"
    .\Extraire-ChapitresAudio.ps1 -Video "video.mkv" -Format mp3
    .\Extraire-ChapitresAudio.ps1 -Video "video.mkv" -OutputDir "sortie" -Track 1

    Si l'exécution de scripts est bloquée, lance d'abord (une seule fois) :
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Video,

    [string]$OutputDir = $null,

    [ValidateSet("copy","mp3","aac","flac","wav","ogg")]
    [string]$Format = "copy",

    [int]$Track = 0
)

$ErrorActionPreference = "Stop"

function Test-Tool($name) {
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $found) {
        Write-Host "Erreur : '$name' est introuvable dans le PATH." -ForegroundColor Red
        Write-Host "Installe ffmpeg depuis https://www.gyan.dev/ffmpeg/builds/ et ajoute son dossier 'bin' au PATH." -ForegroundColor Yellow
        exit 1
    }
}

Test-Tool "ffmpeg"
Test-Tool "ffprobe"

if (-not (Test-Path $Video)) {
    Write-Host "Erreur : fichier introuvable : $Video" -ForegroundColor Red
    exit 1
}

$videoItem = Get-Item $Video
if (-not $OutputDir) {
    $OutputDir = Join-Path $videoItem.DirectoryName ($videoItem.BaseName + "_audio")
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Get-SafeName([string]$name) {
    $safe = $name -replace '[\\/:*?"<>|]', "_"
    $safe = $safe.Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { return "sans_titre" }
    return $safe
}

Write-Host "Lecture des chapitres..." -ForegroundColor Cyan
$probeJson = & ffprobe -i "$Video" -print_format json -show_chapters -loglevel error
$probeData = $probeJson | ConvertFrom-Json
$chapters = $probeData.chapters

if (-not $chapters -or $chapters.Count -eq 0) {
    Write-Host "Aucun chapitre trouvé. Extraction de l'audio complet en un seul fichier." -ForegroundColor Yellow
    $durationStr = & ffprobe -i "$Video" -show_entries format=duration -v quiet -of csv=p=0
    $chapters = @([PSCustomObject]@{
        start_time = "0"
        end_time   = $durationStr.Trim()
        tags       = [PSCustomObject]@{ title = $videoItem.BaseName }
    })
}

Write-Host "$($chapters.Count) chapitre(s) détecté(s). Sortie dans : $OutputDir`n" -ForegroundColor Cyan

$ext = if ($Format -eq "copy") { "mka" } else { $Format }
$codecMap = @{
    mp3  = "libmp3lame"
    aac  = "aac"
    flac = "flac"
    wav  = "pcm_s16le"
    ogg  = "libvorbis"
}

$i = 0
foreach ($chap in $chapters) {
    $i++
    $start = $chap.start_time
    $end = $chap.end_time
    $title = if ($chap.tags -and $chap.tags.title) { $chap.tags.title } else { "chapitre_$i" }
    $safeTitle = Get-SafeName $title
    $num = "{0:D2}" -f $i
    $outName = "$num - $safeTitle.$ext"
    $outPath = Join-Path $OutputDir $outName

    Write-Host "[$i/$($chapters.Count)] $title  ($start s -> $end s)"

    $ffmpegArgs = @(
        "-y",
        "-i", $Video,
        "-ss", $start,
        "-to", $end,
        "-map", "0:a:$Track",
        "-vn"
    )

    if ($Format -eq "copy") {
        $ffmpegArgs += @("-c:a", "copy")
    } else {
        $ffmpegArgs += @("-c:a", $codecMap[$Format])
    }

    $ffmpegArgs += @("-loglevel", "error", $outPath)

    & ffmpeg @ffmpegArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "   Erreur ffmpeg pour ce chapitre." -ForegroundColor Red
    } else {
        Write-Host "   -> $outName" -ForegroundColor Green
    }
}

Write-Host "`nTerminé." -ForegroundColor Cyan
