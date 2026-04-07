#!/usr/bin/env bash

systemd-inhibit --what=idle:sleep --who="keepalive" --why="Prevent screensaver" bash -c 'while true; do sleep 60; done'
