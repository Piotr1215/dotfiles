#!/usr/bin/env bash
#This script gets all installations don today

CURRENT_DATE=$(date +'%Y-%m-%d')

cat /var/log/dpkg.log | grep "^${CURRENT_DATE}.*\ installed\ " | lolcat
