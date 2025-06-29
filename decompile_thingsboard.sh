#!/bin/bash

# Sadece client-1.3.0.jar ve shared-1.3.0.jar decompile eder

set -e

echo "🎯 ThingsBoard License JAR Decompiler - SADECE 2 JAR"
echo "=================================================="

WORK_DIR="/tmp/tb-license-minimal"
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

# SADECE client ve shared JAR'larını bul
echo "🔍 SADECE license JAR'ları aranıyor..."

# Spesifik dosya isimleri
CLIENT_JAR=""
SHARED_JAR=""

# client-1.3.0.jar exact match
CLIENT_JAR=$(find . -name "client-1.3.0.jar" | head -1)
# shared-1.3.0.jar exact match  
SHARED_JAR=$(find . -name "shared-1.3.0.jar" | head -1)

echo "📋 Aranan JAR'lar:"
echo "   🔍 client-1.3.0.jar veya license-client-*.jar"
echo "   🔍 shared-1.3.0.jar veya license-shared-*.jar"
echo ""

if [ -n "$CLIENT_JAR" ]; then
    echo "   ✅ CLIENT BULUNDU: $(basename $CLIENT_JAR)"
else
    echo "   ❌ CLIENT JAR bulunamadı"
    echo "   📋 Mevcut client JAR'ları:"
    find . -name "*client*.jar" | grep -v google | grep -v http | head -5
fi

if [ -n "$SHARED_JAR" ]; then
    echo "   ✅ SHARED BULUNDU: $(basename $SHARED_JAR)"
else
    echo "   ❌ SHARED JAR bulunamadı"
    echo "   📋 Mevcut shared JAR'ları:"
    find . -name "*shared*.jar" | grep -v google | grep -v http | head -5
fi

# Sadece bulunan JAR'ları decompile et
if [ -n "$CLIENT_JAR" ]; then
    echo ""
    echo "🎯 CLIENT JAR DECOMPILE: $(basename $CLIENT_JAR)"
    echo "=============================================="
    
    mkdir -p "client_src"
    java -jar "$CFR_JAR" "$CLIENT_JAR" --outputdir "client_src" 2>/dev/null || {
        echo "❌ Client JAR decompile hatası"
    }
    
    # Sadece Java dosyalarını göster
    if [ -d "client_src" ]; then
        echo "📄 CLIENT SOURCE KODLARI:"
        find client_src -name "*.java" | while read java_file; do
            echo ""
            echo "📄 === $(basename $java_file) ==="
            echo "Dosya: $java_file"
            echo "════════════════════════════════════════"
            cat "$java_file"
            echo "════════════════════════════════════════"
        done
    fi
fi

if [ -n "$SHARED_JAR" ]; then
    echo ""
    echo "🎯 SHARED JAR DECOMPILE: $(basename $SHARED_JAR)"
    echo "=============================================="
    
    mkdir -p "shared_src"
    java -jar "$CFR_JAR" "$SHARED_JAR" --outputdir "shared_src" 2>/dev/null || {
        echo "❌ Shared JAR decompile hatası"
    }
    
    # Sadece Java dosyalarını göster
    if [ -d "shared_src" ]; then
        echo "📄 SHARED SOURCE KODLARI:"
        find shared_src -name "*.java" | while read java_file; do
            echo ""
            echo "📄 === $(basename $java_file) ==="
            echo "Dosya: $java_file"
            echo "════════════════════════════════════════"
            cat "$java_file"
            echo "════════════════════════════════════════"
        done
    fi
fi

# Hiçbiri bulunamadıysa tüm JAR'ları listele
if [ -z "$CLIENT_JAR" ] && [ -z "$SHARED_JAR" ]; then
    echo ""
    echo "❌ HEDEF JAR'LAR BULUNAMADI"
    echo "=========================="
    echo "📋 Tüm JAR dosyaları:"
    find . -name "*.jar" | head -20 | while read jar; do
        echo "   $(basename $jar)"
    done
fi

echo ""
echo "✅ İşlem tamamlandı!"
echo "📁 Çalışma dizini: $WORK_DIR"
