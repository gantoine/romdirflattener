# romdirflattener
Simply script to flatten a directory of roms from a nested directory using hardlinks to avoid wasting diskspace.

## Usage

```sh
flatten-romdir.sh [--dryrun] [--prune] <source_directory> <flat_directory>
```

- Files with a known rom extension (matched case-insensitively) are hardlinked into `<flat_directory>`.
- A folder holding a `.cue`, `.gdi`, `.m3u`, `.ccd` or `.mds` and no subfolders is a disc game. It is linked as one folder with all of its files, including audio tracks.
- When two different files share a name, the second is linked as `Name [Parent Folder].ext`. Identical copies are linked once.
- `--prune` removes files whose source was deleted (a link count of 1), then empty folders. Only use it when `<flat_directory>` holds nothing but links made by this script.
- `--dryrun` prints what would happen without changing anything.
