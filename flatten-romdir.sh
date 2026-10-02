#!/bin/bash

# Allowed file extensions for hardlinking, matched case-insensitively
allowed_exts=".32x .3ds .7z .a26 .a52 .a78 .abs .adf .adfd .agb .atr .bin .bs .car .ccd .cdi .chd .cia .col .crt .cue .d64 .d88 .dms .dsk .fds .fig .g64 .gb .gba .gbc .gcm .gcz .gdi .gen .gg .hdf .img .ipf .iso .j64 .jag .jcd .lha .lnx .m3u .md .mdf .mds .msa .n64 .nds .neo .nes .ngc .ngp .nsp .pbp .pce .prg .qd .rar .rom .rvz .sc .sf .sfc .sg .sgx .smc .smd .sms .sna .st .stx .sv .t64 .tap .tzx .v64 .vb .vec .wad .wbfs .ws .wsc .xci .z64 .z80 .zip"

# A folder holding one of these (and no subfolders) is a disc game. It is linked
# whole, so tracks keep their folder and audio tracks are not filtered out.
disc_exts=".cue .gdi .m3u .ccd .mds"

dryrun=0
prune=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dryrun) dryrun=1; shift ;;
    --prune) prune=1; shift ;;
    *) break ;;
  esac
done

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 [--dryrun] [--prune] <source_directory> <flat_directory>" >&2
  exit 1
fi

src_dir="$1"
flat_dir="$2"

# Validate source directory
if [ ! -d "$src_dir" ]; then
  echo "Error: Source directory '$src_dir' does not exist or is not a directory." >&2
  exit 2
fi

# Validate flat directory
if [ ! -d "$flat_dir" ]; then
  echo "Error: Flat directory '$flat_dir' does not exist or is not a directory." >&2
  exit 3
fi

has_ext() {
  local name="${1,,}"
  [[ "$name" == *.* ]] && [[ " $2 " == *" .${name##*.} "* ]]
}

# "Game (USA).fds" + "QD2FDS" -> "Game (USA) [QD2FDS].fds"
with_tag() {
  local name="$1" tag="$2"
  if [[ "$name" == *.* ]]; then
    echo "${name%.*} [$tag].${name##*.}"
  else
    echo "$name [$tag]"
  fi
}

# Returns 1 when dest is taken by a different file.
can_link() {
  local file="$1" dest="$2"
  [ ! -e "$dest" ] && return 0
  [ "$(stat -c %d:%i "$file")" = "$(stat -c %d:%i "$dest")" ] && return 0
  [ -f "$dest" ] && cmp -s "$file" "$dest" && return 0
  return 1
}

link_file() {
  local file="$1" dest="$2"
  if [ -e "$dest" ]; then
    [ "$dryrun" -eq 1 ] && echo "Already present: '$file' -> '$dest' (skipped)"
    return
  fi
  if [ "$dryrun" -eq 1 ]; then
    echo "Would link: '$file' -> '$dest'"
  else
    ln "$file" "$dest"
  fi
}

is_disc_dir() {
  local dir="$1" f
  [ -n "$(find "$dir" -mindepth 1 -maxdepth 1 -type d -print -quit)" ] && return 1
  for f in "$dir"/*; do
    [ -f "$f" ] && has_ext "$f" "$disc_exts" && return 0
  done
  return 1
}

# Every file of the disc dir fits in dest_dir without displacing another game's.
dir_fits() {
  local dir="$1" dest_dir="$2" f
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    can_link "$f" "$dest_dir/$(basename "$f")" || return 1
  done
}

declare -A disc_dirs

while IFS= read -r -d $'\0' dir; do
  is_disc_dir "$dir" || continue
  disc_dirs["$dir"]=1
  name="$(basename "$dir")"
  dest_dir="$flat_dir/$name"
  if ! dir_fits "$dir" "$dest_dir"; then
    dest_dir="$flat_dir/$name [$(basename "$(dirname "$dir")")]"
    if ! dir_fits "$dir" "$dest_dir"; then
      echo "Skipping (name taken by a different game): '$dir'" >&2
      continue
    fi
  fi
  [ "$dryrun" -eq 0 ] && mkdir -p "$dest_dir"
  for f in "$dir"/*; do
    [ -f "$f" ] && link_file "$f" "$dest_dir/$(basename "$f")"
  done
done < <(find "$src_dir" -mindepth 1 -type d -print0 | sort -z)

while IFS= read -r -d $'\0' file; do
  [ -n "${disc_dirs["$(dirname "$file")"]}" ] && continue
  # Only process allowed extensions
  if ! has_ext "$file" "$allowed_exts"; then
    [ "$dryrun" -eq 1 ] && echo "Skipping (ext not allowed): '$file'"
    continue
  fi
  name="$(basename "$file")"
  dest="$flat_dir/$name"
  # Avoid linking file onto itself
  [ "$file" = "$dest" ] && continue
  # A different file already owns the name, so tag this one with its folder
  if ! can_link "$file" "$dest"; then
    dest="$flat_dir/$(with_tag "$name" "$(basename "$(dirname "$file")")")"
    if ! can_link "$file" "$dest"; then
      echo "Skipping (name taken by a different file): '$file'" >&2
      continue
    fi
  fi
  link_file "$file" "$dest"
done < <(find "$src_dir" -type f -print0 | sort -z)

# Every file in the flat directory is a hardlink, so a link count of 1 means its
# source was deleted.
if [ "$prune" -eq 1 ]; then
  while IFS= read -r -d $'\0' stale; do
    if [ "$dryrun" -eq 1 ]; then
      echo "Would remove (source deleted): '$stale'"
    else
      rm -- "$stale"
    fi
  done < <(find "$flat_dir" -type f -links 1 -print0)
  [ "$dryrun" -eq 0 ] && find "$flat_dir" -mindepth 1 -type d -empty -delete
fi
