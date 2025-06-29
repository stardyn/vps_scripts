#!/bin/bash

# ThingsBoard License Client Decompile Script
# Usage: ./decompile_thingsboard.sh

#apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/decompile_thingsboard.sh && dos2unix decompile_thingsboard.sh && chmod +x decompile_thingsboard.sh && ./decompile_thingsboard.sh

set -e  # Exit on any error

echo "🔍 ThingsBoard License Client Decompilation Script"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ANALYSIS_DIR="/tmp/license-client-analysis"
THINGSBOARD_JAR="/tmp/thingsboard-analysis/BOOT-INF/lib/client-1.3.0.jar"
CFR_JAR="/tmp/cfr-0.152.jar"
OUTPUT_DIR="/tmp/decompiled_output"

echo -e "${BLUE}📦 Step 1: Setup directories${NC}"
mkdir -p "$ANALYSIS_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$ANALYSIS_DIR"

echo -e "${BLUE}📦 Step 2: Extract ThingsBoard License JAR${NC}"
if [ ! -f "$THINGSBOARD_JAR" ]; then
    echo -e "${RED}❌ ThingsBoard JAR not found: $THINGSBOARD_JAR${NC}"
    echo "Please make sure ThingsBoard is extracted first"
    exit 1
fi

echo "Extracting: $THINGSBOARD_JAR"
jar -xf "$THINGSBOARD_JAR"

echo -e "${BLUE}📦 Step 3: Download CFR Decompiler${NC}"
if [ ! -f "$CFR_JAR" ]; then
    echo "Downloading CFR decompiler..."
    cd /tmp
    wget -q https://github.com/leibnitz27/cfr/releases/latest/download/cfr-0.152.jar
    echo -e "${GREEN}✅ CFR decompiler downloaded${NC}"
else
    echo -e "${GREEN}✅ CFR decompiler already exists${NC}"
fi

cd "$ANALYSIS_DIR"

echo -e "${BLUE}📦 Step 4: Find License Classes${NC}"
echo "License client classes found:"
find . -name "*TbLicense*" -type f | head -10

echo -e "\nSignature related classes:"
find . -name "*Signature*" -type f

echo -e "\nCheckInstance related classes:"
find . -name "*CheckInstance*" -type f

echo -e "${BLUE}📦 Step 5: List JAR Contents${NC}"
echo "Full JAR contents (org/thingsboard packages):"
jar -tf "$THINGSBOARD_JAR" | grep "org/thingsboard" | sort > "$OUTPUT_DIR/jar_contents.txt"
cat "$OUTPUT_DIR/jar_contents.txt" | head -20
echo "... (saved to $OUTPUT_DIR/jar_contents.txt)"

echo -e "${BLUE}📦 Step 6: Decompile Key Classes${NC}"

# Function to decompile a class
decompile_class() {
    local class_path="$1"
    local output_name="$2"
    
    if [ -f "$class_path" ]; then
        echo -e "${YELLOW}Decompiling: $class_path${NC}"
        java -jar "$CFR_JAR" "$class_path" > "$OUTPUT_DIR/${output_name}.java" 2>/dev/null
        echo -e "${GREEN}✅ Saved to: $OUTPUT_DIR/${output_name}.java${NC}"
        
        # Show first 30 lines
        echo "Preview (first 30 lines):"
        head -30 "$OUTPUT_DIR/${output_name}.java"
        echo "..."
        echo ""
    else
        echo -e "${RED}❌ Class not found: $class_path${NC}"
    fi
}

# Decompile main classes
decompile_class "$ANALYSIS_DIR/org/thingsboard/license/client/TbLicenseClient.class" "TbLicenseClient"

# Try to find and decompile other important classes
for class_file in $ANALYSIS_DIR/org/thingsboard/license/client/*.class; do
    if [ -f "$class_file" ]; then
        class_name=$(basename "$class_file" .class)
        case "$class_name" in
            *LicenseClient*|*AbstractTbLicense*|*TbLicenseCtx*)
                decompile_class "$class_file" "$class_name"
                ;;
        esac
    fi
done

echo -e "${BLUE}📦 Step 7: Search for Shared Classes in Other JARs${NC}"
echo "Searching for shared classes in other JARs..."
find /tmp/thingsboard-analysis -name "*.jar" -type f | while read jar_file; do
    if jar -tf "$jar_file" 2>/dev/null | grep -q "CheckInstanceResponse\|SignatureUtil"; then
        echo -e "${YELLOW}Found in: $jar_file${NC}"
        jar -tf "$jar_file" | grep -E "(CheckInstance|SignatureUtil|signature)" | head -5
    fi
done

echo -e "${BLUE}📦 Step 8: Extract and Decompile Shared Classes${NC}"
# Find shared JAR
SHARED_JAR=$(find /tmp/thingsboard-analysis -name "*shared*.jar" -type f | head -1)
if [ -n "$SHARED_JAR" ]; then
    echo "Found shared JAR: $SHARED_JAR"
    
    # Extract shared JAR to separate directory
    SHARED_DIR="/tmp/shared-analysis"
    mkdir -p "$SHARED_DIR"
    cd "$SHARED_DIR"
    jar -xf "$SHARED_JAR"
    
    # Find and decompile SignatureUtil
    if [ -f "./org/thingsboard/license/shared/signature/SignatureUtil.class" ]; then
        decompile_class "./org/thingsboard/license/shared/signature/SignatureUtil.class" "SignatureUtil"
    fi
    
    # Find and decompile CheckInstanceResponse
    CHECKINST_CLASS=$(find . -name "*CheckInstance*Response*.class" | head -1)
    if [ -n "$CHECKINST_CLASS" ]; then
        decompile_class "$CHECKINST_CLASS" "CheckInstanceResponse"
    fi
    
    # Find and decompile CheckInstanceRequest
    CHECKREQ_CLASS=$(find . -name "*CheckInstance*Request*.class" | head -1)
    if [ -n "$CHECKREQ_CLASS" ]; then
        decompile_class "$CHECKREQ_CLASS" "CheckInstanceRequest"
    fi
    
    cd "$ANALYSIS_DIR"
else
    echo -e "${YELLOW}⚠️  No shared JAR found${NC}"
fi

echo -e "${BLUE}📦 Step 9: Generate Summary${NC}"
SUMMARY_FILE="$OUTPUT_DIR/analysis_summary.txt"
cat > "$SUMMARY_FILE" << EOF
ThingsBoard License Client Analysis Summary
==========================================
Generated: $(date)

Decompiled Files:
$(ls -la $OUTPUT_DIR/*.java 2>/dev/null || echo "No Java files found")

Key Classes Status:
- TbLicenseClient: $([ -f "$OUTPUT_DIR/TbLicenseClient.java" ] && echo "✅ Decompiled" || echo "❌ Not found")
- SignatureUtil: $([ -f "$OUTPUT_DIR/SignatureUtil.java" ] && echo "✅ Decompiled" || echo "❌ Not found")
- CheckInstanceResponse: $([ -f "$OUTPUT_DIR/CheckInstanceResponse.java" ] && echo "✅ Decompiled" || echo "❌ Not found")
- CheckInstanceRequest: $([ -f "$OUTPUT_DIR/CheckInstanceRequest.java" ] && echo "✅ Decompiled" || echo "❌ Not found")

Analysis Directories:
- License Client: $ANALYSIS_DIR
- Shared Classes: $SHARED_DIR
- Decompiled Output: $OUTPUT_DIR

Next Steps:
1. Review decompiled Java files in $OUTPUT_DIR/
2. Focus on signature verification logic in SignatureUtil.java
3. Understand CheckInstanceResponse structure
4. Analyze TbLicenseClient.persistInstanceData() method
EOF

echo -e "${GREEN}📋 Analysis Summary:${NC}"
cat "$SUMMARY_FILE"

echo -e "${GREEN}🎉 Decompilation Complete!${NC}"
echo -e "${BLUE}📁 Check decompiled files in: $OUTPUT_DIR/${NC}"
echo -e "${BLUE}📋 Full summary in: $SUMMARY_FILE${NC}"

echo -e "${YELLOW}💡 Quick commands to view key files:${NC}"
echo "cat $OUTPUT_DIR/TbLicenseClient.java | head -50"
echo "cat $OUTPUT_DIR/SignatureUtil.java"
echo "cat $OUTPUT_DIR/CheckInstanceResponse.java"
