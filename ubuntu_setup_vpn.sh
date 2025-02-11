#!/bin/bash

# Default values
VPN_PORT="8443"
VPN_NETWORK="10.12.10.0"
VPN_NETMASK="255.255.255.0"
VPN_USERNAME="vpnuser"
VPN_PASSWORD="202300"

# Help message
show_help() {
    echo "Ubuntu VPN Server Setup Script"
    echo ""
    echo "Usage:"
    echo "./ubuntu_vpn_setup.sh \\"
    echo "    --vpn-port=8443 \\"
    echo "    --vpn-user=vpnuser \\"
    echo "    --vpn-pass=mypassword"
    echo ""
    echo "Parameters:"
    echo "  --vpn-port       : VPN port number (default: 8443)"
    echo "  --vpn-user       : VPN username (default: vpnuser)"
    echo "  --vpn-pass       : VPN password (default: 202300)"
    echo "  --vpn-network    : VPN network (default: 10.12.10.0)"
    echo "  --vpn-netmask    : VPN netmask (default: 255.255.255.0)"
}

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
}

# VPN setup function
setup_vpn() {
    echo "Starting VPN setup..."

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    # Install required packages
    echo "Installing OCServ..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ocserv gnutls-bin iptables iptables-persistent

    # Create SSL certificate
    echo "Creating SSL certificate..."
    mkdir -p /etc/ocserv/ssl
    cd /etc/ocserv/ssl
    certtool --generate-privkey --outfile server-key.pem

    # Create certificate template
    cat > /etc/ocserv/ssl/server.tmpl << EOF
organization = "VPN Server"
expiration_days = 3650
cn = "VPN Server"
tls_www_server
signing_key
encryption_key
EOF

    # Sign certificate
    certtool --generate-self-signed --load-privkey server-key.pem --template server.tmpl --outfile server-cert.pem

    # Configure OCServ
    echo "Configuring OCServ..."
    sed -i "s/^auth =.*/auth = \"plain[passwd=\/etc\/ocserv\/ocpasswd]\"/" /etc/ocserv/ocserv.conf
    sed -i "s/^tcp-port =.*/tcp-port = $VPN_PORT/" /etc/ocserv/ocserv.conf
    sed -i "s/^udp-port =.*/udp-port = $VPN_PORT/" /etc/ocserv/ocserv.conf

    # Remove commented certificate settings and add new ones
    sed -i "/^#.*server-cert/d" /etc/ocserv/ocserv.conf
    sed -i "/^#.*server-key/d" /etc/ocserv/ocserv.conf
    echo "server-cert = /etc/ocserv/ssl/server-cert.pem" >> /etc/ocserv/ocserv.conf
    echo "server-key = /etc/ocserv/ssl/server-key.pem" >> /etc/ocserv/ocserv.conf

    # Configure network settings
    sed -i "s/^try-mtu-discovery =.*/try-mtu-discovery = true/" /etc/ocserv/ocserv.conf
    sed -i "s/^default-domain =.*/default-domain = vpn.server.com/" /etc/ocserv/ocserv.conf
    sed -i "s/^ipv4-network =.*/ipv4-network = $VPN_NETWORK/" /etc/ocserv/ocserv.conf
    sed -i "s/^ipv4-netmask =.*/ipv4-netmask = $VPN_NETMASK/" /etc/ocserv/ocserv.conf

    # Configure MTU and DNS settings
    sed -i "s/^#tunnel-all-dns.*/tunnel-all-dns = false/" /etc/ocserv/ocserv.conf
    sed -i "s/^#mtu.*/mtu = 1420/" /etc/ocserv/ocserv.conf

    # Clear and set routes
    sed -i "/^route = /d" /etc/ocserv/ocserv.conf
    echo "no-route = 0.0.0.0/128.0.0.0" >> /etc/ocserv/ocserv.conf
    echo "no-route = 128.0.0.0/128.0.0.0" >> /etc/ocserv/ocserv.conf

    # Create socket directory
    mkdir -p /run/ocserv

    # Configure firewall
    echo "Configuring firewall rules..."
    
    # Clear existing rules
    iptables -F
    iptables -t nat -F
    
    # Set default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow SSH (port 22)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow VPN ports
    iptables -A INPUT -p tcp --dport $VPN_PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $VPN_PORT -j ACCEPT
    
    # Enable NAT for VPN network
    iptables -t nat -A POSTROUTING -s $VPN_NETWORK/24 -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    
    # Save firewall rules
    iptables-save > /etc/iptables/rules.v4
    
    # Create VPN user
    echo "Creating VPN user..."
    mkdir -p /etc/ocserv
    echo "$VPN_PASSWORD" | ocpasswd -c /etc/ocserv/ocpasswd $VPN_USERNAME

    # Enable and start OCServ service
    systemctl enable ocserv
    systemctl restart ocserv

    # Get server's IP address
    SERVER_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

    echo "VPN setup completed!"
    echo "VPN username: $VPN_USERNAME"
    echo "VPN password: $VPN_PASSWORD"
    echo "VPN server IP: $SERVER_IP"
    echo "VPN port: $VPN_PORT"
    echo "Supported protocols: TCP/$VPN_PORT and UDP/$VPN_PORT"
}

# Main program
check_root

# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        --vpn-port=*)
            VPN_PORT="${1#*=}"
            ;;
        --vpn-user=*)
            VPN_USERNAME="${1#*=}"
            ;;
        --vpn-pass=*)
            VPN_PASSWORD="${1#*=}"
            ;;
        --vpn-network=*)
            VPN_NETWORK="${1#*=}"
            ;;
        --vpn-netmask=*)
            VPN_NETMASK="${1#*=}"
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
    shift
done

# Run VPN setup
setup_vpn

exit 0