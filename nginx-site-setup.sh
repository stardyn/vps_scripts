#!/bin/bash

# Root kullanıcısı kontrolü
if [ "$EUID" -ne 0 ]; then 
    echo "Bu script root kullanıcısı olarak çalıştırılmalıdır."
    exit 1
fi

# Fonksiyon: Index.html oluştur
create_index() {
    local domain_name=$1
    local index_file="/srv/sites/$domain_name/www/index.html"
    
    cat > $index_file << EOF
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$domain_name</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background-color: #f0f2f5;
        }
        .container {
            text-align: center;
            padding: 40px;
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #1a73e8;
            margin-bottom: 20px;
        }
        p {
            color: #5f6368;
            line-height: 1.6;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Hoş Geldiniz</h1>
        <p>$domain_name sitesi kurulumu başarıyla tamamlandı.</p>
        <p>Bu sayfa otomatik olarak oluşturulmuştur.</p>
    </div>
</body>
</html>
EOF

    echo "Index.html dosyası oluşturuldu: $index_file"
    # Dosya izinlerini ayarla
    #chown -R www-data:www-data "/srv/sites/$domain_name"
    #chmod -R 755 "/srv/sites/$domain_name"
}

# Fonksiyon: Domain Ekle
add_domain() {
    local domain_name=$1
    
    # Dizinleri oluştur
    echo "Dizinler oluşturuluyor..."
    mkdir -p /srv/sites/$domain_name/www

    # Index.html dosyasını oluştur
    create_index $domain_name

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
    ln -s /srv/sites/$domain_name/www/site_nginx.conf /etc/nginx/sites-available/$domain_name
    ln -s /srv/sites/$domain_name/www/site_nginx.conf /etc/nginx/sites-enabled/$domain_name

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
    
    # Domain dizinini silme seçeneği devre dışı
    # if [ -d "/srv/sites/$domain_name" ]; then
    #     rm -rf "/srv/sites/$domain_name"
    #     echo "Domain dizini silindi: /srv/sites/$domain_name"
    # fi
    
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
