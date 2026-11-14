#!/bin/bash

if [[ -n $SSH_CONNECTION ]]; then
    systemd-inhibit --what=idle --who="SSH Session" --why="SSH session active" $SHELL
fi
