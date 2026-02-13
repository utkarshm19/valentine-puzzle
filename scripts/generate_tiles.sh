#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES_DIR="$ROOT_DIR/images"
TMP_DIR="$IMAGES_DIR/.tilegen_tmp"
mkdir -p "$TMP_DIR"

slice_from_full_image() {
  local src_full="$1"
  local tile_suffix="$2"

  local src_path="$IMAGES_DIR/$src_full"
  if [[ ! -f "$src_path" ]]; then
    echo "Missing source image: $src_path" >&2
    exit 1
  fi

  local width height
  width="$(sips -g pixelWidth "$src_path" | awk '/pixelWidth:/{print $2}')"
  height="$(sips -g pixelHeight "$src_path" | awk '/pixelHeight:/{print $2}')"

  # Work on a temp square source so the original full image is not modified.
  local work_src="$TMP_DIR/work-${tile_suffix:-base}.png"
  cp "$src_path" "$work_src"

  if (( width != height )); then
    local square crop_x crop_y
    if (( width < height )); then
      square=$width
    else
      square=$height
    fi
    crop_x=$(( (width - square) / 2 ))
    crop_y=$(( (height - square) / 2 ))
    # sips cropOffset expects X then Y.
    sips -c "$square" "$square" --cropOffset "$crop_x" "$crop_y" "$work_src" --out "$work_src" >/dev/null
    width=$square
    height=$square
  fi

  local final_dim=$width
  local divisible_dim=$(( final_dim - (final_dim % 3) ))
  if (( divisible_dim != final_dim )); then
    local off=$(( (final_dim - divisible_dim) / 2 ))
    # Trim equally from all sides to nearest dimension divisible by 3.
    sips -c "$divisible_dim" "$divisible_dim" --cropOffset "$off" "$off" "$work_src" --out "$work_src" >/dev/null
    final_dim=$divisible_dim
  fi

  local tile_size=$(( final_dim / 3 ))
  local last_offset=$(( final_dim - tile_size ))
  local flipped_src="$TMP_DIR/flipped-${tile_suffix:-base}.png"
  sips -f horizontal "$work_src" --out "$flipped_src" >/dev/null

  local idx=1
  for row in 0 1 2; do
    for col in 0 1 2; do
      local y_off=$((row * tile_size))
      local x_off=$((col * tile_size))
      local tile_out
      if [[ -n "$tile_suffix" ]]; then
        tile_out="$IMAGES_DIR/tile-${idx}-${tile_suffix}.png"
      else
        tile_out="$IMAGES_DIR/tile-${idx}.png"
      fi

      # sips has edge-case bugs at two opposing corners where it can return full image.
      # Work around both with mirrored crop + mirrored tile back.
      if (( x_off == 0 && y_off == last_offset )); then
        local mirrored_col_offset=$last_offset
        local mirrored_tile="$TMP_DIR/mirror-tile-${tile_suffix:-base}-${idx}.png"
        sips -c "$tile_size" "$tile_size" --cropOffset "$mirrored_col_offset" "$y_off" "$flipped_src" --out "$mirrored_tile" >/dev/null
        sips -f horizontal "$mirrored_tile" --out "$tile_out" >/dev/null
      elif (( x_off == last_offset && y_off == 0 )); then
        local mirrored_tile="$TMP_DIR/mirror-tile-${tile_suffix:-base}-${idx}.png"
        sips -c "$tile_size" "$tile_size" --cropOffset 0 0 "$flipped_src" --out "$mirrored_tile" >/dev/null
        sips -f horizontal "$mirrored_tile" --out "$tile_out" >/dev/null
      else
        # sips cropOffset expects X then Y.
        sips -c "$tile_size" "$tile_size" --cropOffset "$x_off" "$y_off" "$work_src" --out "$tile_out" >/dev/null
      fi

      idx=$((idx + 1))
    done
  done

  echo "Generated tile set (${tile_suffix:-base}) from $src_full"
}

slice_from_full_image "full-image.png" ""
slice_from_full_image "full-image-2.png" "2"

rm -rf "$TMP_DIR"

echo "Done."
