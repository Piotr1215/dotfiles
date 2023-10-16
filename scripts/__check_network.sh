#!/bin/bash

# Define a function to check the network interface status
check_network_interface() {
	# Get the name of the network interface
	local interface=$(ip route | grep default | awk '{print $5}')

	# Check if the network interface is up
	local status=$(ip link show $interface | grep "state UP")

	if [[ -z $status ]]; then
		echo "The network interface $interface is down."
		# Attempt to bring the network interface up
		sudo ip link set $interface up
		if [[ $? -eq 0 ]]; then
			echo "Successfully brought $interface up."
		else
			echo "Failed to bring $interface up. You may want to check the physical connection or contact your network administrator."
		fi
	else
		echo "The network interface $interface is up."
	fi

	# Check if the network interface has an IP address
	local ip_address=$(ip addr show $interface | grep "inet " | awk '{print $2}')
	if [[ -z $ip_address ]]; then
		echo "The network interface $interface does not have an IP address."
		# Here we may want to suggest further troubleshooting or attempt to renew the IP address
		# For now, we'll suggest checking the DHCP server or restarting the network service
		echo "You may want to check the DHCP server or restart your network service."
	else
		echo "The network interface $interface has an IP address: $ip_address"
	fi
}
ping_server() {
	local server=$1
	if ping -c 1 $server &>/dev/null; then
		echo "Successfully pinged $server."
	else
		echo "Failed to ping $server. There might be a connectivity issue."
	fi
}

# Define a function to test DNS resolution
test_dns_resolution() {
	local domain=$1
	if nslookup $domain &>/dev/null; then
		echo "Successfully resolved $domain."
	else
		echo "Failed to resolve $domain. There might be a DNS issue."
		# Attempt to restart the DNS service
		sudo systemctl restart systemd-resolved
		echo "Restarted the DNS service. Please try the DNS resolution test again."
	fi
}

# Define a function to test HTTP connection
test_http_connection() {
	local url=$1
	if curl -Is $url | grep "200 OK" &>/dev/null; then
		echo "Successfully connected to $url."
	else
		echo "Failed to connect to $url. There might be an HTTP connectivity issue."
	fi
}
check_slack_status() {
	# Make a request to the Slack current status API
	local slack_response=$(curl -s https://status.slack.com/api/v2.0.0/current)
	local status=$(echo $slack_response | jq -r '.status')

	# Check the status from the response
	if [[ $status == "ok" ]]; then
		echo "Slack's status is ok."
	else
		echo "Slack is experiencing an issue."
		local incidents=$(echo $slack_response | jq -r '.active_incidents[] | .title')
		echo "Active incidents: $incidents"
	fi
}
# Define a function to monitor bandwidth using ifstat
monitor_bandwidth() {
	echo "Monitoring bandwidth for 10 seconds..."
	ifstat -t 10
}

# Define a function to display active network connections using netstat
show_active_connections() {
	echo "Displaying active network connections..."
	netstat -tuln
}

# Define a function to capture packets using tcpdump
capture_packets() {
	echo "Capturing packets for 10 seconds..."
	tcpdump -w captured_packets.pcap -c 100
	echo "Packets captured and saved to captured_packets.pcap"
}

# Define a function to perform DNS lookup using host
dns_lookup() {
	local domain=$1
	echo "Performing DNS lookup for $domain..."
	host $domain
}

# Define a function to scan open ports using nmap
scan_open_ports() {
	local target=$1
	echo "Scanning open ports on $target..."
	nmap $target
}
check_network_interface

# Call the functions with the servers and domains you want to test
ping_server "8.8.8.8"
test_dns_resolution "google.com"
test_http_connection "http://www.google.com"

# Ping health endpoints of specified services
ping_server "cloud.google.com"
# Call the new function to check Slack's status
check_slack_status
# monitor_bandwidth
show_active_connections
scan_open_ports $(hostname -I | awk '{print $1}')
# Uncomment the below lines if you want to execute these functions
# Note: capturing packets and scanning open ports can be network-intensive tasks
# capture_packets
# dns_lookup "example.com"
# scan_open_ports "localhost"
