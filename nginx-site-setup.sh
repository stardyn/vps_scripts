#!/bin/bash

# Root kullanıcısı kontrolü
if [ "$EUID" -ne 0 ]; then 
    echo "Bu script root kullanıcısı olarak çalıştırılmalıdır."
    exit 1
fi

# Fonksiyon: Domain Ekle
add_domain() {
    local domain_name=$1
    
    # Dizinleri oluştur
    echo "Dizinler oluşturuluyor..."
    mkdir -p /srv/sites/$domain_name/www

    # Nginx konfigürasyon dosyasını oluştur
    config_file="/srv/sites/$domain_name/www/site_nginx.conf"
    echo "Nginx konfigürasyonu oluşturuluyor..."

    cat > $config_file << EOF
server {
    listen   80;
    server_name $domain_name;
    root  /srv/sites/$domain_name/www;
    index index.html index.htm;
}
EOF

    # Symbolic linkleri oluştur
    echo "Symbolic linkler oluşturuluyor..."
    ln -s $config_file /etc/nginx/sites-available/$domain_name
    ln -s $config_file /etc/nginx/sites-enabled/$domain_name

    # Nginx konfigürasyonunu test et
    echo "Nginx konfigürasyonu test ediliyor..."
    nginx -t

    if [ $? -eq 0 ]; then
        echo "Nginx konfigürasyonu başarılı!"
        
        # Nginx'i yeniden yükle
        echo "Nginx yeniden yükleniyor..."
        service nginx reload
        
        echo "Kurulum tamamlandı!"
        echo "Site dizini: /srv/sites/$domain_name/www"
        echo "Konfigürasyon dosyası: $config_file"
        echo "Domain: $domain_name"
    else
        echo "Nginx konfigürasyon testi başarısız oldu!"
        echo "Lütfen konfigürasyon dosyasını kontrol edin."
        exit 1
    fi
}

# Fonksiyon: Domain Sil
remove_domain() {
    local domain_name=$1
    
    echo "Domain siliniyor: $domain_name"
    
    # Symbolic linkleri sil
    if [ -L "/etc/nginx/sites-enabled/$domain_name" ]; then
        rm "/etc/nginx/sites-enabled/$domain_name"
    fi
    
    if [ -L "/etc/nginx/sites-available/$domain_name" ]; then
        rm "/etc/nginx/sites-available/$domain_name"
    fi
    
    # Domain dizinini sil
  #  if [ -d "/srv/sites/$domain_name" ]; then
  #      rm -rf "/srv/sites/$domain_name"
  #      echo "Domain dizini silindi: /srv/sites/$domain_name"
  #  fi
    
    # Nginx'i yeniden yükle
    echo "Nginx yeniden yükleniyor..."
    service nginx reload
    
    echo "Domain başarıyla silindi!"
}

# Ana menü
echo "Nginx Domain Yönetimi"
echo "1) Domain Ekle"
echo "2) Domain Sil"
echo "3) Çıkış"
read -p "Seçiminiz (1-3): " choice

case $choice in
    1)
        read -p "Domain adını giriniz (örnek: ludo.kesfet.co): " domain_name
        if [ -z "$domain_name" ]; then
            echo "Domain adı boş olamaz!"
            exit 1
        fi
        add_domain $domain_name
        ;;
    2)
        read -p "Silinecek domain adını giriniz: " domain_name
        if [ -z "$domain_name" ]; then
            echo "Domain adı boş olamaz!"
            exit 1
        fi
        remove_domain $domain_name
        ;;
    3)
        echo "Çıkış yapılıyor..."
        exit 0
        ;;
    *)
        echo "Geçersiz seçim!"
        exit 1
        ;;
esac