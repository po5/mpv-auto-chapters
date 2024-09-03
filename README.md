# autochapters
Automatically finds chapters for your anime files.

## Installation
Place the "autochapters" folder in your mpv `scripts` folder. Do not take the Lua file out of the folder.  
This script requires **curl** and **guessit** to be installed and [accessible within Path](https://learn.microsoft.com/en-us/previous-versions/office/developer/sharepoint-2010/ee537574(v=office.14)#to-add-a-path-to-the-path-environment-variable).  
For Windows grab the [curl](https://curl.se/windows/) and [guessit-windows.exe](https://github.com/guessit-io/guessit/releases/latest) binaries. Rename the guessit file to `guessit.exe`.  
Use your package manager on Mac/Linux.

## Usage
Open any anime episode. The offline database will automatically be cached on first launch.  
If your file did not already have chapters, this script will extract the anime title and episode number from the filename, and look for matching chapters online.  
Filenames are processed on your local device and never sent over the internet.

## Synergy with other scripts
Any script that uses chapters such as [chapterskip](https://github.com/po5/chapterskip) can be used to automatically skip openings/endings.  
Chapter data is also available under the `user-data/autochapters` property, and filename parsing results at `user-data/guessit`.

## Acknowledgements
[Aniskip](https://github.com/aniskip) for the API serving chapters.  
[ani-skip](https://github.com/synacktraa/ani-skip) for being annoying enough to use that I went and made this.  
manami's [anime-offline-database](https://github.com/manami-project/anime-offline-database) which is used to link titles to MyAnimeList IDs.  
Taiga's [anime-relations](https://github.com/erengy/anime-relations) used to resolve continuous numbering schemes to their respective seasons.
