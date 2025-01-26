#!/bin/bash

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

# Firewall kuralları (eğer UFW yüklüyse)
if command -v ufw >/dev/null 2>&1; then
    echo "Firewall kuralları ekleniyor..."
    ufw allow 'Nginx Full'
    ufw allow 80/tcp
    ufw allow 443/tcp
fi

# Web ve FTP için ortak grup oluştur
echo "Ortak grup oluşturuluyor..."
groupadd -f web-ftp-users

# www-data kullanıcısını gruba ekle
usermod -a -G web-ftp-users www-data

# FTP kullanıcısını gruba ekle (eğer varsa)
if id "yonetici" &>/dev/null; then
    usermod -a -G web-ftp-users yonetici
fi

# Web dizini oluştur ve yetkilendir
echo "Web dizini oluşturuluyor..."
mkdir -p /srv
chown www-data:web-ftp-users /srv
chmod 775 /srv
chmod g+s /srv  # Yeni oluşturulan dosyalar grup sahipliğini devralır

# ACL kuralları ekle (eğer ACL destekleniyorsa)
if command -v setfacl >/dev/null 2>&1; then
    apt-get install -y acl
    setfacl -R -m g:web-ftp-users:rwx /srv
    setfacl -R -d -m g:web-ftp-users:rwx /srv
fi

# Örnek index.html oluştur
cat > /srv/index.html << 'EOL'
<!DOCTYPE html>
<html>
<head>
    <title>Web Sunucusu Hazır!</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px auto;
            max-width: 650px;
            line-height: 1.6;
            padding: 0 10px;
        }
        h1 {
            color: #333;
            text-align: center;
        }
    </style>
</head>
<body>
    <h1>Nginx Sunucusu Başarıyla Kuruldu!</h1>
    <p>Bu sayfa, Nginx web sunucusunun başarıyla kurulduğunu ve çalıştığını gösterir.</p>
</body>
</html>
EOL

# Örnek dosya yetkilerini ayarla
chown www-data:web-ftp-users /srv/index.html
chmod 664 /srv/index.html

# Nginx varsayılan site yapılandırması
cat > /etc/nginx/sites-available/default << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /srv;
    index index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOL

# Nginx yapılandırması yedekle ve güncelle
echo "Nginx yapılandırması güncelleniyor..."
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Nginx optimizasyonları
cat > /etc/nginx/nginx.conf << 'EOL'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOL

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
echo "Grup üyelikleri:"
groups www-data
if id "yonetici" &>/dev/null; then
    groups yonetici
fi
echo "Nginx durum kontrolü:"
systemctl status nginx --no-pager
