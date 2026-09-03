# NyxNiri Multi-App Scratchpad Toggle
# Controls floating scratchpad lifecycle for Kitty, Mission Center, Nautilus, and custom apps.
# (shebang 由 writeShellApplication 生成, 本文件为脚本体)

# shellcheck disable=SC2317
set -uo pipefail

TARGET_APP="${1:-kitty}"

# ── Serialization Lock ──────────────────────────────────────────────
LOCK_NAME=$(printf '%s' "$TARGET_APP" | tr -c 'a-zA-Z0-9_' '_')
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/nyxniri-scratch-${LOCK_NAME}.lock"
flock -n 9 || exit 0

case "$TARGET_APP" in
    kitty|terminal|Kitty|Terminal)
        APP_ID="scratchpad"
        TMUX_SESSION="scratch"

        ACTIVE_WS=$(niri msg -j workspaces 2>/dev/null \
            | jq -r '[.[] | select(.is_focused == true) | .id] + [.[] | select(.is_active == true) | .id] | .[0] // empty') \
            || true

        read -r win_id win_ws < <(niri msg -j windows 2>/dev/null \
            | jq -r --arg id "$APP_ID" \
                '.[] | select(.app_id == $id) | "\(.id) \(.workspace_id)"') \
            || { win_id=; win_ws=; }

        spawn_kitty() {
            # kitty 由 niri spawn, 继承 niri 环境 PATH (无 store tmux/fish)。
            # command -v 利用本脚本 PATH 注入 (runtimeInputs) 拿到 store 绝对路径,
            # 否则 kitty exec tmux 时 "Failed to launch child tmux"。
            local tmux_bin fish_bin
            tmux_bin=$(command -v tmux 2>/dev/null || true)
            fish_bin=$(command -v fish 2>/dev/null || true)
            if [ -n "$tmux_bin" ] && [ -n "$fish_bin" ]; then
                niri msg action spawn -- \
                    kitty --app-id "$APP_ID" --title "Scratchpad" \
                    --override confirm_os_window_close=0 \
                    "$tmux_bin" new-session -A -D -s "$TMUX_SESSION" \
                    "$fish_bin -C 'function fish_greeting; end' -C 'set -g fish_history scratchpad'" \; set-option status off
            else
                niri msg action spawn -- \
                    kitty --app-id "$APP_ID" --title "Scratchpad" \
                    --override confirm_os_window_close=0
            fi
        }

        if [ -z "${win_id:-}" ]; then
            spawn_kitty
        elif [ -n "$ACTIVE_WS" ] && [ -n "${win_ws:-}" ] && [ "$win_ws" != "$ACTIVE_WS" ]; then
            # Relocate from other workspace to current active workspace
            niri msg action close-window --id "$win_id"
            sleep 0.05
            spawn_kitty
        else
            # On current workspace -> toggle off
            niri msg action close-window --id "$win_id"
        fi
        ;;

    missioncenter|monitor|"mission center"|"Mission Center"|MissionCenter)
        APP_ID="io.missioncenter.MissionCenter"

        ACTIVE_WS=$(niri msg -j workspaces 2>/dev/null \
            | jq -r '[.[] | select(.is_focused == true) | .id] + [.[] | select(.is_active == true) | .id] | .[0] // empty') \
            || true

        read -r win_id win_ws < <(niri msg -j windows 2>/dev/null \
            | jq -r --arg id "$APP_ID" \
                '.[] | select(.app_id == $id) | "\(.id) \(.workspace_id)"') \
            || { win_id=; win_ws=; }

        if [ -z "${win_id:-}" ]; then
            if command -v missioncenter >/dev/null 2>&1; then
                niri msg action spawn -- missioncenter
            elif command -v flatpak >/dev/null 2>&1 && flatpak info io.missioncenter.MissionCenter >/dev/null 2>&1; then
                niri msg action spawn -- flatpak run io.missioncenter.MissionCenter
            fi
        elif [ -n "$ACTIVE_WS" ] && [ -n "${win_ws:-}" ] && [ "$win_ws" != "$ACTIVE_WS" ]; then
            niri msg action focus-window --id "$win_id"
        else
            niri msg action close-window --id "$win_id"
        fi
        ;;

    nautilus|files|Nautilus|Files)
        APP_ID="org.gnome.Nautilus"

        ACTIVE_WS=$(niri msg -j workspaces 2>/dev/null \
            | jq -r '[.[] | select(.is_focused == true) | .id] + [.[] | select(.is_active == true) | .id] | .[0] // empty') \
            || true

        read -r win_id win_ws < <(niri msg -j windows 2>/dev/null \
            | jq -r --arg id "$APP_ID" \
                '.[] | select(.app_id == $id) | "\(.id) \(.workspace_id)"') \
            || { win_id=; win_ws=; }

        if [ -z "${win_id:-}" ]; then
            niri msg action spawn -- nautilus --new-window
        elif [ -n "$ACTIVE_WS" ] && [ -n "${win_ws:-}" ] && [ "$win_ws" != "$ACTIVE_WS" ]; then
            niri msg action focus-window --id "$win_id"
        else
            niri msg action close-window --id "$win_id"
        fi
        ;;

    *)
        # Custom command or script execution
        if [[ "$TARGET_APP" =~ ^~.* ]]; then
            TARGET_APP="${TARGET_APP/#\~/$HOME}"
        fi
        if [ -x "$TARGET_APP" ] || command -v "$TARGET_APP" >/dev/null 2>&1; then
            niri msg action spawn -- "$TARGET_APP"
        else
            niri msg action spawn -- bash -c "$TARGET_APP"
        fi
        ;;
esac

