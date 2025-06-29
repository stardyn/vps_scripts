#!/bin/bash

# Simple ThingsBoard License Client Extractor
# Sadece client lib'i bulup decompile eder

set -e

echo "🔍 Simple ThingsBoard License Client Extractor"
echo "=============================================="

# Configuration
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
WORK_DIR="/tmp/tb-license-extract"
OUTPUT_DIR="/tmp/tb-client-source"
CFR_JAR="/tmp/cfr.jar"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Check ThingsBoard JAR
if [ ! -f "$THINGSBOARD_JAR" ]; then
    echo_error "ThingsBoard JAR not found: $THINGSBOARD_JAR"
    
    # Try alternative locations
    for alt_path in "/opt/thingsboard/bin/thingsboard.jar" "/var/lib/thingsboard/thingsboard.jar"; do
        if [ -f "$alt_path" ]; then
            THINGSBOARD_JAR="$alt_path"
            echo_info "Found at alternative location: $alt_path"
            break
        fi
    done
    
    if [ ! -f "$THINGSBOARD_JAR" ]; then
        echo_error "No ThingsBoard JAR found. Please check installation."
        exit 1
    fi
fi

echo_info "ThingsBoard JAR: $THINGSBOARD_JAR"

# Setup directories
rm -rf "$WORK_DIR" "$OUTPUT_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Download CFR if needed
if [ ! -f "$CFR_JAR" ]; then
    echo_info "Downloading CFR decompiler..."
    wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/download/0.152/cfr-0.152.jar" || {
        echo_error "Failed to download CFR decompiler"
        exit 1
    }
fi

echo_info "Extracting ThingsBoard JAR..."
cd "$WORK_DIR"
jar -xf "$THINGSBOARD_JAR" >/dev/null 2>&1

# Find license client JAR - specifically client-1.3.0.jar in BOOT-INF/lib
echo_info "Searching for client-1.3.0.jar in BOOT-INF/lib..."
CLIENT_JAR=$(find . -path "*/BOOT-INF/lib/client-1.3.0.jar" | head -1)

if [ -z "$CLIENT_JAR" ]; then
    echo_info "client-1.3.0.jar not found in expected location, searching everywhere..."
    CLIENT_JAR=$(find . -name "client-1.3.0.jar" | head -1)
fi

if [ -z "$CLIENT_JAR" ]; then
    echo_info "client-1.3.0.jar not found, listing JARs in BOOT-INF/lib for manual selection..."
    echo_info "Available JARs in BOOT-INF/lib/:"
    find . -path "*/BOOT-INF/lib/*.jar" | grep -E "(client|license)" | head -10
    
    # Manual fallback - look for any client JAR that might contain license code
    for potential_jar in $(find . -path "*/BOOT-INF/lib/*client*.jar"); do
        jar_name=$(basename "$potential_jar")
        echo_info "Checking potential license client: $jar_name"
        
        # Quick check for license-related classes
        if jar -tf "$potential_jar" 2>/dev/null | grep -q -E "(License|Signature|TbClient|CheckInstance)"; then
            echo_info "✅ Found license classes in: $jar_name"
            CLIENT_JAR="$potential_jar"
            break
        fi
    done
fi

if [ -z "$CLIENT_JAR" ]; then
    echo_error "client-1.3.0.jar not found!"
    echo_info "Please check the exact filename. Available client JARs:"
    find . -path "*/BOOT-INF/lib/*" -name "*client*" | head -5
    exit 1
fi

echo_info "Found license client JAR: $CLIENT_JAR"

# Show contents of client JAR to verify it's the right one
echo_info "Verifying JAR contents..."
echo_info "Classes in JAR:"
jar -tf "$CLIENT_JAR" | grep "\.class$" | head -10

echo_info "Looking for specific license classes:"
jar -tf "$CLIENT_JAR" | grep -i -E "(TbLicenseClient|AbstractTbLicenseClient|SignatureUtil|LicenseValidator|CheckInstance)" || echo "No obvious license classes found"

# Extract client JAR
CLIENT_DIR="$WORK_DIR/client_extracted"
mkdir -p "$CLIENT_DIR"
cd "$CLIENT_DIR"

echo_info "Extracting client JAR..."
jar -xf "../$CLIENT_JAR" >/dev/null 2>&1

# Find license-related classes
echo_info "Finding license classes..."
LICENSE_CLASSES=$(find . -name "*.class" | grep -i -E "(license|signature|tbclient)" | head -10)

if [ -z "$LICENSE_CLASSES" ]; then
    echo_warn "No license classes found with standard naming"
    echo_info "Searching all classes for license content..."
    LICENSE_CLASSES=$(find . -name "*.class" | head -20)
fi

echo_info "Found classes:"
echo "$LICENSE_CLASSES" | while read class; do
    echo "   - $class"
done

# Decompile classes
echo_info "Decompiling classes with CFR..."
cd "$OUTPUT_DIR"

echo "$LICENSE_CLASSES" | while read class_file; do
    if [ -f "$CLIENT_DIR/$class_file" ]; then
        class_name=$(basename "$class_file" .class)
        echo_info "Decompiling: $class_name"
        
        java -jar "$CFR_JAR" "$CLIENT_DIR/$class_file" --outputdir . --silent 2>/dev/null || {
            echo_warn "Failed to decompile: $class_name"
        }
    fi
done

# Show results
echo_info "Decompilation complete!"
echo_info "Output directory: $OUTPUT_DIR"

JAVA_FILES=$(find "$OUTPUT_DIR" -name "*.java" 2>/dev/null)
if [ -n "$JAVA_FILES" ]; then
    echo_info "Decompiled Java files:"
    echo "$JAVA_FILES" | while read java_file; do
        lines=$(wc -l < "$java_file" 2>/dev/null || echo "0")
        echo "   - $(basename "$java_file") ($lines lines)"
    done
    
    echo ""
    echo_info "Quick preview of key files:"
    
    # Show key classes
    for pattern in "TbLicenseClient" "LicenseClient" "SignatureUtil" "License"; do
        key_file=$(find "$OUTPUT_DIR" -name "*$pattern*.java" | head -1)
        if [ -n "$key_file" ]; then
            echo ""
            echo "🔍 Preview: $(basename "$key_file")"
            echo "─────────────────────────────────────"
            head -30 "$key_file" | cat -n
            echo "─────────────────────────────────────"
        fi
    done
else
    echo_warn "No Java files generated. Check decompilation process."
fi

echo ""
echo_info "Commands to explore:"
echo "   # View all decompiled files"
echo "   find $OUTPUT_DIR -name '*.java' -exec ls -la {} \;"
echo ""
echo "   # Search for specific methods"
echo "   grep -r 'persistInstanceData\|checkInstance\|signature' $OUTPUT_DIR/"
echo ""
echo "   # View complete files"
echo "   find $OUTPUT_DIR -name '*.java' -exec cat {} \;"

echo ""
echo_info "✅ License client extraction complete!"
