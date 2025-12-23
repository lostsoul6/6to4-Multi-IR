#!/bin/bash

echo "What should I do?"
echo "1) 6to4"
echo "2) Remove tunnels"
echo "3) Enable BBR"
echo "4) Fix Whatsapp Time"
echo "5) Optimize"
echo "6) Install x-ui"
echo "7) Change NameServer"
echo "8) Disable IPv6 - After server reboot IPv6 is activated"
read -p "Select an option (1, 2, 3, 4, 5, 6, 7, or 8): " server_choice

setup_rc_local() {
    FILE="/etc/rc.local"
    commands="$1"

    # Ensure the file exists and is executable
    if [ ! -f "$FILE" ]; then
        echo -e '#! /bin/bash\n\nexit 0' | tee "$FILE" > /dev/null
        chmod +x "$FILE"
    fi

    # Check if the file already contains content and add new commands accordingly
    if grep -q 'ip tunnel add' "$FILE"; then
        # If the file has existing commands, add new ones above 'exit 0'
        bash -c "sed -i '/exit 0/i $commands' $FILE"
    else
        # If the file is empty or does not have the relevant commands, replace its content
        bash -c "echo -e '#! /bin/bash\n\n$commands\n\nexit 0' > $FILE"
    fi
    echo "Commands added to /etc/rc.local"
}

# Function to handle Fix Whatsapp Time option
fix_whatsapp_time() {
    commands="timedatectl set-timezone Asia/Tehran"
    setup_rc_local "$commands"
    echo "Whatsapp time fixed to Asia/Tehran timezone."
}

# Function to handle Optimize option
optimize() {
    USER_CONF="/etc/systemd/user.conf"
    SYSTEM_CONF="/etc/systemd/system.conf"
    LIMITS_CONF="/etc/security/limits.conf"
    SYSCTL_CONF="/etc/sysctl.d/local.conf"
    TEMP_USER_CONF=$(mktemp)
    TEMP_SYSTEM_CONF=$(mktemp)

    # Function to add line if not exists
    add_line_if_not_exists() {
        local file="$1"
        local line="$2"
        local temp_file="$3"

        if [ -f "$file" ];then
            cp "$file" "$temp_file"
            if ! grep -q "$line" "$file"; then
                sed -i '/^\[Manager\]/a '"$line" "$temp_file"
                mv "$temp_file" "$file"
                echo "Added '$line' to $file"
            else
                echo "The line '$line' already exists in $file"
                rm "$temp_file"
            fi
        else
            echo "$file does not exist."
            rm "$temp_file"
        fi
    }

    # Optimize user.conf
    add_line_if_not_exists "$USER_CONF" "DefaultLimitNOFILE=1024000" "$TEMP_USER_CONF"

    # Optimize system.conf
    add_line_if_not_exists "$SYSTEM_CONF" "DefaultLimitNOFILE=1024000" "$TEMP_SYSTEM_CONF"

    # Optimize limits.conf
    if [ -f "$LIMITS_CONF" ];then
        cat <<EOF | tee -a "$LIMITS_CONF"
* hard nofile 1024000
* soft nofile 1024000
root hard nofile 1024000
root soft nofile 1024000
EOF
        echo "Added limits to $LIMITS_CONF"
    else
        echo "$LIMITS_CONF does not exist."
    fi

    # Optimize sysctl.d/local.conf
    cat <<EOF | tee "$SYSCTL_CONF"
# max open files
fs.file-max = 1024000
EOF
    echo "Added sysctl settings to $SYSCTL_CONF"

    # Apply sysctl changes
    sysctl --system
    echo "Sysctl changes applied."
}

# Function to install x-ui
install_x_ui() {
    echo "Choose the version of x-ui to install:"
    echo "1) alireza"
    echo "2) MHSanaei"
    read -p "Select an option (1 or 2): " xui_choice

    if [ "$xui_choice" -eq 1 ]; then
        bash <(curl -Ls https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh)
        echo "alireza version of x-ui installed."
    elif [ "$xui_choice" -eq 2 ]; then
        bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
        echo "MHSanaei version of x-ui installed."
    else
        echo "Invalid option. Please select 1 or 2."
    fi
}

# Function to disable IPv6
disable_ipv6() {
    commands=$(cat <<EOF
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
EOF
)

    eval "$commands"
    echo "IPv6 has been disabled. This change is temporary and will revert after reboot."
}

# Function to change NameServer
change_nameserver() {
    FILE="/etc/resolv.conf"
    if [ -f "$FILE" ]; then
        # Backup the original file
        cp "$FILE" "${FILE}.bak"

        # Remove existing nameserver lines
        sed -i '/^nameserver /d' "$FILE"

        # Add new nameserver lines
        echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | tee -a "$FILE" > /dev/null

        echo "NameServers have been updated."
    else
        echo "$FILE does not exist."
    fi
}

# Function to handle 6to4 option - Supports up to 2 Iran servers
handle_six_to_four() {
    echo "Choose the type of server:"
    echo "1) Kharej (Outside) - Supports up to 2 Iran servers for redundancy"
    echo "2) Iran (Server 1 or 2)"
    read -p "Select an option (1 or 2): " six_to_four_choice

    if [ "$six_to_four_choice" -eq 1 ]; then
        # Kharej side
        read -p "Enter the Kharej (outside) IPv4 address: " ipkharej

        echo "How many Iran servers do you want to connect? (1 or 2 for redundancy)"
        read -p "Number (1/2): " num_iran
        if [ "$num_iran" != "1" ] && [ "$num_iran" != "2" ]; then
            echo "Invalid choice. Defaulting to 2."
            num_iran=2
        fi

        commands=""

        # Iran Server 1
        if [ "$num_iran" -ge 1 ]; then
            read -p "Enter IPv4 address of Iran Server 1: " ipiran1
            commands+="ip tunnel add 6to4_To_IR1 mode sit remote $ipiran1 local $ipkharej\n"
            commands+="ip -6 addr add 2010:5a8:2e20:f2e::2/64 dev 6to4_To_IR1\n"
            commands+="ip link set 6to4_To_IR1 mtu 1420\n"
            commands+="ip link set 6to4_To_IR1 up\n\n"

            commands+="ip -6 tunnel add GRE6Tun_To_IR1 mode ip6gre remote 2010:5a8:2e20:f2e::1 local 2010:5a8:2e20:f2e::2\n"
            commands+="ip addr add 121.113.9.2/30 dev GRE6Tun_To_IR1\n"
            commands+="ip link set GRE6Tun_To_IR1 mtu 1420\n"
            commands+="ip link set GRE6Tun_To_IR1 up\n\n"
        fi

        # Iran Server 2
        if [ "$num_iran" -ge 2 ]; then
            read -p "Enter IPv4 address of Iran Server 2: " ipiran2
            commands+="ip tunnel add 6to4_To_IR2 mode sit remote $ipiran2 local $ipkharej\n"
            commands+="ip -6 addr add 2010:5a8:2e20:f3e::2/64 dev 6to4_To_IR2\n"
            commands+="ip link set 6to4_To_IR2 mtu 1420\n"
            commands+="ip link set 6to4_To_IR2 up\n\n"

            commands+="ip -6 tunnel add GRE6Tun_To_IR2 mode ip6gre remote 2010:5a8:2e20:f3e::1 local 2010:5a8:2e20:f3e::2\n"
            commands+="ip addr add 121.113.10.2/30 dev GRE6Tun_To_IR2\n"
            commands+="ip link set GRE6Tun_To_IR2 mtu 1420\n"
            commands+="ip link set GRE6Tun_To_IR2 up\n\n"
        fi

        eval "$commands"
        setup_rc_local "$commands"
        echo "Kharej server configured for $num_iran Iran server(s). Tunnels created."

    elif [ "$six_to_four_choice" -eq 2 ]; then
        # Iran side
        read -p "Is this Iran Server 1 or 2? (1/2): " iran_number
        if [ "$iran_number" != "1" ] && [ "$iran_number" != "2" ]; then
            echo "Invalid. Please run again and enter 1 or 2."
            return
        fi

        read -p "Enter this Iran server's IPv4 address: " ipiran
        read -p "Enter the Kharej (outside) IPv4 address: " ipkharej

        if [ "$iran_number" -eq 1 ]; then
            prefix="f2e"
            priv_ip="121.113.9.1/30"
            remote_gre="2010:5a8:2e20:f2e::2"
            local_gre="2010:5a8:2e20:f2e::1/64"
            remote_nat="121.113.9.2"
        else
            prefix="f3e"
            priv_ip="121.113.10.1/30"
            remote_gre="2010:5a8:2e20:f3e::2"
            local_gre="2010:5a8:2e20:f3e::1/64"
            remote_nat="121.113.10.2"
        fi

        commands=$(cat <<EOF
ip tunnel add 6to4_To_KH mode sit remote $ipkharej local $ipiran
ip -6 addr add $local_gre dev 6to4_To_KH
ip link set 6to4_To_KH mtu 1420
ip link set 6to4_To_KH up

ip -6 tunnel add GRE6Tun_To_KH mode ip6gre remote $remote_gre local $local_gre
ip addr add $priv_ip dev GRE6Tun_To_KH
ip link set GRE6Tun_To_KH mtu 1420
ip link set GRE6Tun_To_KH up

sysctl net.ipv4.ip_forward=1
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination $priv_ip
iptables -t nat -A PREROUTING -j DNAT --to-destination $remote_nat
iptables -t nat -A POSTROUTING -j MASQUERADE
EOF
)

        eval "$commands"
        setup_rc_local "$commands"
        echo "Iran Server $iran_number configured successfully."

    else
        echo "Invalid option."
    fi
}

# Execute the selected option
case $server_choice in
    1)
        handle_six_to_four
        ;;
    2)
        echo "Removing all 6to4 tunnels (for 1 or 2 Iran servers)..."

        # Remove Iran Server 1 tunnels
        ip tunnel del 6to4_To_IR1 2>/dev/null || true
        ip -6 tunnel del GRE6Tun_To_IR1 2>/dev/null || true
        ip link del 6to4_To_IR1 2>/dev/null || true
        ip link del GRE6Tun_To_IR1 2>/dev/null || true

        # Remove Iran Server 2 tunnels
        ip tunnel del 6to4_To_IR2 2>/dev/null || true
        ip -6 tunnel del GRE6Tun_To_IR2 2>/dev/null || true
        ip link del 6to4_To_IR2 2>/dev/null || true
        ip link del GRE6Tun_To_IR2 2>/dev/null || true

        # Backward compatibility - old single tunnel names
        ip tunnel del 6to4_To_IR 2>/dev/null || true
        ip -6 tunnel del GRE6Tun_To_IR 2>/dev/null || true
        ip link del 6to4_To_IR 2>/dev/null || true
        ip link del GRE6Tun_To_IR 2>/dev/null || true

        # Iran-side interfaces
        ip tunnel del 6to4_To_KH 2>/dev/null || true
        ip -6 tunnel del GRE6Tun_To_KH 2>/dev/null || true
        ip link del 6to4_To_KH 2>/dev/null || true
        ip link del GRE6Tun_To_KH 2>/dev/null || true

        # Remove NAT rules for both subnets
        iptables -t nat -D PREROUTING -p tcp --dport 22 -j DNAT --to-destination 121.113.9.1 2>/dev/null || true
        iptables -t nat -D PREROUTING -j DNAT --to-destination 121.113.9.2 2>/dev/null || true
        iptables -t nat -D PREROUTING -p tcp --dport 22 -j DNAT --to-destination 121.113.10.1 2>/dev/null || true
        iptables -t nat -D PREROUTING -j DNAT --to-destination 121.113.10.2 2>/dev/null || true
        iptables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null || true

        # Reset rc.local
        echo -e '#! /bin/bash\n\nexit 0' | tee /etc/rc.local > /dev/null
        chmod +x /etc/rc.local

        echo "All tunnels and related rules have been removed."
        echo "/etc/rc.local has been reset."
        ;;
    3)
        wget --no-check-certificate -O /opt/bbr.sh https://github.com/teddysun/across/raw/master/bbr.sh
        chmod 755 /opt/bbr.sh
        /opt/bbr.sh
        echo "BBR optimization enabled."
        ;;
    4)
        fix_whatsapp_time
        ;;
    5)
        optimize
        ;;
    6)
        install_x_ui
        ;;
    7)
        change_nameserver
        ;;
    8)
        disable_ipv6
        ;;
    *)
        echo "Invalid option. Please select 1, 2, 3, 4, 5, 6, 7, or 8."
        ;;
esac
