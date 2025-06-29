#!/bin/bash

# ThingsBoard License Class Decompiler
# Specifically extracts and decompiles license classes

set -e

echo "🎯 ThingsBoard License Class Decompiler"
echo "======================================="

WORK_DIR="/tmp/tb-decompile"
OUTPUT_DIR="$WORK_DIR/decompiled_sources"
CFR_JAR="/tmp/cfr-0.152.jar"

# Setup
rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Download CFR if needed
if [ ! -f "$CFR_JAR" ]; then
    echo "📥 Downloading CFR decompiler..."
    wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/download/0.152/cfr-0.152.jar"
    echo "✅ CFR downloaded"
fi

# Find ThingsBoard JAR
TB_JAR=""
POSSIBLE_LOCATIONS=(
    "/usr/share/thingsboard/bin/thingsboard.jar"
    "/opt/thingsboard/bin/thingsboard.jar"
    "/var/lib/thingsboard/thingsboard.jar"
    "./thingsboard.jar"
)

for location in "${POSSIBLE_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        TB_JAR="$location"
        echo "✅ Found ThingsBoard JAR: $location"
        break
    fi
done

if [ -z "$TB_JAR" ]; then
    echo "❌ ThingsBoard JAR not found"
    echo "Please ensure ThingsBoard is installed or place thingsboard.jar in current directory"
    exit 1
fi

cd "$WORK_DIR"

# Extract main JAR
echo "📦 Extracting main ThingsBoard JAR..."
jar -xf "$TB_JAR" >/dev/null 2>&1

# Find license JARs
echo "🔍 Finding license JARs..."
LICENSE_JARS=($(find . -name "*.jar" | grep -E "(client|shared|license)" | sort))

if [ ${#LICENSE_JARS[@]} -eq 0 ]; then
    echo "❌ No license JARs found"
    echo "🔍 Available JARs:"
    find . -name "*.jar" | head -10
    exit 1
fi

echo "📋 Found license JARs:"
for jar in "${LICENSE_JARS[@]}"; do
    echo "   - $(basename $jar)"
done

# Function to decompile entire JAR
decompile_jar() {
    local jar_file="$1"
    local jar_name=$(basename "$jar_file" .jar)
    local jar_output_dir="$OUTPUT_DIR/$jar_name"
    
    echo ""
    echo "🎯 Decompiling: $jar_name"
    echo "================================"
    
    mkdir -p "$jar_output_dir"
    
    # Decompile entire JAR
    java -jar "$CFR_JAR" "$jar_file" --outputdir "$jar_output_dir" 2>/dev/null || {
        echo "❌ Failed to decompile $jar_name"
        return
    }
    
    echo "✅ Decompiled: $jar_name"
    
    # List generated files
    local java_files=($(find "$jar_output_dir" -name "*.java" | sort))
    echo "📄 Generated files (${#java_files[@]}):"
    
    for java_file in "${java_files[@]}"; do
        local rel_path="${java_file#$jar_output_dir/}"
        local lines=$(wc -l < "$java_file" 2>/dev/null || echo "0")
        echo "   - $rel_path ($lines lines)"
        
        # Special handling for key classes
        if [[ "$java_file" == *"SignatureUtil"* ]]; then
            echo "🎯 FOUND SIGNATUREUTIL!"
            show_source_preview "$java_file" "SignatureUtil"
        elif [[ "$java_file" == *"TbLicenseClient"* ]]; then
            echo "🎯 FOUND TbLicenseClient!"
            show_source_preview "$java_file" "TbLicenseClient"
        elif [[ "$java_file" == *"CheckInstance"* ]]; then
            echo "🎯 FOUND CheckInstance class!"
            show_source_preview "$java_file" "CheckInstance"
        fi
    done
}

# Function to show source code preview
show_source_preview() {
    local java_file="$1"
    local class_name="$2"
    
    echo ""
    echo "📄 === $class_name SOURCE CODE ==="
    echo "File: $java_file"
    echo "Lines: $(wc -l < "$java_file")"
    echo "════════════════════════════════════════════════════════════════"
    cat "$java_file"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

# Decompile each license JAR
for jar in "${LICENSE_JARS[@]}"; do
    decompile_jar "$jar"
done

# Create summary report
SUMMARY_FILE="$OUTPUT_DIR/DECOMPILE_SUMMARY.md"
cat > "$SUMMARY_FILE" << EOF
# ThingsBoard License Decompilation Summary

**Generated:** $(date)
**Source JAR:** $TB_JAR
**Output Directory:** $OUTPUT_DIR

## Decompiled JARs

EOF

for jar in "${LICENSE_JARS[@]}"; do
    jar_name=$(basename "$jar" .jar)
    java_count=$(find "$OUTPUT_DIR/$jar_name" -name "*.java" 2>/dev/null | wc -l)
    echo "### $jar_name ($java_count files)" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    if [ $java_count -gt 0 ]; then
        echo "#### Key Classes Found:" >> "$SUMMARY_FILE"
        find "$OUTPUT_DIR/$jar_name" -name "*.java" | while read java_file; do
            rel_path="${java_file#$OUTPUT_DIR/$jar_name/}"
            lines=$(wc -l < "$java_file")
            echo "- \`$rel_path\` ($lines lines)" >> "$SUMMARY_FILE"
        done
        echo "" >> "$SUMMARY_FILE"
    fi
done

cat >> "$SUMMARY_FILE" << EOF

## Key Files for License Bypass

### SignatureUtil
$(find "$OUTPUT_DIR" -name "*SignatureUtil*.java" | head -1 | sed "s|$OUTPUT_DIR/|Location: |" || echo "❌ Not found")

### TbLicenseClient  
$(find "$OUTPUT_DIR" -name "*TbLicenseClient*.java" | head -1 | sed "s|$OUTPUT_DIR/|Location: |" || echo "❌ Not found")

### CheckInstance Classes
EOF

find "$OUTPUT_DIR" -name "*CheckInstance*.java" | while read file; do
    echo "- ${file#$OUTPUT_DIR/}" >> "$SUMMARY_FILE"
done

cat >> "$SUMMARY_FILE" << EOF

## Quick Access Commands

### View all SignatureUtil files
\`\`\`bash
find $OUTPUT_DIR -name "*SignatureUtil*.java" -exec cat {} \;
\`\`\`

### View all TbLicenseClient files  
\`\`\`bash
find $OUTPUT_DIR -name "*TbLicenseClient*.java" -exec cat {} \;
\`\`\`

### Search for verification methods
\`\`\`bash
grep -r "verify\|signature" $OUTPUT_DIR/ --include="*.java"
\`\`\`

### List all decompiled classes
\`\`\`bash
find $OUTPUT_DIR -name "*.java" | sort
\`\`\`

---
*All source files are available in: $OUTPUT_DIR*
EOF

echo ""
echo "🎉 DECOMPILATION COMPLETE!"
echo "=========================="
echo ""
echo "📊 Summary:"
echo "   - Processed JARs: ${#LICENSE_JARS[@]}"
echo "   - Total Java files: $(find "$OUTPUT_DIR" -name "*.java" 2>/dev/null | wc -l)"
echo "   - SignatureUtil files: $(find "$OUTPUT_DIR" -name "*SignatureUtil*.java" 2>/dev/null | wc -l)"
echo "   - TbLicenseClient files: $(find "$OUTPUT_DIR" -name "*TbLicenseClient*.java" 2>/dev/null | wc -l)"
echo ""
echo "📁 All decompiled sources: $OUTPUT_DIR"
echo "📋 Summary report: $SUMMARY_FILE"
echo ""
echo "🔧 Quick commands:"
echo "   # View summary"
echo "   cat $SUMMARY_FILE"
echo ""
echo "   # View SignatureUtil"
echo "   find $OUTPUT_DIR -name '*SignatureUtil*.java' -exec cat {} \;"
echo ""
echo "   # View TbLicenseClient"  
echo "   find $OUTPUT_DIR -name '*TbLicenseClient*.java' -exec cat {} \;"
echo ""
echo "   # List all files"
echo "   find $OUTPUT_DIR -name '*.java' | sort"

# Also create quick access scripts
cat > "$OUTPUT_DIR/view_signatureutil.sh" << 'EOF'
#!/bin/bash
find /tmp/tb-decompile/decompiled_sources -name "*SignatureUtil*.java" -exec echo "=== {} ===" \; -exec cat {} \;
EOF

cat > "$OUTPUT_DIR/view_licenseclient.sh" << 'EOF'  
#!/bin/bash
find /tmp/tb-decompile/decompiled_sources -name "*TbLicenseClient*.java" -exec echo "=== {} ===" \; -exec cat {} \;
EOF

chmod +x "$OUTPUT_DIR"/*.sh

echo ""
echo "✅ Quick access scripts created:"
echo "   $OUTPUT_DIR/view_signatureutil.sh"
echo "   $OUTPUT_DIR/view_licenseclient.sh"
