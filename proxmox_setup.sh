#!/bin/bash
#apt-get update && apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/proxmox_setup.sh && dos2unix proxmox_setup.sh && chmod +x proxmox_setup.sh && ./proxmox_setup.sh

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
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    
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
        apt-transport-https
        
    # Nginx ve FTP kurulumu
    install_ftp_web
    
    # Gereksiz paketleri temizle
    echo "Gereksiz paketler temizleniyor..."
    apt-get autoremove -y
    apt-get clean
    
    # UFW'yi devre dışı bırak ve kaldır
    echo "Firewall devre dışı bırakılıyor..."
    systemctl disable ufw
    systemctl stop ufw
    apt-get remove -y ufw
}

install_ftp_web() {
    echo "FTP kurulumu yapılıyor..."
    # VSFTPD kurulumu
    echo "VSFTPD kuruluyor..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y vsftpd
    
    # VSFTPD yapılandırması
	echo "VSFTPD yapılandırılıyor..."
	sed -i "s/^#\?listen=.*/listen=NO/" /etc/vsftpd.conf
	sed -i "s/^#\?listen_ipv6=.*/listen_ipv6=YES/" /etc/vsftpd.conf
	sed -i "s/^#\?anonymous_enable=.*/anonymous_enable=NO/" /etc/vsftpd.conf
	sed -i "s/^#\?local_enable=.*/local_enable=YES/" /etc/vsftpd.conf
	sed -i "s/^#\?write_enable=.*/write_enable=YES/" /etc/vsftpd.conf
	sed -i "s/^#\?local_umask=.*/local_umask=022/" /etc/vsftpd.conf
	sed -i "s/^#\?chroot_local_user=.*/chroot_local_user=YES/" /etc/vsftpd.conf
	sed -i "s/^#\?allow_writeable_chroot=.*/allow_writeable_chroot=YES/" /etc/vsftpd.conf
    
    # Pasif mod ayarları
    grep -q "^pasv_enable=" /etc/vsftpd.conf || echo "pasv_enable=YES" >> /etc/vsftpd.conf
    grep -q "^pasv_min_port=" /etc/vsftpd.conf || echo "pasv_min_port=30000" >> /etc/vsftpd.conf
    grep -q "^pasv_max_port=" /etc/vsftpd.conf || echo "pasv_max_port=30400" >> /etc/vsftpd.conf
    
    # /etc/shells düzenleme
    echo "Shells yapılandırılıyor..."
    grep -q "^/usr/sbin/nologin$" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells
    
    # FTP kullanıcı grubu ve yönetici oluşturma
    echo "FTP kullanıcıları ayarlanıyor..."
    groupadd -f ftp-users
    useradd -M yonetici -g ftp-users -s /usr/sbin/nologin -d /srv/ftp 2>/dev/null || true
    echo "yonetici:202300" | chpasswd
    
    # FTP dizini oluştur ve yetkilendir
    echo "FTP dizini oluşturuluyor ve yetkilendiriliyor..."
    chown -R yonetici:ftp-users /srv
    chmod -R 775 /srv
    
    # VSFTPD yeniden başlat
    systemctl restart vsftpd
    
    echo "FTP kurulumu tamamlandı."
    echo "FTP yönetici kullanıcı adı: yonetici"
    echo "FTP yönetici şifresi: 202300"
    echo "FTP dizini: /srv"
}

# Ana fonksiyon
main() {
    # Paketleri kur
    install_packages
    
    echo "Tüm kurulum işlemleri tamamlandı!"
}

# Scripti çalıştır
main "$@"
