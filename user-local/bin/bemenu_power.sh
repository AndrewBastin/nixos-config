#!/usr/bin/env bash
# https://github.com/bitterhalt
set -euo pipefail

CONFIRM="$HOME/.local/bin/bemenu_runner.sh -n -W 0.10 -B1 --bdr #DA1E28 -l2 -p Sure?"

case $(printf "%s\n" "Lock" "Logout" "Suspend" "Reboot" "Shutdown" | $HOME/.local/bin/bemenu_runner.sh -n -B1 -l5 -p Quit?) in
"Shutdown")
  confirm=$(echo -e "Yes\nNo" | $CONFIRM)
  if [[ "$confirm" == "Yes" ]]; then
    poweroff
  fi
  ;;
"Reboot")
  confirm=$(echo -e "Yes\nNo" | $CONFIRM)
  if [[ "$confirm" == "Yes" ]]; then
    reboot
  fi
  ;;
"Suspend")
  loginctl suspend
  ;;
"Lock")
  hyprlock
  ;;
"Logout")
  loginctl terminate-session "${XDG_SESSION_ID-}"
  ;;
esac
