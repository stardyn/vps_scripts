#!/bin/bash

# Enhanced ThingsBoard License Client Decompile Script
# Usage: ./enhanced_decompile_thingsboard.sh

#apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/enhanced_decompile_thingsboard.sh && dos2unix enhanced_decompile_thingsboard.sh && chmod +x enhanced_decompile_thingsboard.sh && ./enhanced_decompile_thingsboard.sh

set -e  # Exit on any error

echo "🔍 Enhanced ThingsBoard License Client Decompilation Script v2.0"
echo "================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Enhanced output functions
echo_info() { echo -e "${BLUE}📋 $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }
echo_highlight() { echo -e "${CYAN}🎯 $1${NC}"; }
echo_step() { echo -e "${PURPLE}📦 $1${NC}"; }

# Configuration
MAIN_THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
ANALYSIS_DIR="/tmp/enhanced-license-analysis"
THINGSBOARD_EXTRACT_DIR="/tmp/thingsboard-full-extract"
CFR_JAR="/tmp/cfr-0.152.jar"
FERNFLOWER_JAR="/tmp/fernflower.jar"
OUTPUT_DIR="/tmp/decompiled_output"
TOOLS_DIR="/tmp/decompile_tools"

echo_step "Step 1: Setup and Tool Preparation"
mkdir -p "$ANALYSIS_DIR" "$OUTPUT_DIR" "$TOOLS_DIR" "$THINGSBOARD_EXTRACT_DIR"

# Check required tools
check_java() {
    if ! command -v java >/dev/null 2>&1; then
        echo_error "Java not found. Installing OpenJDK..."
        apt-get update && apt-get install -y openjdk-11-jdk
    fi
    echo_success "Java is available: $(java -version 2>&1 | head -1)"
}

# Download decompilers
download_decompilers() {
    echo_info "Downloading decompilation tools..."
    
    # CFR Decompiler
    if [ ! -f "$CFR_JAR" ]; then
        echo_info "Downloading CFR decompiler..."
        wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/latest/download/cfr-0.152.jar"
        echo_success "CFR decompiler downloaded"
    else
        echo_success "CFR decompiler already exists"
    fi
    
    # FernFlower Decompiler (alternative)
    if [ ! -f "$FERNFLOWER_JAR" ]; then
        echo_info "Downloading FernFlower decompiler..."
        wget -q -O "$FERNFLOWER_JAR" "https://github.com/JetBrains/intellij-community/raw/master/plugins/java-decompiler/engine/fernflower.jar" || {
            echo_warning "FernFlower download failed, using CFR only"
        }
    fi
}

check_java
download_decompilers

echo_step "Step 2: Extract Main ThingsBoard JAR"
if [ ! -f "$MAIN_THINGSBOARD_JAR" ]; then
    echo_error "ThingsBoard JAR not found: $MAIN_THINGSBOARD_JAR"
    echo_info "Please ensure ThingsBoard is installed"
    exit 1
fi

echo_info "Extracting main ThingsBoard JAR..."
cd "$THINGSBOARD_EXTRACT_DIR"
jar -xf "$MAIN_THINGSBOARD_JAR" >/dev/null 2>&1
echo_success "Main JAR extracted to: $THINGSBOARD_EXTRACT_DIR"

echo_step "Step 3: Find and Catalog All License-Related JARs"

# Function to find license-related JARs
find_license_jars() {
    echo_info "Scanning for license-related JARs..."
    
    # Find all JARs that might contain license code
    declare -a LICENSE_JARS
    
    # Primary candidates
    while IFS= read -r -d '' jar_file; do
        jar_name=$(basename "$jar_file")
        case "$jar_name" in
            *client*|*license*|*shared*|*core*|*common*)
                LICENSE_JARS+=("$jar_file")
                ;;
        esac
    done < <(find "$THINGSBOARD_EXTRACT_DIR" -name "*.jar" -type f -print0)
    
    echo_success "Found ${#LICENSE_JARS[@]} potential license JARs:"
    for i in "${!LICENSE_JARS[@]}"; do
        jar_file="${LICENSE_JARS[$i]}"
        jar_size=$(du -h "$jar_file" | cut -f1)
        echo "   $((i+1)). $(basename "$jar_file") ($jar_size)"
        
        # Quick peek inside for license classes
        license_class_count=$(jar -tf "$jar_file" 2>/dev/null | grep -i -E "(license|signature)" | wc -l)
        if [ "$license_class_count" -gt 0 ]; then
            echo "      └─ Contains $license_class_count license-related classes"
        fi
    done
    
    # Store globally
    FOUND_LICENSE_JARS=("${LICENSE_JARS[@]}")
}

find_license_jars

echo_step "Step 4: Extract and Analyze Each License JAR"

# Function to extract and analyze a JAR
analyze_jar() {
    local jar_file="$1"
    local jar_name=$(basename "$jar_file" .jar)
    local extract_dir="$ANALYSIS_DIR/$jar_name"
    
    echo_highlight "Analyzing: $jar_name"
    
    mkdir -p "$extract_dir"
    cd "$extract_dir"
    
    # Extract JAR
    if ! jar -xf "$jar_file" >/dev/null 2>&1; then
        echo_warning "Failed to extract: $jar_name"
        return 1
    fi
    
    # Find license-related classes
    local license_classes=($(find . -name "*.class" | grep -i -E "(license|signature|checker|validator|client)" 2>/dev/null))
    
    if [ ${#license_classes[@]} -gt 0 ]; then
        echo_success "Found ${#license_classes[@]} classes in $jar_name:"
        for class_file in "${license_classes[@]}"; do
            echo "     - $class_file"
        done
        
        # Store for later decompilation
        for class_file in "${license_classes[@]}"; do
            echo "$extract_dir/$class_file" >> "$OUTPUT_DIR/all_license_classes.txt"
        done
    else
        echo_info "No license classes found in $jar_name"
    fi
    
    return 0
}

# Analyze all found JARs
echo > "$OUTPUT_DIR/all_license_classes.txt"  # Reset file
for jar_file in "${FOUND_LICENSE_JARS[@]}"; do
    analyze_jar "$jar_file"
done

echo_step "Step 5: Advanced Decompilation with Multiple Tools"

# Enhanced decompilation function
decompile_class_enhanced() {
    local class_path="$1"
    local output_name="$2"
    local method="$3"  # cfr or fernflower
    
    if [ ! -f "$class_path" ]; then
        echo_warning "Class not found: $class_path"
        return 1
    fi
    
    echo_info "Decompiling with $method: $(basename "$class_path")"
    
    case "$method" in
        "cfr")
            java -jar "$CFR_JAR" "$class_path" --outputdir "$OUTPUT_DIR" --silent true 2>/dev/null || {
                echo_warning "CFR decompilation failed for $output_name"
                return 1
            }
            ;;
        "fernflower")
            if [ -f "$FERNFLOWER_JAR" ]; then
                java -jar "$FERNFLOWER_JAR" "$class_path" "$OUTPUT_DIR" 2>/dev/null || {
                    echo_warning "FernFlower decompilation failed for $output_name"
                    return 1
                }
            else
                echo_warning "FernFlower not available"
                return 1
            fi
            ;;
    esac
    
    echo_success "Decompiled: $output_name"
    return 0
}

# Function to show decompiled code preview
show_code_preview() {
    local java_file="$1"
    local title="$2"
    
    if [ -f "$java_file" ]; then
        echo_highlight "$title"
        echo "File: $java_file"
        echo "────────────────────────────────────────"
        head -50 "$java_file" | cat -n
        echo "────────────────────────────────────────"
        local total_lines=$(wc -l < "$java_file")
        echo "Preview: 50 lines of $total_lines total"
        echo ""
    else
        echo_warning "$title - File not found: $java_file"
    fi
}

# Decompile priority classes
echo_info "Decompiling priority license classes..."

# Priority class patterns to focus on
PRIORITY_PATTERNS=(
    "*TbLicenseClient*"
    "*SignatureUtil*" 
    "*CheckInstance*Response*"
    "*CheckInstance*Request*"
    "*AbstractTbLicense*"
    "*LicenseValidator*"
    "*LicenseChecker*"
)

for pattern in "${PRIORITY_PATTERNS[@]}"; do
    echo_info "Searching for pattern: $pattern"
    
    while IFS= read -r class_path; do
        if [[ "$(basename "$class_path")" == $pattern ]]; then
            class_name=$(basename "$class_path" .class)
            
            # Try CFR first, then FernFlower as backup
            if decompile_class_enhanced "$class_path" "$class_name" "cfr"; then
                # Find and show the decompiled file
                java_file=$(find "$OUTPUT_DIR" -name "${class_name}.java" | head -1)
                if [ -n "$java_file" ]; then
                    show_code_preview "$java_file" "🔍 $class_name (CFR)"
                fi
            elif decompile_class_enhanced "$class_path" "$class_name" "fernflower"; then
                java_file=$(find "$OUTPUT_DIR" -name "${class_name}.java" | head -1)
                if [ -n "$java_file" ]; then
                    show_code_preview "$java_file" "🔍 $class_name (FernFlower)"
                fi
            else
                echo_warning "Failed to decompile: $class_name"
            fi
            
            break  # Only process first match for each pattern
        fi
    done < "$OUTPUT_DIR/all_license_classes.txt"
done

echo_step "Step 6: Generate Comprehensive Analysis Report"

REPORT_FILE="$OUTPUT_DIR/comprehensive_analysis_report.md"
cat > "$REPORT_FILE" << EOF
# ThingsBoard License Client Analysis Report

**Generated:** $(date)  
**Analyzer:** Enhanced Decompilation Script v2.0

## 📊 Summary

### Analyzed JARs
$(for jar in "${FOUND_LICENSE_JARS[@]}"; do echo "- $(basename "$jar")"; done)

### Decompiled Classes
$(find "$OUTPUT_DIR" -name "*.java" | wc -l) Java files generated

### Key Files Status
EOF

# Check for key files and add to report
KEY_FILES=(
    "TbLicenseClient"
    "SignatureUtil" 
    "CheckInstanceResponse"
    "CheckInstanceRequest"
    "AbstractTbLicenseClient"
)

for key_file in "${KEY_FILES[@]}"; do
    java_file=$(find "$OUTPUT_DIR" -name "${key_file}.java" | head -1)
    if [ -n "$java_file" ]; then
        echo "- ✅ **$key_file**: $(basename "$java_file")" >> "$REPORT_FILE"
    else
        echo "- ❌ **$key_file**: Not found" >> "$REPORT_FILE"
    fi
done

cat >> "$REPORT_FILE" << EOF

## 📂 Directory Structure

\`\`\`
$OUTPUT_DIR/
$(find "$OUTPUT_DIR" -type f -name "*.java" | head -20 | sed 's|'$OUTPUT_DIR'/|├── |g')
$([ $(find "$OUTPUT_DIR" -name "*.java" | wc -l) -gt 20 ] && echo "└── ... ($(find "$OUTPUT_DIR" -name "*.java" | wc -l) total files)")
\`\`\`

## 🔍 Quick Analysis Commands

### View Key License Classes
\`\`\`bash
# Main license client
cat $OUTPUT_DIR/TbLicenseClient.java

# Signature verification
cat $OUTPUT_DIR/SignatureUtil.java

# Response/Request structures  
cat $OUTPUT_DIR/CheckInstance*.java
\`\`\`

### Search for Specific Methods
\`\`\`bash
# Find signature verification methods
grep -r "verify\|signature" $OUTPUT_DIR/*.java

# Find license validation logic
grep -r "valid\|check\|license" $OUTPUT_DIR/*.java

# Find network communication
grep -r "http\|request\|response" $OUTPUT_DIR/*.java
\`\`\`

## 🎯 Key Areas to Focus On

1. **TbLicenseClient.persistInstanceData()** - License persistence logic
2. **SignatureUtil.verify()** - Signature verification bypass point  
3. **CheckInstanceResponse** - Server response structure
4. **License validation flows** - Main validation logic

## 🚀 Next Steps

1. Review decompiled source code for license validation logic
2. Identify signature verification points  
3. Understand communication protocol with license server
4. Plan bytecode modification strategy
5. Create targeted patches for key validation methods

---
*Analysis completed: $(date)*
EOF

echo_step "Step 7: Create Analysis Helper Scripts"

# Create helper script for code analysis
cat > "$OUTPUT_DIR/analyze_code.sh" << 'HELPER_EOF'
#!/bin/bash
# Quick code analysis helper

OUTPUT_DIR="/tmp/decompiled_output"

echo "🔍 ThingsBoard License Code Analysis Helper"
echo "=========================================="

echo "📋 Available Java files:"
ls -la "$OUTPUT_DIR"/*.java 2>/dev/null | head -10

echo ""
echo "🎯 Quick searches:"

echo ""
echo "1. Signature verification methods:"
grep -r -n -A 3 -B 1 "verify.*signature\|signature.*verify" "$OUTPUT_DIR"/*.java 2>/dev/null | head -10

echo ""
echo "2. License validation returns:"  
grep -r -n "return.*valid\|return.*true\|return.*false" "$OUTPUT_DIR"/*.java 2>/dev/null | head -10

echo ""
echo "3. Network communication:"
grep -r -n "http\|POST\|GET\|request\|response" "$OUTPUT_DIR"/*.java 2>/dev/null | head -10

echo ""
echo "4. Exception handling:"
grep -r -n "throw\|exception\|catch" "$OUTPUT_DIR"/*.java 2>/dev/null | head -10

echo ""
echo "💡 Commands for detailed analysis:"
echo "   grep -r 'methodName' $OUTPUT_DIR/*.java"
echo "   cat $OUTPUT_DIR/TbLicenseClient.java | grep -A 10 'persistInstanceData'"
echo "   cat $OUTPUT_DIR/SignatureUtil.java | grep -A 5 'verify'"
HELPER_EOF

chmod +x "$OUTPUT_DIR/analyze_code.sh"

# Create search script for specific patterns
cat > "$OUTPUT_DIR/search_patterns.sh" << 'SEARCH_EOF'
#!/bin/bash
# Search for specific patterns in decompiled code

OUTPUT_DIR="/tmp/decompiled_output"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <search_pattern>"
    echo "Examples:"
    echo "  $0 'persistInstanceData'"
    echo "  $0 'signature'"
    echo "  $0 'checkInstance'"
    exit 1
fi

PATTERN="$1"
echo "🔍 Searching for pattern: $PATTERN"
echo "================================"

grep -r -n -i -A 5 -B 2 "$PATTERN" "$OUTPUT_DIR"/*.java 2>/dev/null || {
    echo "No matches found for: $PATTERN"
}
SEARCH_EOF

chmod +x "$OUTPUT_DIR/search_patterns.sh"

echo_step "Step 8: Final Summary and Next Steps"

echo_success "🎉 Enhanced Decompilation Complete!"
echo ""
echo_highlight "📊 Analysis Results:"
echo "   - Analyzed JARs: ${#FOUND_LICENSE_JARS[@]}"
echo "   - Decompiled classes: $(find "$OUTPUT_DIR" -name "*.java" | wc -l)"
echo "   - Total lines of code: $(find "$OUTPUT_DIR" -name "*.java" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')"
echo ""
echo_highlight "📁 Output Locations:"
echo "   - Decompiled Java: $OUTPUT_DIR/"
echo "   - Analysis report: $REPORT_FILE"
echo "   - Helper scripts: $OUTPUT_DIR/*.sh"
echo ""
echo_highlight "🔧 Quick Commands:"
echo "   # View main report"
echo "   cat $REPORT_FILE"
echo ""
echo "   # Run code analysis"  
echo "   $OUTPUT_DIR/analyze_code.sh"
echo ""
echo "   # Search for specific patterns"
echo "   $OUTPUT_DIR/search_patterns.sh 'persistInstanceData'"
echo "   $OUTPUT_DIR/search_patterns.sh 'signature'"
echo ""
echo "   # View key classes"
echo "   ls $OUTPUT_DIR/*.java"
echo ""
echo_highlight "🎯 Key Files to Review:"
for key_file in "${KEY_FILES[@]}"; do
    java_file=$(find "$OUTPUT_DIR" -name "${key_file}.java" | head -1)
    if [ -n "$java_file" ]; then
        echo "   ✅ cat $java_file"
    fi
done

echo ""
echo_warning "💡 Next Steps:"
echo "   1. Review the comprehensive analysis report"
echo "   2. Focus on signature verification logic"
echo "   3. Understand license validation flow"
echo "   4. Plan targeted bytecode modifications"
echo "   5. Create custom patches based on findings"

echo ""
echo_success "✅ All analysis tools ready for use!"
