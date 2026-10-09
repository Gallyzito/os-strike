os!strike MAPS
==============

Every folder here is one song: the audio, the background image and one .osu
file per difficulty. The game reads this folder every time you open the song select.

INSTALLING MAPS
- .osz files: put them directly here (not inside a subfolder). They are extracted
  automatically the next time you open the song select.
- osu! (stable): copy song folders from %LOCALAPPDATA%\osu!\Songs to here.
- osu!lazer: export the beatmap as .osz and put it here.

Only osu!standard maps work (taiko, catch and mania are skipped).
Next to each .osu the game creates a .json with the map index (title, stars,
AR/OD/CS/HP...). To re-index a map, delete its .json.
