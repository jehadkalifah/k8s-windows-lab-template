#!/bin/sh
case "$1" in
  *sername*) printf '%s\n' "$GIT_USER" ;;
  *assword*) printf '%s\n' "$GIT_TOKEN" ;;
  *)         printf '\n' ;;
esac
