#!/bin/bash

# ThingsBoard License JAR Decompiler - Sadece client ve shared JAR'ları
# client-1.3.0.jar ve shared-1.3.0.jar için

set -e

echo "🎯 ThingsBoard License JAR Decompiler"
echo "====================================="

WORK_DIR="/tmp/tb-license-only"
CFR_JAR="/tmp/cfr-0.152.jar"

# Setup
rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR"

# CFR indir
if [ ! -f "$CFR_JAR" ]; then
    echo "📥 CFR indiriliyor..."
    wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/download/0.152/cfr-0.152.jar"
fi

# ThingsBoard JAR bul
TB_JAR=""
LOCATIONS=(
    "/usr/share/thingsboard/bin/thingsboard.jar"
    "/opt/thingsboard/bin/thingsboard.jar"
    "/var/lib/thingsboard/thingsboard.jar"
    "./thingsboard.jar"
)

for location in "${LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        TB_JAR="$location"
        echo "✅ ThingsBoard JAR: $location"
        break
    fi
done

if [ -z "$TB_JAR" ]; then
    echo "❌ ThingsBoard JAR bulunamadı"
    exit 1
fi

cd "$WORK_DIR"

# Main JAR extract et
echo "📦 Main JAR extract ediliyor..."
jar -xf "$TB_JAR" >/dev/null 2>&1

# Sadece client ve shared JAR'larını bul
echo "🔍 License JAR'ları aranıyor..."

CLIENT_JAR=""
SHARED_JAR=""

# client-1.3.0.jar ara
CLIENT_JAR=$(find . -name "*client*1.3.0*.jar" | head -1)
if [ -z "$CLIENT_JAR" ]; then
    CLIENT_JAR=$(find . -name "*client*.jar" | grep -i license | head -1)
fi

# shared-1.3.0.jar ara  
SHARED_JAR=$(find . -name "*shared*1.3.0*.jar" | head -1)
if [ -z "$SHARED_JAR" ]; then
    SHARED_JAR=$(find . -name "*shared*.jar" | grep -i license | head -1)
fi

echo "📋 Bulunan JAR'lar:"
if [ -n "$CLIENT_JAR" ]; then
    echo "   ✅ CLIENT: $(basename $CLIENT_JAR)"
else
    echo "   ❌ CLIENT JAR bulunamadı"
fi

if [ -n "$SHARED_JAR" ]; then
    echo "   ✅ SHARED: $(basename $SHARED_JAR)"
else
    echo "   ❌ SHARED JAR bulunamadı"
fi

# CLIENT JAR decompile et
if [ -n "$CLIENT_JAR" ]; then
    echo ""
    echo "🎯 CLIENT JAR DECOMPILE EDİLİYOR"
    echo "==============================="
    
    mkdir -p "client_decompiled"
    java -jar "$CFR_JAR" "$CLIENT_JAR" --outputdir "client_decompiled" 2>/dev/null || echo "Decompile hatası"
    
    echo "📄 Client JAR içeriği:"
    find client_decompiled -name "*.java" | head -20
    
    echo ""
    echo "📋 TüM CLIENT SOURCE KODLARI:"
    echo "============================="
    find client_decompiled -name "*.java" | while read java_file; do
        echo ""
        echo "📄 === $(basename $java_file) ==="
        echo "Dosya: $java_file"
        echo "════════════════════════════════════════"
        cat "$java_file"
        echo "════════════════════════════════════════"
    done
fi

# SHARED JAR decompile et
if [ -n "$SHARED_JAR" ]; then
    echo ""
    echo "🎯 SHARED JAR DECOMPILE EDİLİYOR"
    echo "==============================="
    
    mkdir -p "shared_decompiled"
    java -jar "$CFR_JAR" "$SHARED_JAR" --outputdir "shared_decompiled" 2>/dev/null || echo "Decompile hatası"
    
    echo "📄 Shared JAR içeriği:"
    find shared_decompiled -name "*.java" | head -20
    
    echo ""
    echo "📋 TÜM SHARED SOURCE KODLARI:"
    echo "============================="
    find shared_decompiled -name "*.java" | while read java_file; do
        echo ""
        echo "📄 === $(basename $java_file) ==="
        echo "Dosya: $java_file"
        echo "════════════════════════════════════════"
        cat "$java_file"
        echo "════════════════════════════════════════"
    done
fi

echo ""
echo "✅ DECOMPILE TAMAMLANDI!"
echo "======================="
echo "📁 Çalışma dizini: $WORK_DIR"

if [ -n "$CLIENT_JAR" ]; then
    echo "📁 Client kaynak kodları: $WORK_DIR/client_decompiled/"
fi

if [ -n "$SHARED_JAR" ]; then
    echo "📁 Shared kaynak kodları: $WORK_DIR/shared_decompiled/"
fi
