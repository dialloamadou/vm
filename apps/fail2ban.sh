#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/
# Inspired by https://github.com/nextcloud/nextcloudpi/blob/master/etc/nextcloudpi-config.d/fail2ban.sh

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
NC_UPDATE=1 . <(curl -sL https://raw.githubusercontent.com/nextcloud/vm/master/lib.sh)
unset NC_UPDATE

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Nextcloud 13 is required.
lowest_compatible_nc 13

# Check if fail2ban is already installed
print_text_in_color "$ICyan" "Checking if Fail2Ban is already installed..."
if is_this_installed fail2ban
then
    choice=$(whiptail --radiolist "It seems like 'Fail2Ban' is already installed.\nChoose what you want to do.\nSelect by pressing the spacebar and ENTER" "$WT_HEIGHT" "$WT_WIDTH" 4 \
    "Uninstall Fail2Ban" "" OFF \
    "Reinstall Fail2Ban" "" ON 3>&1 1>&2 2>&3)
    
    case "$choice" in
        "Uninstall Fail2Ban")
            print_text_in_color "$ICyan" "Uninstalling Fail2Ban and resetting all settings..."
            fail2ban-client unban --all
            check_command apt purge fail2ban -y
            rm /etc/fail2ban/filter.d/nextcloud.conf
            rm /etc/fail2ban/jail.local
            msg_box "Fail2Ban was successfully uninstalled and all settings were resetted."
            exit
        ;;
        "Reinstall Fail2Ban")
            print_text_in_color "$ICyan" "Reinstalling Fail2Ban..."
            fail2ban-client unban --all
            check_command apt purge fail2ban -y
            rm /etc/fail2ban/filter.d/nextcloud.conf
            rm /etc/fail2ban/jail.local
        ;;
        *)
        ;;
    esac
else
    print_text_in_color "$ICyan" "Installing Fail2ban..."
fi

### Local variables ###
# location of Nextcloud logs
NCLOG="$(print_text_in_color "$ICyan" "Finding nextcloud.log..." && find / -name nextcloud.log -quit)"
# time to ban an IP that exceeded attempts
BANTIME_=600000
# cooldown time for incorrect passwords
FINDTIME_=1800
# failed attempts before banning an IP
MAXRETRY_=20

apt update -q4 & spinner_loading
check_command apt install fail2ban -y
check_command update-rc.d fail2ban disable

if [ -z "$NCLOG" ]
then
    print_text_in_color "$IRed" "nextcloud.log not found"
    print_text_in_color "$IRed" "Please add your logpath to $NCPATH/config/config.php and restart this script."
    exit 1
else
    chown www-data:www-data "$NCLOG"
fi

# Set values in config.php
occ_command config:system:set loglevel --value=2
occ_command config:system:set log_type --value=file
occ_command config:system:set logfile --value="$NCLOG"
occ_command config:system:set logtimezone --value="$(cat /etc/timezone)"

# Create nextcloud.conf file
# Test: failregex = Login failed.*Remote IP.*<HOST>
cat << NCONF > /etc/fail2ban/filter.d/nextcloud.conf
[Definition]
failregex=^{"reqId":".*","remoteAddr":".*","app":"core","message":"Login failed: '.*' \(Remote IP: '<HOST>'\)","level":2,"time":".*"}$
            ^{"reqId":".*","level":2,"time":".*","remoteAddr":".*","app":"core".*","message":"Login failed: '.*' \(Remote IP: '<HOST>'\)".*}$
            ^.*\"remoteAddr\":\"<HOST>\".*Trusted domain error.*\$
NCONF

# Disable default Debian sshd chain
check_command sed -i "s|true|false|g" /etc/fail2ban/jail.d/defaults-debian.conf 

# Create jail.local file
cat << FCONF > /etc/fail2ban/jail.local
# The DEFAULT allows a global definition of the options. They can be overridden
# in each jail afterwards.
[DEFAULT]

# "ignoreip" can be an IP address, a CIDR mask or a DNS host. Fail2ban will not
# ban a host which matches an address in this list. Several addresses can be
# defined using space separator.
ignoreip = 127.0.0.1/8 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8

# "bantime" is the number of seconds that a host is banned.
bantime  = $BANTIME_

# A host is banned if it has generated "maxretry" during the last "findtime"
# seconds.
findtime = $FINDTIME_
maxretry = $MAXRETRY_

#
# ACTIONS
#
banaction = iptables-multiport
protocol = tcp
chain = INPUT
action_ = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mw = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mwl = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action = %(action_)s

#
# SSH
#

[ssh]

enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = $MAXRETRY_

#
# HTTP servers
#

[nextcloud]

enabled  = true
port     = http,https
filter   = nextcloud
logpath  = $NCLOG
maxretry = $MAXRETRY_
FCONF

# Update settings
check_command update-rc.d fail2ban defaults
check_command update-rc.d fail2ban enable
check_command service fail2ban restart

# The End
msg_box "Fail2ban is now sucessfully installed.

Please use 'fail2ban-client set nextcloud unbanip <Banned IP>' to unban certain IPs
You can also use 'iptables -L -n' to check which IPs that are banned"

exit
