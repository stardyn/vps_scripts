#!/bin/bash
#apt-get update && apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/ubuntu_setup_ftp.sh && dos2unix ubuntu_setup_ftp.sh && chmod +x ubuntu_setup_ftp.sh && ./ubuntu_setup_ftp.sh

# Root yetkisi kontrolü ve yükseltme
if [ "$EUID" -ne 0 ]; then
    echo "Root yetkisi gerekiyor... Yetki yükseltme deneniyor..."
    exec sudo "$0" "$@"
    exit $?
fi

# Hata durumunda scripti durdur
set -e

# Fonksiyonları tanımla
install_packages() {
    echo "Sistem güncelleniyor ve temel paketler kuruluyor..."   
    echo "APT güncelleniyor..."
    apt-get update
    
    echo "Tam sistem güncellemesi yapılıyor..."
    #DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    
    echo "Temel paketler kuruluyor..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        wget \
        nano \
        htop \
        net-tools \
        mc \
        software-properties-common \
        ca-certificates \
        gnupg \
        dos2unix \
        apt-transport-https
        
    #FTP kurulumu
    install_ftp_web
    
    # Gereksiz paketleri temizle
    echo "Gereksiz paketler temizleniyor..."
    apt-get autoremove -y
    apt-get clean
    
	useradd -r dotnet
	groupadd dotnet # grup yoksa

	# UFW kontrolü ve devre dışı bırakma
	if command -v ufw >/dev/null 2>&1; then
		echo "UFW tespit edildi, devre dışı bırakılıyor..."
		systemctl disable ufw
		systemctl stop ufw
		apt-get remove -y ufw
	fi
}

install_ftp_web() {
    echo "FTP kurulumu yapılıyor..."
    # VSFTPD kurulumu
    echo "VSFTPD kuruluyor..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y vsftpd
    
    # VSFTPD yapılandırması
    echo "VSFTPD yapılandırılıyor..."
    sed -i "s/^#\?listen_ipv6=.*/listen_ipv6=YES/" /etc/vsftpd.conf
    sed -i "s/^#\?anonymous_enable=.*/anonymous_enable=NO/" /etc/vsftpd.conf
    sed -i "s/^#\?local_enable=.*/local_enable=YES/" /etc/vsftpd.conf
    sed -i "s/^#\?write_enable=.*/write_enable=YES/" /etc/vsftpd.conf
    sed -i "s/^#\?local_umask=.*/local_umask=022/" /etc/vsftpd.conf
    sed -i "s/^#\?chroot_local_user=.*/chroot_local_user=YES/" /etc/vsftpd.conf
    
    # Pasif mod ayarları
    grep -q "^pasv_enable=" /etc/vsftpd.conf || echo "pasv_enable=YES" >> /etc/vsftpd.conf
    grep -q "^pasv_min_port=" /etc/vsftpd.conf || echo "pasv_min_port=30000" >> /etc/vsftpd.conf
    grep -q "^pasv_max_port=" /etc/vsftpd.conf || echo "pasv_max_port=30400" >> /etc/vsftpd.conf
    
    # Root dizini ve güvenlik ayarları
    grep -q "^local_root=" /etc/vsftpd.conf || echo "local_root=/srv/sites" >> /etc/vsftpd.conf
    grep -q "^user_sub_token=" /etc/vsftpd.conf || echo "user_sub_token=\$USER" >> /etc/vsftpd.conf
    grep -q "^allow_writeable_chroot=" /etc/vsftpd.conf || echo "allow_writeable_chroot=YES" >> /etc/vsftpd.conf
    
    # /etc/shells düzenleme
    echo "Shells yapılandırılıyor..."
    grep -q "^/usr/sbin/nologin$" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells
    
    # FTP kullanıcı grubu ve yönetici oluşturma
    echo "FTP kullanıcıları ayarlanıyor..."
    groupadd ftp-users 2>/dev/null || true
    
    # Ana dizin yapısını oluştur
    mkdir -p /srv/sites
    
    # Önce root sahipliğinde oluştur
    chown root:root /srv/sites
    chmod 755 /srv/sites
    
    # Alt dizini kullanıcı için oluştur
    mkdir -p /srv/sites/web
    
    useradd yonetici --home-dir /srv/sites --gid ftp-users --create-home --no-user-group --shell /usr/sbin/nologin
    echo "yonetici:202300" | chpasswd
    
    # Sadece alt dizine yazma izni ver
    chown -R yonetici:ftp-users /srv/sites/web
    chmod 755 /srv/sites/web    
	
    # VSFTPD yeniden başlat
    systemctl restart vsftpd
	chown yonetici -R /srv 
    
    echo "FTP kurulumu tamamlandı."
    echo "FTP yönetici kullanıcı adı: yonetici"
    echo "FTP yönetici şifresi: 202300"
    echo "FTP dizini: /srv/sites"
}

# Ana fonksiyon
main() {
    # Paketleri kur
    install_packages
    
    echo "Tüm kurulum işlemleri tamamlandı!"
}

# Scripti çalıştır
main "$@"
