#!/bin/bash

# ===========================================
# Ubuntu VPN Server Setup Script
# ===========================================
#
# Bu script Ubuntu sunucuda OpenConnect VPN (ocserv) kurulumunu otomatikleştirir.
# 
# Özellikler:
# - OpenConnect VPN sunucu kurulumu
# - Otomatik SSL sertifika oluşturma
# - Esnek routing yapılandırması (tüm trafik veya sadece iç ağlar)
# - Opsiyonel firewall yapılandırması
# - UFW ve iptables desteği
#
# Temel Kullanım:
# --------------
# Minimal kurulum:
#   ./ubuntu_vpn_setup.sh
#
# Tüm trafiği VPN üzerinden yönlendirme:
#   ./ubuntu_vpn_setup.sh --all-traffic
#
# Sadece belirli ağları yönlendirme:
#   ./ubuntu_vpn_setup.sh --route=10.10.10.0/24 --route=192.168.0.0/16
#
# Firewall olmadan kurulum:
#   ./ubuntu_vpn_setup.sh --no-firewall
#
# Tam özelleştirmeli kurulum:
#   ./ubuntu_vpn_setup.sh \
#     --vpn-port=443 \
#     --vpn-user=myuser \
#     --vpn-pass=mypass \
#     --route=10.10.10.0/24 \
#     --route=192.168.0.0/16 \
#     --all-traffic \
#     --no-firewall
#
# Varsayılan Değerler:
# ------------------
# VPN Port: 8443
# VPN User: vpnuser
# VPN Pass: 202300
# VPN Network: 10.12.10.0
# VPN Netmask: 255.255.255.0
#
# Notlar:
# ------
# - Script root yetkisi gerektirir
# - UFW varsa otomatik devre dışı bırakılır
# - --all-traffic kullanılmazsa sadece belirtilen ağlar yönlendirilir
# - --no-firewall kullanılmazsa temel güvenlik kuralları uygulanır
#
#apt-get update && apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/ubuntu_setup_vpn.sh && dos2unix ubuntu_setup_vpn.sh && chmod +x ubuntu_setup_vpn.sh && ./ubuntu_vpn_setup.sh \
#     --vpn-port=443 \
#     --vpn-user=myuser \
#     --vpn-pass=mypass \
#     --route=10.10.10.0/24 \
#     --route=192.168.0.0/16 \
#     --all-traffic \
#     --no-firewall
# ===========================================

# Default values
VPN_PORT="8443"
VPN_NETWORK="10.12.10.0"
VPN_NETMASK="255.255.255.0"
VPN_USERNAME="vpnuser"
VPN_PASSWORD="202300"
ROUTE_ALL_TRAFFIC=false
INTERNAL_ROUTES=()
USE_FIREWALL=true

# Help message
show_help() {
    echo "Ubuntu VPN Server Setup Script"
    echo ""
    echo "Usage:"
    echo "./ubuntu_vpn_setup.sh \\"
    echo "    --vpn-port=8443 \\"
    echo "    --vpn-user=vpnuser \\"
    echo "    --vpn-pass=mypassword \\"
    echo "    --route=10.10.10.0/24 \\"
    echo "    --route=192.168.0.0/16 \\"
    echo "    --all-traffic \\"
    echo "    --no-firewall"
    echo ""
    echo "Parameters:"
    echo "  --vpn-port       : VPN port number (default: 8443)"
    echo "  --vpn-user       : VPN username (default: vpnuser)"
    echo "  --vpn-pass       : VPN password (default: 202300)"
    echo "  --vpn-network    : VPN network (default: 10.12.10.0)"
    echo "  --vpn-netmask    : VPN netmask (default: 255.255.255.0)"
    echo "  --route          : Internal network route (can be used multiple times)"
    echo "  --all-traffic    : Route all traffic through VPN (optional)"
echo "  --no-firewall    : Disable firewall configuration"
}

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
}

# Function to convert CIDR to netmask
cidr_to_netmask() {
    local cidr=$1
    local ip=${cidr%/*}
    local bits=${cidr#*/}
    local mask=""
    
    # Extract only the netmask part using ipcalc if available
    if command -v ipcalc >/dev/null 2>&1; then
        mask=$(ipcalc "$cidr" | grep Netmask | awk '{print $2}')
    else
        # Fallback manual calculation if ipcalc is not available
        local full_mask=$((0xffffffff << (32 - bits)))
        local oct1=$((full_mask >> 24 & 255))
        local oct2=$((full_mask >> 16 & 255))
        local oct3=$((full_mask >> 8 & 255))
        local oct4=$((full_mask & 255))
        mask="$oct1.$oct2.$oct3.$oct4"
    fi
    
    echo "$ip/$mask"
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
    DEBIAN_FRONTEND=noninteractive apt-get install -y ocserv gnutls-bin iptables iptables-persistent ipcalc

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
    sed -i "s/^#tunnel-all-dns.*/tunnel-all-dns = $ROUTE_ALL_TRAFFIC/" /etc/ocserv/ocserv.conf
    sed -i "s/^#mtu.*/mtu = 1420/" /etc/ocserv/ocserv.conf

    # Configure routing based on parameters
    sed -i "/^route = /d" /etc/ocserv/ocserv.conf
    
    if [ "$ROUTE_ALL_TRAFFIC" = true ]; then
        echo "Configuring to route all traffic..."
        echo "route = default" >> /etc/ocserv/ocserv.conf
    else
        echo "Configuring internal routes only..."
        # Add each internal route
        for route in "${INTERNAL_ROUTES[@]}"; do
            IFS='/' read -r ip mask <<< "$route"
            echo "route = $ip/255.255.255.0" >> /etc/ocserv/ocserv.conf
        done
    fi

    # Create socket directory
    mkdir -p /run/ocserv

    # Check if UFW is installed and active
    if command -v ufw >/dev/null 2>&1; then
        echo "Detected UFW firewall..."
        ufw disable
        echo "UFW firewall disabled"
    fi

    # Configure firewall if enabled
    if [ "$USE_FIREWALL" = true ]; then
        echo "Configuring firewall rules..."
    
    # Clear existing rules
    iptables -F
    iptables -t nat -F
    
    # Set default policies
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
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
    fi
    
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
    if [ "$ROUTE_ALL_TRAFFIC" = true ]; then
        echo "Routing: All traffic"
    else
        echo "Routing: Internal networks only"
        for route in "${INTERNAL_ROUTES[@]}"; do
            echo "  - $route"
        done
    fi
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
        --route=*)
            INTERNAL_ROUTES+=("${1#*=}")
            ;;
        --all-traffic)
            ROUTE_ALL_TRAFFIC=true
            ;;
        --no-firewall)
            USE_FIREWALL=false
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
