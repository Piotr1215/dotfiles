#!/usr/bin/env bash

# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __reboot_required.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [ -f /var/run/reboot-required ]; then
	echo 'Oh no! The system needs a reboot, just like after a long party night.'
	read -p "Do you want to tuck it into bed now? (Y/N) " answer

	case ${answer:0:1} in
	y | Y)
		echo 'Tucking in now... Zzz...'
		sudo reboot
		;;
	*)
		echo ' :('
		cat <<EOF
Even if you are a night owl, remember that your system sometimes needs its beauty sleep.
Just like us, it needs to rest after doing a lot of work.
When the file /var/run/reboot-required shows up, it means your system has been partying hard,
maybe by updating its dance moves (aka critical parts), and now it needs to hit the hay to get back in form.
So next time, don’t hesitate to let it sleep a little!
EOF
		;;
	esac
else
	echo 'The system is as fresh as a daisy, no reboot required!'
fi
