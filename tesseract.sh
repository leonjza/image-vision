#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <directory-of-images>"
  exit 1
fi

input_dir="$1"

if [ ! -d "$input_dir" ]; then
  echo "Error: Directory $input_dir does not exist."
  exit 1
fi

supported_extensions=("png" "jpg" "jpeg" "tif" "tiff" "bmp")

for ext in "${supported_extensions[@]}"; do
  for img in "$input_dir"/*.$ext; do
    if [ ! -e "$img" ]; then
      continue
    fi

    base_name=$(basename "$img" | sed 's/\.[^.]*$//')
    output_file="$input_dir/$base_name-tesseract"

    tesseract "$img" "$output_file" &> /dev/null

    word_count=$(wc -w < "$output_file".txt)

    echo "$word_count words recognized, writing to $output_file.txt"
  done
done

