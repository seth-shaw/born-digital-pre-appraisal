#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! -d "$1" ]]; then
    echo "Usage: $0 DIRECTORY [OUTPUT_FORMAT]" >&2
    exit 1
fi

input_dir=$(cd -- "$1" && pwd)
output_format=${2:-md}
pandoc_format=$output_format

# Keep the existing GitHub-Flavored Markdown behavior for the default `md`
# format while allowing any Pandoc output format, such as `html`.
if [[ "$output_format" == "md" ]]; then
    pandoc_format=gfm
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT

# LibreOffice needs a writable user profile, even in headless mode.
export HOME="$temporary_dir/home"
mkdir -p "$HOME"

converted_count=0
failed_count=0

extract_text_fallback() {
    local source_file="$1"
    local text_file="${source_file}.txt"

    if strings -- "$source_file" | awk '
        NR == FNR { dict[tolower($1)]; next }
        {
            for (i = 1; i <= NF; i++) {
                gsub(/[^A-Za-z]/, "", $i)
                if (tolower($i) in dict) printf "%s ", $i
            }
            print ""
        }
    ' /usr/share/dict/words - > "$text_file"; then
        echo "Created fallback text file $text_file"
    else
        echo "Could not create fallback text file $text_file" >&2
    fi
}

record_failure() {
    local source_file="$1"
    local message="$2"

    echo "$message" >&2
    extract_text_fallback "$source_file"
    failed_count=$((failed_count + 1))
}

while IFS= read -r -d '' file; do
    filename=$(basename -- "$file")
    stem=${filename%.*}
    output_file="${file}.${output_format}"

    # Detect the actual file format. This deliberately does not use the
    # filename extension, since archives often contain incorrectly named or
    # extensionless documents.
    if ! mime_type=$(file --brief --mime-type "$file"); then
        record_failure "$file" "Could not determine the file type for $file; skipping"
        continue
    fi

    if ! description=$(file --brief "$file"); then
        record_failure "$file" "Could not inspect $file; skipping"
        continue
    fi
    conversion_source=""

    case "$mime_type" in
        application/vnd.openxmlformats-officedocument.wordprocessingml.document)
            # Pandoc can read modern Word documents directly.
            conversion_source="$file"
            ;;
        application/msword|application/rtf|text/rtf|\
        application/vnd.oasis.opendocument.text|\
        application/vnd.oasis.opendocument.text-template|\
        application/vnd.wordperfect|application/x-wordperfect)
            conversion_source="$file"
            ;;
        application/CDFV2)
            # Older Word files are commonly reported as generic OLE compound
            # documents rather than application/msword.
            conversion_source="$file"
            ;;
        application/octet-stream|application/x-ole-storage)
            # Older Word and WordPerfect files can be reported as generic
            # binary data, so inspect file(1)'s description too.
            if [[ "$description" =~ [Ww]ord([Pp]erfect)? ]]; then
                conversion_source="$file"
            elif [[ "$mime_type" == "application/octet-stream" && "$description" == "data" ]]; then
                record_failure "$file" "File was reported as generic data; using text extraction"
                continue
            fi
            ;;
        *)
            if [[ "$description" =~ [Ww]ord([Pp]erfect)? ]]; then
                conversion_source="$file"
            fi
            ;;
    esac

    [[ -n "$conversion_source" ]] || continue

    echo "Converting $file ($mime_type)..."

    if [[ "$mime_type" == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ]]; then
        if ! pandoc "$conversion_source" --from=docx --to="$pandoc_format" --output="$output_file"; then
            record_failure "$file" "Pandoc could not convert $file; skipping"
            continue
        fi
    else
        # Normalize legacy formats, including WordPerfect, to DOCX before
        # passing them to Pandoc.
        conversion_dir=$(mktemp -d "$temporary_dir/convert.XXXXXX")

        if ! libreoffice --headless --convert-to docx --outdir "$conversion_dir" "$conversion_source" >/dev/null; then
            record_failure "$file" "LibreOffice could not convert $file; skipping"
            continue
        fi

        converted_file="$conversion_dir/${stem}.docx"

        if [[ ! -f "$converted_file" ]]; then
            record_failure "$file" "LibreOffice did not create a DOCX for $file; skipping"
            continue
        fi

        if ! pandoc "$converted_file" --from=docx --to="$pandoc_format" --output="$output_file"; then
            record_failure "$file" "Pandoc could not convert $file; skipping"
            continue
        fi
    fi

    converted_count=$((converted_count + 1))
    echo "Created $output_file"
done < <(find "$input_dir" -type f -print0)

echo "Converted $converted_count document(s); skipped $failed_count due to errors."
