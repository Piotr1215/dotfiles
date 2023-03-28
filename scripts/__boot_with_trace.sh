#!/usr/bin/env bash

sleep 1
/home/decoder/dev/dotfiles/scripts/__run_with_xtrace.sh /home/decoder/dev/dotfiles/scripts/__boot.sh 2>&1 | tee /var/log/custom_boot.log
