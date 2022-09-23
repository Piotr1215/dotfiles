#!/usr/bin/env bash

set -eo pipefail

detect_os() {
	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		export paste_tool="xsel -ob"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		export paste_tool="pbpaste"
	else
		echo "Unrecognized OS"
		return 1
	fi
}

display_help() {
	{
		cat <<EOF
	Copy credentials to the clipboard
	Run the script (scripts folder is in the PATH)
	If the credentials exist it will override them
	If not, it will add them to the config file
EOF
	}
}
check_aws_config() {

	aws_creds=~/.aws/credentials

	if [ ! -f "$aws_creds" ]; then
		echo "AWS credentials file not found in ~/.aws/credentials"
		return 2
	fi
}
parse_clipboard_input() {

	# Paste profile from the "Option 2"
	profile=$(${paste_tool})
	# Make sure we are not pasting junk
	if [[ "$profile" != *"_AdministratorAccess"* ]]; then
		echo "This is not the right format, copy again"
		return 5
	fi
}
update_credentials() {

	# Grab only first line without brackets
	first_line=$(echo "$profile" | awk 'NR==1 {print $0}' | sed 's/[][]//g')

	# If credentials found in the file, remove them and add
	# again to the end of the file
	# If not found add them to the end of the file
	if grep -q "$first_line" "$aws_creds"; then
		echo "Credendials for $first_line found and swapped in the config file"
		perl -i -00ne "print unless /$first_line/" "$aws_creds"
		echo -e "\n$profile" >>"$aws_creds"
	else
		echo "Credendials not found, adding to the config file"
		echo -e "\n$profile" >>"$aws_creds"
	fi

}
main() {
	if [[ "$1" =~ (-h|--help) ]]; then
		display_help "$1"
		return 0
	fi
	detect_os
	check_aws_config
	parse_clipboard_input
	update_credentials
}

main "$@"
