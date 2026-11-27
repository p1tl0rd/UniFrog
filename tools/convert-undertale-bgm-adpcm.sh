#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
	echo "Usage: $0 <undertale_data_dir>" >&2
	exit 1
fi

dir=$1
if [ ! -d "$dir" ]; then
	echo "Error: directory not found: $dir" >&2
	exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "Error: ffmpeg is required in PATH" >&2
	exit 1
fi

count=0
tmp_list=$(mktemp)
trap 'rm -f "$tmp_list"' EXIT

find "$dir" -type f \( -name 'mus_*.ogg' -o -path '*/music/*.ogg' \) | sort > "$tmp_list"

while IFS= read -r src; do
	[ -n "$src" ] || continue
	out="${src%.*}.wav"
	ffmpeg -y -v error -i "$src" -vn -ac 1 -ar 22050 -c:a adpcm_ima_wav "$out"
	count=$((count + 1))
done < "$tmp_list"

echo "Converted $count OGG track(s) to 22050 Hz mono IMA-ADPCM WAV in $dir (originals preserved)."
