# Rebellion

Production UI extensions for Guerilla Render.

Current public payload:

- Gizmo 2.0
- Color Picker 2.0
- Auto Save

## Install

For CreativeSeeds artists, double-click:

```text
Install_Rebellion_CreativeSeeds.bat
```

It installs to:

```text
C:\CreativeSeeds\Applications\guerilla2\app
```

Run PowerShell from the repo root:

```powershell
.\tools\install.ps1 -GuerillaRoot "<path-to-guerilla-install>"
```

`GuerillaRoot` is the folder that contains the `app` directory. Existing files are backed up before replacement.

Dry run:

```powershell
.\Install_Rebellion_CreativeSeeds.bat /dryrun
.\tools\install.ps1 -GuerillaRoot "<path-to-guerilla-install>" -WhatIf
```

## Auto Save

Auto Save writes backup `.gproject` files beside the active scene:

```text
scene_folder/
  scene.gproject
  autosave/
    scene_bkp_001.gproject
    scene_bkp_002.gproject
```

The active Guerilla scene remains the original file. Auto Save skips repeated backups when the serialized scene has not changed since the previous autosave.

Preferences live in:

```text
Preferences > Local Settings > Auto Save
```

## Development Flow

Private development happens in `Rebellion_Experimental`. Public releases are promoted into this repo with an allowlist:

```powershell
.\tools\promote-from-experimental.ps1 -ExperimentalRoot "<path-to-private-experimental-repo>"
.\tools\check-public-hygiene.ps1
git status
git add .
git commit -m "Release Rebellion UI extensions"
git push
```
