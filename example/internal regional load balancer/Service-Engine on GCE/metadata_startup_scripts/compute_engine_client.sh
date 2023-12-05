if [[ -f /etc/startup_was_launched ]]; then exit 0; fi
apt-get update
apt-get install jq -y --no-install-recommends

####### End of startup script #######
touch /etc/startup_was_launched
