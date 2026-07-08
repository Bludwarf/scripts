# Extraire chapitres audio

## Exemple

```powershell
.\Extraire-ChapitresAudio.ps1 .\Cars.mkv -Format mp3 -Track 1 -Album Cars
```

## Informations

Pour obtenir plus d'informations sur la vidéo d'entrée, utiliser ffmpeg.

Exemple :

```powershell
ffmpeg -i .\Cars.mkv 
```

## TODO

- [ ] Deuxième chapitre en sortie superflu
- [ ] Langue absente en sortie
- [ ] creation_time en sortie marquée comme GMT alors que GMT+2 (si heure d'été en France)
