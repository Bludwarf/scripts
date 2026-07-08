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
.\Extraire-ChapitresAudio.ps1 -Video "video.mkv" -OutputDir "sortie" -Track 1 -Album "Mon album"

Si l'exécution de scripts est bloquée, lance d'abord (une seule fois) :
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Video,
    [string]$OutputDir = $null,
    [ValidateSet("copy","mp3","aac","flac","wav","ogg")]
    [string]$Format = "copy",
    [int]$Track = 0,
    [string]$Album
)

$ScriptVersion = "2026.07.08"
$ErrorActionPreference = "Stop"

# Force l'UTF-8 en entrée/sortie des process externes (ffmpeg/ffprobe) pour éviter
# les caractères mal décodés type "?®" au lieu de "é" dans les titres de chapitres.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

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

# Version ffmpeg réellement utilisée, déduite de `ffmpeg -version`.
$ffmpegVersionOutput = & ffmpeg -version
$ffmpegVersion = if ($ffmpegVersionOutput[0] -match 'ffmpeg version (\S+)') { $Matches[1] } else { "inconnue" }

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
        end_time = $durationStr.Trim()
        tags = [PSCustomObject]@{ title = $videoItem.BaseName }
    })
}

Write-Host "$($chapters.Count) chapitre(s) détecté(s). Sortie dans : $OutputDir`n" -ForegroundColor Cyan

$ext = if ($Format -eq "copy") { "mka" } else { $Format }
$codecMap = @{
    mp3 = "libmp3lame"
    aac = "aac"
    flac = "flac"
    wav = "pcm_s16le"
    ogg = "libvorbis"
}

# Langue de la piste audio sélectionnée, déduite via ffprobe (repli sur "und" si absente).
$trackLanguage = & ffprobe -i "$Video" -select_streams "a:$Track" -show_entries "stream_tags=language" -of csv=p=0 -v quiet
$trackLanguage = if ([string]::IsNullOrWhiteSpace($trackLanguage)) { "und" } else { $trackLanguage.Trim() }

Write-Host "Langue : $trackLanguage"

if ($Album) {
    Write-Host "Album : $Album"
}

Write-Host

# Args communs à tous les chapitres, sortis de la boucle.
# "language" est une métadonnée de PISTE (pas globale) : on la cible avec -metadata:s:a:0
# pour qu'elle soit effectivement écrite sur le flux audio de sortie.
$commonMetadataArgs = @(
    "-metadata", "genre=Soundtrack",
    "-metadata", "encoded_by=Extraire-ChapitresAudio.ps1 $ScriptVersion via ffmpeg $ffmpegVersion",
    "-metadata:s:a:0", "language=$trackLanguage"
)


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

    Write-Host "[$i/$($chapters.Count)] $title ($start s -> $end s)"

    $ffmpegArgs = @(
        "-y",
        "-i", $Video,
        "-ss", $start,
        "-to", $end,
        "-map", "0:a:$Track",
        "-vn",
        "-map_chapters", "-1",
        "-map_metadata:g", "0:g",
        "-id3v2_version", "3",
        "-metadata", "track=$i",
        "-metadata", "TRACKTOTAL=$($chapters.Count)",
        "-metadata", "title=$title"
    )
    $ffmpegArgs += $commonMetadataArgs

    if ($Format -eq "copy") {
        $ffmpegArgs += @("-c:a", "copy")
    } else {
        $ffmpegArgs += @("-c:a", $codecMap[$Format])
    }

    if ($Album) {
        # Doit être ajouté avant le chemin de sortie : ffmpeg ignore les options
        # placées après le fichier de sortie, ce qui rendait ce tag invisible dans l'explorateur.
        $ffmpegArgs += @("-metadata", "album=$Album")
    }

    $ffmpegArgs += @("-loglevel", "warning", $outPath)

    & ffmpeg @ffmpegArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Erreur ffmpeg pour ce chapitre." -ForegroundColor Red
    } else {
        Write-Host "  -> $outName" -ForegroundColor Green
    }
}

Write-Host "`nTerminé." -ForegroundColor Cyan
