#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "Usage: $0 DIRECTORY" >&2
    exit 1
fi

input_dir=$(cd -- "$1" && pwd)
tika_home=${TIKA_HOME:-/opt/tika}
tika_server="$tika_home/tika-server.jar"
tika_config="$tika_home/tika-config.json"
tika_port=${TIKA_SERVER_PORT:-9998}
tika_url="http://127.0.0.1:${tika_port}"
server_state_dir=$(mktemp -d)
server_log="$server_state_dir/tika-server.log"
server_pid=""

if [[ ! -f "$tika_server" ]]; then
    echo "Apache Tika server not found at $tika_server" >&2
    exit 1
fi

if [[ ! -f "$tika_config" ]]; then
    echo "Apache Tika configuration not found at $tika_config" >&2
    exit 1
fi

stop_server() {
    if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi

    rm -rf -- "$server_state_dir"
}

trap stop_server EXIT

echo "Starting Apache Tika Server on $tika_url..."
(
    cd -- "$tika_home"
    exec java -jar "$tika_server" \
        --config "$tika_config" \
        --host 127.0.0.1 \
        --port "$tika_port"
) > "$server_log" 2>&1 &
server_pid=$!

server_ready=false
for _ in {1..120}; do
    if curl --silent --fail --max-time 1 "$tika_url/version" > /dev/null; then
        server_ready=true
        break
    fi

    if ! kill -0 "$server_pid" 2>/dev/null; then
        break
    fi

    sleep 0.5
done

if [[ "$server_ready" != true ]]; then
    echo "Apache Tika Server did not become ready. Server log:" >&2
    cat "$server_log" >&2
    exit 1
fi

# Force parser-worker initialization before processing the first real file.
if ! curl --silent --show-error --fail-with-body \
    --request PUT \
    --header 'Content-Type: text/plain' \
    --data-binary 'Apache Tika warm-up' \
    --output /dev/null \
    "$tika_url/tika/html"; then
    echo "Apache Tika Server warm-up failed. Server log:" >&2
    cat "$server_log" >&2
    exit 1
fi

echo "Apache Tika Server is ready."

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
        return 0
    else
        echo "Could not create fallback text file $text_file" >&2
        return 1
    fi
}

record_failure() {
    local source_file="$1"
    local message="$2"

    echo "$message" >&2
    extract_text_fallback "$source_file" || true
    failed_count=$((failed_count + 1))
}

# Materialize the input list before creating output so files written during this
# run cannot be picked up by find. Generated HTML and fallback text from an
# earlier run are excluded as well.
mapfile -d '' source_files < <(
    find "$input_dir" -type f ! -name '*.html' ! -name '*.txt' -print0
)

for source_file in "${source_files[@]}"; do
    output_file="${source_file}.html"
    temporary_output=$(mktemp "${output_file}.tmp.XXXXXX")

    #echo "Converting $source_file with Apache Tika Server..."

    if curl --silent --show-error --fail-with-body \
        --globoff \
        --request PUT \
        --upload-file "$source_file" \
        --output "$temporary_output" \
        "$tika_url/tika/html"; then
        mv -- "$temporary_output" "$output_file"
        converted_count=$((converted_count + 1))
        echo "Created $output_file"
    else
        rm -f -- "$temporary_output"
        record_failure "$source_file" "Apache Tika could not convert $source_file; skipping"
    fi
done

echo "Converted $converted_count document(s) to HTML; encountered $failed_count conversion error(s)."
