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

# Web dizini oluştur
echo "Web dizini oluşturuluyor..."
mkdir -p /srv
chown www-data:web-ftp-users /srv
chmod 775 /srv

# FTP kullanıcısını düzenle
if id "yonetici" &>/dev/null; then
    # FTP kullanıcısını güncelle
    usermod -d /srv yonetici
    usermod -a -G web-ftp-users yonetici
    # FTP kullanıcısına shell ver (gerekli olabilir)
    usermod -s /bin/bash yonetici
fi

# Tüm dosyaların sahipliğini değiştir
chown -R yonetici:web-ftp-users /srv
chmod -R 775 /srv
chmod g+s /srv

# ACL kuralları ekle
apt-get install -y acl
setfacl -R -m u:www-data:rwx /srv
setfacl -R -m u:yonetici:rwx /srv
setfacl -R -m g:web-ftp-users:rwx /srv
setfacl -R -d -m u:www-data:rwx /srv
setfacl -R -d -m u:yonetici:rwx /srv
setfacl -R -d -m g:web-ftp-users:rwx /srv

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
chown yonetici:web-ftp-users /srv/index.html
chmod 664 /srv/index.html

[Önceki Nginx yapılandırmaları aynı kalacak...]

# Kullanıcı bilgilerini güncelle
echo "yonetici:202300" | chpasswd

# Test dosyası oluştur ve yetkileri kontrol et
echo "Test dosyası" > /srv/test.txt
chown yonetici:web-ftp-users /srv/test.txt
chmod 664 /srv/test.txt

# Yetki durumunu göster
echo "Dizin yetkileri ve sahiplik kontrolü:"
ls -la /srv
echo "ACL yetkileri:"
getfacl /srv
echo "Kullanıcı grupları:"
groups yonetici
groups www-data

# Nginx'i yeniden başlat
systemctl restart nginx
