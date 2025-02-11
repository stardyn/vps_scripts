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
# - AWS uyumlu network interface tespiti
#
# Hızlı Kurulum:
# -------------
# apt-get update && apt-get install -y dos2unix && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/ubuntu_setup_vpn.sh && dos2unix ubuntu_setup_vpn.sh && chmod +x ubuntu_setup_vpn.sh
#
# Kullanım Örnekleri:
# -----------------
# 1. Basit Kurulum (Sadece iç ağ erişimi):
#    ./ubuntu_setup_vpn.sh
#
# 2. Tüm Trafik VPN Üzerinden:
#    ./ubuntu_setup_vpn.sh --all-traffic
#
# 3. Tüm Trafik + Firewall Kapalı:
#    ./ubuntu_setup_vpn.sh --all-traffic --no-firewall
#
# 4. Özel Ağlar İçin:
#    ./ubuntu_setup_vpn.sh --route=10.10.10.0/24 --route=192.168.0.0/16
#
# 5. Tam Özelleştirme:
#    ./ubuntu_setup_vpn.sh \
#      --vpn-port=443 \
#      --vpn-user=myuser \
#      --vpn-pass=mypass \
#      --route=10.10.10.0/24 \
#      --all-traffic \
#      --no-firewall
#
# Varsayılan Değerler:
# ------------------
# VPN Port: 8443
# VPN User: vpnuser
# VPN Pass: 202300
# VPN Network: 10.12.10.0
# VPN Netmask: 255.255.255.0
#
# ===========================================

# Varsayılan değerler
VPN_PORT="8443"
VPN_NETWORK="10.12.10.0"
VPN_NETMASK="255.255.255.0"
VPN_USERNAME="vpnuser"
VPN_PASSWORD="202300"
ROUTE_ALL_TRAFFIC=false
INTERNAL_ROUTES=()
USE_FIREWALL=true

# Global değişkenler
PRIMARY_INTERFACE=""
SERVER_IP=""

# Yardım mesajı
show_help() {
    echo "Ubuntu VPN Server Setup Script"
    echo ""
    echo "Kullanım:"
    echo "./ubuntu_setup_vpn.sh [SEÇENEKLER]"
    echo ""
    echo "Seçenekler:"
    echo "  --vpn-port=PORT    : VPN port numarası (varsayılan: 8443)"
    echo "  --vpn-user=USER    : VPN kullanıcı adı (varsayılan: vpnuser)"
    echo "  --vpn-pass=PASS    : VPN şifresi (varsayılan: 202300)"
    echo "  --route=NETWORK    : İç ağ rotası (birden fazla kullanılabilir)"
    echo "  --all-traffic      : Tüm trafiği VPN üzerinden yönlendir"
    echo "  --no-firewall      : Firewall yapılandırmasını devre dışı bırak"
    echo ""
    echo "Örnek:"
    echo "  ./ubuntu_setup_vpn.sh --all-traffic --vpn-port=443"
}

# Root kontrolü
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Hata: Bu script root yetkisi gerektirir"
        exit 1
    fi
}

# Network interface tespiti
detect_network_interface() {
    # İlk olarak default route'dan tespit et
    PRIMARY_INTERFACE=$(ip route | grep default | head -n1 | awk '{print $5}')
    
    # Bulunamazsa, UP durumundaki ilk interface'i bul
    if [ -z "$PRIMARY_INTERFACE" ]; then
        PRIMARY_INTERFACE=$(ip link show | grep -v 'lo:' | grep 'state UP' | head -n1 | awk -F: '{print $2}' | tr -d ' ')
    fi
    
    # AWS'de yaygın interface isimlerini kontrol et
    if [ -z "$PRIMARY_INTERFACE" ]; then
        for iface in eth0 ens5 ens3 ena0; do
            if ip link show $iface >/dev/null 2>&1; then
                PRIMARY_INTERFACE=$iface
                break
            fi
        done
    fi
    
    if [ -z "$PRIMARY_INTERFACE" ]; then
        echo "Hata: Network interface tespit edilemedi!"
        exit 1
    fi
    
    # Server IP adresini tespit et
    SERVER_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
    
    echo "Tespit edilen network interface: $PRIMARY_INTERFACE"
    echo "Sunucu IP adresi: $SERVER_IP"
}

# VPN kurulum fonksiyonu
setup_vpn() {
    echo "VPN kurulumu başlatılıyor..."
    
    # Network interface tespiti
    detect_network_interface
    
    # IP forwarding aktif et
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    # Gerekli paketleri kur
    echo "OCServ kuruluyor..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ocserv gnutls-bin iptables iptables-persistent

    # SSL sertifikası oluştur
    echo "SSL sertifikası oluşturuluyor..."
    mkdir -p /etc/ocserv/ssl
    cd /etc/ocserv/ssl
    certtool --generate-privkey --outfile server-key.pem

    # Sertifika şablonu oluştur
    cat > /etc/ocserv/ssl/server.tmpl << EOF
organization = "VPN Server"
expiration_days = 3650
cn = "VPN Server"
tls_www_server
signing_key
encryption_key
EOF

    # Sertifikayı imzala
    certtool --generate-self-signed --load-privkey server-key.pem --template server.tmpl --outfile server-cert.pem

    # OCServ yapılandırması
    echo "OCServ yapılandırılıyor..."
    
    # Yedek oluştur
    cp /etc/ocserv/ocserv.conf /etc/ocserv/ocserv.conf.bak
    
    # Ana ayarlar
    sed -i "s/^auth =.*/auth = \"plain[passwd=\/etc\/ocserv\/ocpasswd]\"/" /etc/ocserv/ocserv.conf
    sed -i "s/^tcp-port =.*/tcp-port = $VPN_PORT/" /etc/ocserv/ocserv.conf
    sed -i "s/^udp-port =.*/udp-port = $VPN_PORT/" /etc/ocserv/ocserv.conf
    
    # Sertifika ayarları
    sed -i "/^#.*server-cert/d" /etc/ocserv/ocserv.conf
    sed -i "/^#.*server-key/d" /etc/ocserv/ocserv.conf
    echo "server-cert = /etc/ocserv/ssl/server-cert.pem" >> /etc/ocserv/ocserv.conf
    echo "server-key = /etc/ocserv/ssl/server-key.pem" >> /etc/ocserv/ocserv.conf
    
    # Network ayarları
    sed -i "s/^try-mtu-discovery =.*/try-mtu-discovery = true/" /etc/ocserv/ocserv.conf
    sed -i "s/^default-domain =.*/default-domain = vpn.server.com/" /etc/ocserv/ocserv.conf
    sed -i "s/^ipv4-network =.*/ipv4-network = $VPN_NETWORK/" /etc/ocserv/ocserv.conf
    sed -i "s/^ipv4-netmask =.*/ipv4-netmask = $VPN_NETMASK/" /etc/ocserv/ocserv.conf
    
    # DNS ve MTU ayarları
    sed -i "s/^#\?mtu =.*/mtu = 1480/" /etc/ocserv/ocserv.conf
    
    # max-clients ayarı
    sed -i "s/^#\?max-clients =.*/max-clients = 16/" /etc/ocserv/ocserv.conf
    sed -i "s/^#\?max-same-clients =.*/max-same-clients = 2/" /etc/ocserv/ocserv.conf
    
    # Keepalive ayarları
    sed -i "s/^#\?keepalive =.*/keepalive = 32400/" /etc/ocserv/ocserv.conf
    sed -i "s/^#\?dpd =.*/dpd = 90/" /etc/ocserv/ocserv.conf
    sed -i "s/^#\?mobile-dpd =.*/mobile-dpd = 1800/" /etc/ocserv/ocserv.conf
    
    # Session timeout
    sed -i "s/^#\?session-timeout =.*/session-timeout = 86400/" /etc/ocserv/ocserv.conf
    
    # DNS ayarları ekle
    sed -i "/^dns = /d" /etc/ocserv/ocserv.conf
    echo "dns = 8.8.8.8" >> /etc/ocserv/ocserv.conf
    echo "dns = 8.8.4.4" >> /etc/ocserv/ocserv.conf
    
    # Routing ayarları
    sed -i "/^route = /d" /etc/ocserv/ocserv.conf
    if [ "$ROUTE_ALL_TRAFFIC" = true ]; then
        echo "Tüm trafik VPN üzerinden yönlendirilecek..."
        echo "route = default" >> /etc/ocserv/ocserv.conf
        sed -i "s/^#\?tunnel-all-dns =.*/tunnel-all-dns = true/" /etc/ocserv/ocserv.conf
    else
        echo "Sadece belirtilen ağlar yönlendirilecek..."
        for route in "${INTERNAL_ROUTES[@]}"; do
            echo "route = $route" >> /etc/ocserv/ocserv.conf
        done
        sed -i "s/^#\?tunnel-all-dns =.*/tunnel-all-dns = false/" /etc/ocserv/ocserv.conf
    fi

    # Socket dizini oluştur
    mkdir -p /run/ocserv

    # UFW kontrolü ve devre dışı bırakma
    if command -v ufw >/dev/null 2>&1; then
        echo "UFW tespit edildi, devre dışı bırakılıyor..."
        ufw disable
    fi

    # Nat yapılandırması
	echo "Nat yapılandırılıyor..."
	
	# Mevcut kuralları temizle
	iptables -F
	iptables -t nat -F
	iptables -t mangle -F
	
	# Varsayılan politikalar
	iptables -P INPUT ACCEPT
	iptables -P FORWARD ACCEPT
	iptables -P OUTPUT ACCEPT
	
	# Temel kurallar
	iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
	iptables -A INPUT -i lo -j ACCEPT
	iptables -A INPUT -p tcp --dport 22 -j ACCEPT
	iptables -A INPUT -p tcp --dport $VPN_PORT -j ACCEPT
	iptables -A INPUT -p udp --dport $VPN_PORT -j ACCEPT
	
	# FORWARD kuralları
	iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -A FORWARD -s $VPN_NETWORK/24 -j ACCEPT
	
	# NAT kuralları
	iptables -t nat -A POSTROUTING -o $PRIMARY_INTERFACE -j MASQUERADE
	iptables -t nat -A POSTROUTING -s $VPN_NETWORK/24 -o $PRIMARY_INTERFACE -j MASQUERADE
	
	# MASQUERADE için FORWARD chain'de accept
	iptables -A FORWARD -i $PRIMARY_INTERFACE -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -A FORWARD -i tun+ -o $PRIMARY_INTERFACE -j ACCEPT
	
	# Kuralları kaydet
	iptables-save > /etc/iptables/rules.v4

    # VPN kullanıcısı oluştur
    echo "VPN kullanıcısı oluşturuluyor..."
    mkdir -p /etc/ocserv
    echo "$VPN_PASSWORD" | ocpasswd -c /etc/ocserv/ocpasswd $VPN_USERNAME

    # OCServ servisini başlat
    systemctl enable ocserv
    systemctl restart ocserv

    # Yeniden başlatma sonrası ayarların kalıcı olması için
    if [ -f /etc/networkd-dispatcher/routable.d/50-ifup-hooks ]; then
        echo "iptables-restore < /etc/iptables/rules.v4" >> /etc/networkd-dispatcher/routable.d/50-ifup-hooks
        chmod +x /etc/networkd-dispatcher/routable.d/50-ifup-hooks
    fi

    echo "VPN kurulumu tamamlandı!"
    echo "========================="
    echo "Network interface: $PRIMARY_INTERFACE"
    echo "VPN kullanıcı adı: $VPN_USERNAME"
    echo "VPN şifresi: $VPN_PASSWORD"
    echo "VPN sunucu IP: $SERVER_IP"
    echo "VPN port: $VPN_PORT"
    echo "Desteklenen protokoller: TCP/$VPN_PORT ve UDP/$VPN_PORT"
    echo "Firewall durumu: $( [ "$USE_FIREWALL" = true ] && echo "aktif" || echo "pasif" )"
    echo "Routing: $( [ "$ROUTE_ALL_TRAFFIC" = true ] && echo "Tüm trafik" || echo "Sadece iç ağlar" )"
    if [ "$ROUTE_ALL_TRAFFIC" = false ] && [ ${#INTERNAL_ROUTES[@]} -gt 0 ]; then
        echo "Yönlendirilen ağlar:"
        for route in "${INTERNAL_ROUTES[@]}"; do
            echo "  - $route"
        done
    fi
    echo "========================="
}

# Ana program başlangıcı
check_root

# Parametreleri işle
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
            echo "Hata: Bilinmeyen parametre: $1"
            show_help
            exit 1
            ;;
    esac
    shift
done

# VPN kurulumunu başlat
setup_vpn

exit 0
