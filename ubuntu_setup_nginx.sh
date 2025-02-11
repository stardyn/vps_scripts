#!/bin/bash
#apt-get update && apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/ubuntu_setup_nginx.sh && dos2unix ubuntu_setup_nginx.sh && chmod +x ubuntu_setup_nginx.sh && ./ubuntu_setup_nginx.sh

# Root yetkisi kontrolü ve yükseltme
if [ "$EUID" -ne 0 ]; then
    echo "Root yetkisi gerekiyor... Yetki yükseltme deneniyor..."
    exec sudo "$0" "$@"
    exit $?
fi

# Hata durumunda scripti durdur
set -e

# Sistem güncellemesi
echo "Sistem güncelleniyor..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Nginx kurulumu
echo "Nginx kuruluyor..."
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx nginx-extras certbot python3-certbot-nginx

# Nginx servisini başlat ve otomatik başlatmayı etkinleştir
echo "Nginx servisi başlatılıyor..."
systemctl start nginx
systemctl enable nginx

# UFW kontrolü ve devre dışı bırakma
if command -v ufw >/dev/null 2>&1; then
	echo "UFW tespit edildi, devre dışı bırakılıyor..."
	systemctl disable ufw
	systemctl stop ufw
	apt-get remove -y ufw
fi

# Web dizini oluştur ve yetkilendir
echo "Web dizini oluşturuluyor..."
mkdir -p /srv

# Basit ve direkt yetkilendirme
chown -R yonetici /srv

# Nginx yapılandırmasını test et
echo "Nginx yapılandırması test ediliyor..."
nginx -t

# Nginx'i yeniden başlat
echo "Nginx yeniden başlatılıyor..."
systemctl restart nginx

# Kurulum bilgilerini göster
echo "Nginx kurulumu tamamlandı!"
echo "Web sunucusu IP adresi: $(curl -s ifconfig.me)"
echo "Web dizini: /srv"
echo "Dizin yetkileri:"
ls -la /srv
echo "Nginx durum kontrolü:"
systemctl status nginx --no-pager
