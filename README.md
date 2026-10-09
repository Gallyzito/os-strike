# os!strike

osu! on a curved screen floating in space, played in first person with a Counter-Strike crosshair and weapons. Made with Godot 4.7.2.

**Download the game:** see the [Releases](../../releases) page. Extract the zip and open `os!strike.exe`.

## Building from source

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) and its export templates.
2. Put maps in `maps/` (osu!standard `.osz` files), skins in `skins/` and hitsounds in `sounds/`. These folders are not in the repository.
3. Open the project in Godot and press F5, or build a release:

```bash
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 -Version 1.1
```

The script exports the exe and packs `dist/os!strike-<version>-windows.zip` with the default maps, skins and sounds.

## Releasing a new version

1. Change the version number in the commit message or tag (`v1.1`).
2. Run the build script above.
3. On GitHub: Releases, Draft a new release, pick the tag, attach the zip from `dist/`.

## Not included

Songs, beatmaps, skins and original 3D model sources are other people's work and stay out of the repository. Check the licence of every asset before making a repository public.

Not affiliated with ppy Pty Ltd (osu!) or Valve (Counter-Strike).
