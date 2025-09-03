#!/bin/bash

# ---------------- CONFIG ----------------
THEME="/usr/share/rofi/themes/gruvbox-dark-hard.rasi"
MUSIC_DIR="$HOME/Music"
SOCKET="/tmp/mpv-local.sock"
PLAYLIST_DIR="$HOME/Music/playlists"

mkdir -p "$PLAYLIST_DIR"
cd "$MUSIC_DIR" || exit 1

# ---------------- HELPERS ----------------
select_tracks() {
    find . -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" \) |
        sed 's|^\./||' |
        rofi -dmenu -matching fuzzy -i -theme "$THEME" -multi-select -p "🎧 Select Songs"
}

read_selection_into_array() {
    IFS=$'\n' read -d '' -r -a playlist <<<"$1"
}

wait_for_socket() {
    for i in {1..10}; do
        [ -S "$SOCKET" ] && return
        sleep 0.2
    done
    notify-send "MPV socket not available"
    exit 1
}

mpv_running() {
    [ ! -S "$SOCKET" ] && notify-send "MPV is not running" && return 1
    return 0
}

# ---------------- NOTIFYME ----------------
mpv_notify_loop() {
    mpv_running || return
    last_pos=-1
    while [ -S "$SOCKET" ]; do
        pos=$(echo '{ "command": ["get_property", "playlist-pos"] }' | socat - "$SOCKET" | jq '.data')
        [ -z "$pos" ] && sleep 1 && continue
        [ "$pos" == "$last_pos" ] && sleep 1 && continue
        last_pos="$pos"

        # Get current & next track
        current=$(echo '{ "command": ["get_property", "playlist"] }' | socat - "$SOCKET" | jq -r ".data[$pos].filename")
        next=$(echo '{ "command": ["get_property", "playlist"] }' | socat - "$SOCKET" | jq -r ".data[$((pos + 1))].filename // empty")

        # Strip music dir path
        current="${current#$MUSIC_DIR/}"
        next="${next#$MUSIC_DIR/}"

        # Show notifications
        notify-send "🎵 Now Playing" "$current" -u normal
        [ -n "$next" ] && notify-send "⏭️ Up Next" "$next" -u low

        sleep 1
    done
}

# ---------------- PLAYLIST ----------------
save_playlist() {
    mpv_running || return
    pl=$(echo '{ "command": ["get_property", "playlist"] }' | socat - "$SOCKET")
    name=$(rofi -dmenu -theme "$THEME" -p "💾 Save Playlist As:")
    [ -z "$name" ] && return
    echo "$pl" | jq -r '.data[].filename' >"$PLAYLIST_DIR/$name.m3u"
    notify-send "Playlist saved as $name"
}

load_playlist() {
    selected=$(find "$PLAYLIST_DIR" -type f -name "*.m3u" |
        xargs -I{} basename "{}" .m3u |
        rofi -dmenu -theme "$THEME" -p "📂 Load Playlist:")
    [ -z "$selected" ] && return
    mapfile -t playlist <"$PLAYLIST_DIR/$selected.m3u"
    rm -f "$SOCKET"
    mpv --no-video --input-ipc-server="$SOCKET" --quiet "${playlist[@]}" &
    wait_for_socket
    mpv_notify_loop &
}

append_to_playlist() {
    selected_playlist=$(find "$PLAYLIST_DIR" -type f -name "*.m3u" |
        xargs -I{} basename "{}" .m3u |
        rofi -dmenu -theme "$THEME" -p "📋 Choose Playlist to Append:")
    [ -z "$selected_playlist" ] && return
    selected_tracks=$(select_tracks)
    [ -z "$selected_tracks" ] && return
    echo "$selected_tracks" >>"$PLAYLIST_DIR/$selected_playlist.m3u"
    notify-send "Tracks appended to $selected_playlist"
}

shuffle_playlist() {
    # Select playlist
    selected=$(find "$PLAYLIST_DIR" -type f -name "*.m3u" |
        xargs -I{} basename "{}" .m3u |
        rofi -dmenu -theme "$THEME" -p "🎲 Select Playlist to Shuffle:")
    [ -z "$selected" ] && return

    input_file="$PLAYLIST_DIR/$selected.m3u"
    tmp_file=$(mktemp --suffix=.m3u)

    # Shuffle and save to temp file
    shuf "$input_file" >"$tmp_file"

    # Play with MPV
    rm -f "$SOCKET"
    mpv --no-video --input-ipc-server="$SOCKET" --quiet --playlist="$tmp_file" &
    wait_for_socket
    mpv_notify_loop &

    # Remove temp file after playback
    rm -f "$tmp_file"
    notify-send "Finished playing shuffled playlist: $selected"
}
playlist_menu() {
    # choice=$(printf "💾 Save Playlist\n📂 Load Playlist\n📋 Append to Playlist" |
    choice=$(printf "📂 Load Playlist\n💾 Save Playlist\n📋 Append to Playlist\n🎲 Shuffle Playlist" |
        rofi -dmenu -theme "$THEME" -p "🎼 Playlist Menu:")
    case "$choice" in
    "💾 Save Playlist") save_playlist ;;
    "📂 Load Playlist") load_playlist ;;
    "📋 Append to Playlist") append_to_playlist ;;
    "🎲 Shuffle Playlist") shuffle_playlist ;;
    esac
}
