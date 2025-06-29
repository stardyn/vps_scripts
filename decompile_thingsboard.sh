#!/bin/bash

# ThingsBoard SignatureUtil Finder - Minimal Version
# Sadece org.thingsboard.license.shared.signature.SignatureUtil'i bulur

set -e

echo "🎯 ThingsBoard SignatureUtil Finder"
echo "==================================="

# ThingsBoard JAR lokasyonları
THINGSBOARD_JARS=(
    "/usr/share/thingsboard/bin/thingsboard.jar"
    "/opt/thingsboard/bin/thingsboard.jar"
    "/var/lib/thingsboard/thingsboard.jar"
    "./thingsboard.jar"
)

WORK_DIR="/tmp/tb-license-finder"
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
for jar in "${THINGSBOARD_JARS[@]}"; do
    if [ -f "$jar" ]; then
        TB_JAR="$jar"
        echo "✅ ThingsBoard JAR: $jar"
        break
    fi
done

if [ -z "$TB_JAR" ]; then
    echo "❌ ThingsBoard JAR bulunamadı"
    exit 1
fi

cd "$WORK_DIR"
echo "📦 JAR extract ediliyor..."
jar -xf "$TB_JAR" >/dev/null 2>&1

# Hedef sınıfları
TARGETS=(
    "org/thingsboard/license/shared/signature/SignatureUtil.class"
    "org/thingsboard/license/client/TbLicenseClient.class"
    "org/thingsboard/license/client/AbstractTbLicenseClient.class"
)

echo "🔍 Hedef sınıflar aranıyor..."

# JAR'ları tara
find . -name "*.jar" -type f | while read jar_file; do
    jar_name=$(basename "$jar_file")
    
    # JAR içindeki sınıfları kontrol et
    for target in "${TARGETS[@]}"; do
        if jar -tf "$jar_file" 2>/dev/null | grep -q "$target"; then
            class_name=$(basename "$target" .class)
            echo "🎯 BULUNDU: $class_name -> $jar_name"
            
            # JAR'ı extract et
            extract_dir="extracted_$(basename "$jar_file" .jar)"
            mkdir -p "$extract_dir"
            cd "$extract_dir"
            jar -xf "../$jar_file" >/dev/null 2>&1
            
            # Sınıfı decompile et
            if [ -f "$target" ]; then
                echo "📝 Decompile ediliyor: $class_name"
                java -jar "$CFR_JAR" "$target" --outputdir "../output" --silent true 2>/dev/null
                
                output_file="../output/$(echo $target | sed 's|/|.|g' | sed 's|.class|.java|')"
                if [ -f "$output_file" ]; then
                    echo "✅ Decompile başarılı: $output_file"
                    echo ""
                    echo "📄 $class_name Source Code:"
                    echo "=========================="
                    cat "$output_file"
                    echo ""
                    echo "=========================="
                fi
            fi
            cd ..
        fi
    done
done

# Direct sınıfları da kontrol et
echo "🔍 Direct sınıflar aranıyor..."
for target in "${TARGETS[@]}"; do
    if [ -f "$target" ]; then
        class_name=$(basename "$target" .class)
        echo "🎯 DIRECT BULUNDU: $class_name"
        
        mkdir -p "output"
        java -jar "$CFR_JAR" "$target" --outputdir "output" --silent true 2>/dev/null
        
        output_file="output/$(echo $target | sed 's|/|.|g' | sed 's|.class|.java|')"
        if [ -f "$output_file" ]; then
            echo "✅ Decompile başarılı: $output_file"
            echo ""
            echo "📄 $class_name Source Code:"
            echo "=========================="
            cat "$output_file"
            echo ""
            echo "=========================="
        fi
    fi
done

echo "🔍 Tüm license sınıfları listeleniyor..."
find . -name "*.class" | grep -i license | head -10

echo ""
echo "✅ Tarama tamamlandı!"
echo "📁 Çalışma dizini: $WORK_DIR"
