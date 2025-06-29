#!/bin/bash

# Direct client-1.3.0.jar Extractor
# Direkt olarak client-1.3.0.jar dosyasını target alır

set -e

echo "🎯 Direct Client-1.3.0.jar Extractor"
echo "===================================="

# Paths
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
EXTRACT_DIR="/tmp/tb-extract"
CLIENT_JAR_PATH="$EXTRACT_DIR/BOOT-INF/lib/client-1.3.0.jar"
OUTPUT_DIR="/tmp/client-source"
CFR_JAR="/tmp/cfr.jar"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }
echo_highlight() { echo -e "${CYAN}🔍 $1${NC}"; }

# Check ThingsBoard JAR
if [ ! -f "$THINGSBOARD_JAR" ]; then
    echo_error "ThingsBoard JAR not found: $THINGSBOARD_JAR"
    exit 1
fi

# Download CFR if needed
if [ ! -f "$CFR_JAR" ]; then
    echo_info "Downloading CFR decompiler..."
    wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/download/0.152/cfr-0.152.jar"
fi

# Clean and setup
rm -rf "$EXTRACT_DIR" "$OUTPUT_DIR" 2>/dev/null || true
mkdir -p "$EXTRACT_DIR" "$OUTPUT_DIR"

echo_info "Extracting ThingsBoard JAR..."
cd "$EXTRACT_DIR"
jar -xf "$THINGSBOARD_JAR" >/dev/null 2>&1

# Check if client-1.3.0.jar exists
if [ ! -f "$CLIENT_JAR_PATH" ]; then
    echo_error "client-1.3.0.jar not found at expected location!"
    echo_info "Searching for similar files..."
    
    # List all client JARs
    echo_info "Available client JARs in BOOT-INF/lib/:"
    find "$EXTRACT_DIR/BOOT-INF/lib" -name "*client*" 2>/dev/null | while read jar; do
        size=$(du -h "$jar" | cut -f1)
        echo "   - $(basename "$jar") ($size)"
    done
    
    # Try to find any license-related JAR
    echo_info "Searching for license-related JARs..."
    find "$EXTRACT_DIR" -name "*.jar" | while read jar; do
        if jar -tf "$jar" 2>/dev/null | grep -q -i "TbLicenseClient\|LicenseClient\|SignatureUtil"; then
            echo_highlight "Found license classes in: $(basename "$jar")"
            echo "   Path: $jar"
        fi
    done
    
    exit 1
fi

echo_info "Found client-1.3.0.jar: $CLIENT_JAR_PATH"

# Show JAR info
jar_size=$(du -h "$CLIENT_JAR_PATH" | cut -f1)
echo_info "JAR size: $jar_size"

# Show JAR contents preview
echo_info "JAR contents preview:"
jar -tf "$CLIENT_JAR_PATH" | head -15

# Extract client JAR
CLIENT_EXTRACT_DIR="$EXTRACT_DIR/client_extracted"
mkdir -p "$CLIENT_EXTRACT_DIR"
cd "$CLIENT_EXTRACT_DIR"

echo_info "Extracting client-1.3.0.jar..."
jar -xf "$CLIENT_JAR_PATH" >/dev/null 2>&1

# Find all classes in the JAR
echo_info "Finding all classes in client-1.3.0.jar..."
ALL_CLASSES=$(find . -name "*.class" 2>/dev/null)
TOTAL_CLASSES=$(echo "$ALL_CLASSES" | wc -l)

echo_info "Total classes found: $TOTAL_CLASSES"

# Show first few classes
echo_info "Sample classes:"
echo "$ALL_CLASSES" | head -10 | while read class; do
    echo "   - $class"
done

# Look for license-specific classes
echo_info "Searching for license-related classes..."
LICENSE_CLASSES=$(echo "$ALL_CLASSES" | grep -i -E "(license|signature|tbclient|checker|validator)" || true)

if [ -n "$LICENSE_CLASSES" ]; then
    echo_highlight "License-related classes found:"
    echo "$LICENSE_CLASSES" | while read class; do
        echo "   - $class"
    done
else
    echo_warn "No obvious license classes found by name"
    echo_info "Will decompile all classes to search for license logic..."
    LICENSE_CLASSES="$ALL_CLASSES"
fi

# Decompile classes
cd "$OUTPUT_DIR"
echo_info "Decompiling classes..."

# Limit to first 20 classes to avoid overwhelming output
CLASSES_TO_DECOMPILE=$(echo "$LICENSE_CLASSES" | head -20)
DECOMPILED_COUNT=0

echo "$CLASSES_TO_DECOMPILE" | while read class_file; do
    if [ -f "$CLIENT_EXTRACT_DIR/$class_file" ]; then
        class_name=$(basename "$class_file" .class)
        
        if java -jar "$CFR_JAR" "$CLIENT_EXTRACT_DIR/$class_file" --outputdir . --silent 2>/dev/null; then
            ((DECOMPILED_COUNT++))
            echo_info "✅ Decompiled: $class_name"
        else
            echo_warn "❌ Failed: $class_name"
        fi
    fi
done

# Show results
echo_info "Decompilation complete!"

JAVA_FILES=$(find "$OUTPUT_DIR" -name "*.java" 2>/dev/null)
if [ -n "$JAVA_FILES" ]; then
    echo_highlight "Decompiled files:"
    echo "$JAVA_FILES" | while read java_file; do
        lines=$(wc -l < "$java_file" 2>/dev/null || echo "0")
        echo "   - $(basename "$java_file") ($lines lines)"
    done
    
    echo ""
    echo_highlight "Quick search for license-related code:"
    
    # Search for license validation methods
    grep -r -l -i "license\|signature\|valid\|check" "$OUTPUT_DIR/" 2>/dev/null | head -5 | while read file; do
        echo_highlight "Found license code in: $(basename "$file")"
        echo "Preview:"
        grep -n -i -A 2 -B 2 "license\|signature\|valid" "$file" | head -10
        echo "---"
    done
    
else
    echo_warn "No Java files generated!"
fi

echo ""
echo_info "📁 Output directory: $OUTPUT_DIR"
echo_info "📝 All class files: find $CLIENT_EXTRACT_DIR -name '*.class'"
echo_info "📄 All Java files: find $OUTPUT_DIR -name '*.java'"

echo ""
echo_info "🔍 Manual investigation commands:"
echo "   # Search all decompiled code for license"
echo "   grep -r -i 'license\\|signature\\|valid\\|check' $OUTPUT_DIR/"
echo ""
echo "   # View all Java files"
echo "   find $OUTPUT_DIR -name '*.java' -exec cat {} \\;"
echo ""
echo "   # List class structure"
echo "   find $CLIENT_EXTRACT_DIR -name '*.class' | sort"

echo ""
echo_info "✅ client-1.3.0.jar extraction complete!"
