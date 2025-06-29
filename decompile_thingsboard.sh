#!/bin/bash

# Enhanced ThingsBoard License Client Decompile Script
# Usage: ./enhanced_decompile_thingsboard.sh

set -e  # Exit on any error

echo "🔍 Enhanced ThingsBoard License Client Decompilation Script v3.0"
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

# Configuration - Multiple possible locations
POSSIBLE_THINGSBOARD_JARS=(
    "/usr/share/thingsboard/bin/thingsboard.jar"
    "/opt/thingsboard/bin/thingsboard.jar"
    "/var/lib/thingsboard/thingsboard.jar"
    "/usr/local/thingsboard/bin/thingsboard.jar"
    "./thingsboard.jar"
    "/tmp/thingsboard.jar"
)

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
        wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/latest/download/cfr-0.152.jar" || {
            echo_warning "CFR download failed, trying alternative..."
            wget -q -O "$CFR_JAR" "https://github.com/leibnitz27/cfr/releases/download/0.152/cfr-0.152.jar"
        }
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

# Find ThingsBoard JAR
find_thingsboard_jar() {
    echo_info "Searching for ThingsBoard JAR file..."
    
    MAIN_THINGSBOARD_JAR=""
    
    for jar_path in "${POSSIBLE_THINGSBOARD_JARS[@]}"; do
        if [ -f "$jar_path" ]; then
            MAIN_THINGSBOARD_JAR="$jar_path"
            echo_success "Found ThingsBoard JAR: $jar_path"
            break
        fi
    done
    
    if [ -z "$MAIN_THINGSBOARD_JAR" ]; then
        echo_warning "ThingsBoard JAR not found in standard locations"
        echo_info "Searching system-wide for ThingsBoard JARs..."
        
        # Search for any JAR containing "thingsboard"
        potential_jars=$(find /usr /opt /var /home 2>/dev/null | grep -i "thingsboard.*\.jar$" | head -5)
        
        if [ -n "$potential_jars" ]; then
            echo_info "Found potential ThingsBoard JARs:"
            echo "$potential_jars" | nl
            
            # Use the first one found
            MAIN_THINGSBOARD_JAR=$(echo "$potential_jars" | head -1)
            echo_highlight "Using: $MAIN_THINGSBOARD_JAR"
        else
            echo_error "No ThingsBoard JAR found on the system"
            echo_info "Please ensure ThingsBoard is installed or provide JAR path manually"
            echo_info "You can download ThingsBoard and place thingsboard.jar in current directory"
            
            # Check if user wants to download
            read -p "Do you want to download ThingsBoard Community Edition? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                download_thingsboard
            else
                exit 1
            fi
        fi
    fi
    
    # Verify JAR is readable
    if [ ! -r "$MAIN_THINGSBOARD_JAR" ]; then
        echo_error "Cannot read ThingsBoard JAR: $MAIN_THINGSBOARD_JAR"
        echo_info "Checking permissions..."
        ls -la "$MAIN_THINGSBOARD_JAR"
        exit 1
    fi
    
    # Check JAR size - should be substantial
    jar_size=$(du -h "$MAIN_THINGSBOARD_JAR" | cut -f1)
    echo_info "JAR size: $jar_size"
    
    return 0
}

# Download ThingsBoard if needed
download_thingsboard() {
    echo_info "Downloading ThingsBoard Community Edition..."
    
    # Get latest version
    TB_VERSION="3.6.4"  # Update this as needed
    TB_URL="https://github.com/thingsboard/thingsboard/releases/download/v${TB_VERSION}/thingsboard-${TB_VERSION}.deb"
    
    echo_info "Downloading from: $TB_URL"
    wget -O "/tmp/thingsboard.deb" "$TB_URL" || {
        echo_error "Failed to download ThingsBoard"
        echo_info "Please download ThingsBoard manually and place the JAR in current directory"
        exit 1
    }
    
    # Extract the JAR from DEB
    cd /tmp
    ar x thingsboard.deb
    tar -xf data.tar.xz
    
    if [ -f "/tmp/usr/share/thingsboard/bin/thingsboard.jar" ]; then
        MAIN_THINGSBOARD_JAR="/tmp/usr/share/thingsboard/bin/thingsboard.jar"
        echo_success "Extracted ThingsBoard JAR: $MAIN_THINGSBOARD_JAR"
    else
        echo_error "Failed to extract ThingsBoard JAR from DEB package"
        exit 1
    fi
}

check_java
download_decompilers
find_thingsboard_jar

echo_step "Step 2: Extract Main ThingsBoard JAR"
echo_info "Extracting main ThingsBoard JAR: $MAIN_THINGSBOARD_JAR"
cd "$THINGSBOARD_EXTRACT_DIR"

if ! jar -xf "$MAIN_THINGSBOARD_JAR" >/dev/null 2>&1; then
    echo_error "Failed to extract ThingsBoard JAR"
    echo_info "Checking if file is corrupted..."
    file "$MAIN_THINGSBOARD_JAR"
    exit 1
fi

echo_success "Main JAR extracted to: $THINGSBOARD_EXTRACT_DIR"

# Show extracted structure
echo_info "Extracted structure:"
find . -maxdepth 3 -type d | head -10

echo_step "Step 3: Find and Catalog All License-Related JARs"

# Function to find license-related JARs
find_license_jars() {
    echo_info "Scanning for license-related JARs and classes..."

    # Find all JARs that might contain license code
    declare -a LICENSE_JARS
    declare -a LICENSE_CLASSES

    # Primary candidates - look for JARs
    while IFS= read -r -d '' jar_file; do
        jar_name=$(basename "$jar_file")
        case "$jar_name" in
            *client*|*license*|*shared*|*core*|*common*|*tb-*|*thingsboard*)
                LICENSE_JARS+=("$jar_file")
                ;;
        esac
    done < <(find "$THINGSBOARD_EXTRACT_DIR" -name "*.jar" -type f -print0 2>/dev/null)

    # Also look for direct .class files (in case they're not in JARs)
    while IFS= read -r -d '' class_file; do
        class_name=$(basename "$class_file")
        case "$class_name" in
            *License*|*Signature*|*TbClient*|*CheckInstance*)
                LICENSE_CLASSES+=("$class_file")
                ;;
        esac
    done < <(find "$THINGSBOARD_EXTRACT_DIR" -name "*.class" -type f -print0 2>/dev/null)

    echo_success "Found ${#LICENSE_JARS[@]} potential license JARs and ${#LICENSE_CLASSES[@]} direct classes"
    
    if [ ${#LICENSE_JARS[@]} -gt 0 ]; then
        echo_info "License-related JARs:"
        for i in "${!LICENSE_JARS[@]}"; do
            jar_file="${LICENSE_JARS[$i]}"
            jar_size=$(du -h "$jar_file" | cut -f1)
            echo "   $((i+1)). $(basename "$jar_file") ($jar_size)"

            # Quick peek inside for license classes
            license_class_count=$(jar -tf "$jar_file" 2>/dev/null | grep -i -E "(license|signature|client)" | wc -l)
            if [ "$license_class_count" -gt 0 ]; then
                echo "      └─ Contains $license_class_count license-related classes"
                
                # Show some example classes
                jar -tf "$jar_file" 2>/dev/null | grep -i -E "(license|signature|client)" | head -3 | while read class; do
                    echo "         - $class"
                done
            fi
        done
    fi
    
    if [ ${#LICENSE_CLASSES[@]} -gt 0 ]; then
        echo_info "Direct license classes found:"
        for class_file in "${LICENSE_CLASSES[@]:0:10}"; do  # Show first 10
            echo "   - ${class_file#$THINGSBOARD_EXTRACT_DIR/}"
        done
        if [ ${#LICENSE_CLASSES[@]} -gt 10 ]; then
            echo "   ... and $((${#LICENSE_CLASSES[@]} - 10)) more"
        fi
    fi

    # Store globally
    FOUND_LICENSE_JARS=("${LICENSE_JARS[@]}")
    FOUND_LICENSE_CLASSES=("${LICENSE_CLASSES[@]}")
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
    local license_classes=($(find . -name "*.class" | grep -i -E "(license|signature|checker|validator|client|tbclient)" 2>/dev/null))

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

# Process JARs
for jar_file in "${FOUND_LICENSE_JARS[@]}"; do
    analyze_jar "$jar_file"
done

# Add direct classes to the list
for class_file in "${FOUND_LICENSE_CLASSES[@]}"; do
    echo "$class_file" >> "$OUTPUT_DIR/all_license_classes.txt"
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

# Check if we have any classes to decompile
if [ ! -s "$OUTPUT_DIR/all_license_classes.txt" ]; then
    echo_warning "No license classes found to decompile"
    echo_info "This might mean:"
    echo "  - License code is embedded differently"
    echo "  - Different package structure than expected"
    echo "  - License validation is in a different component"
    
    echo_info "Searching for any class containing 'license' or 'signature'..."
    find "$THINGSBOARD_EXTRACT_DIR" -name "*.class" -exec grep -l "license\|signature\|License\|Signature" {} \; 2>/dev/null | head -5 || true
    
    echo_info "Searching for Spring Boot structure..."
    find "$THINGSBOARD_EXTRACT_DIR" -path "*/BOOT-INF/classes/*" -name "*.class" | head -10
else
    # Priority class patterns to focus on
    PRIORITY_PATTERNS=(
        "*TbLicenseClient*"
        "*SignatureUtil*"
        "*CheckInstance*Response*"
        "*CheckInstance*Request*"
        "*AbstractTbLicense*"
        "*LicenseValidator*"
        "*LicenseChecker*"
        "*License*"
        "*Client*"
    )

    decompiled_count=0
    while IFS= read -r class_path; do
        if [ -f "$class_path" ]; then
            class_name=$(basename "$class_path" .class)
            
            # Try CFR first, then FernFlower as backup
            if decompile_class_enhanced "$class_path" "$class_name" "cfr"; then
                # Find and show the decompiled file
                java_file=$(find "$OUTPUT_DIR" -name "${class_name}.java" | head -1)
                if [ -n "$java_file" ]; then
                    show_code_preview "$java_file" "🔍 $class_name (CFR)"
                    ((decompiled_count++))
                fi
            elif decompile_class_enhanced "$class_path" "$class_name" "fernflower"; then
                java_file=$(find "$OUTPUT_DIR" -name "${class_name}.java" | head -1)
                if [ -n "$java_file" ]; then
                    show_code_preview "$java_file" "🔍 $class_name (FernFlower)"
                    ((decompiled_count++))
                fi
            else
                echo_warning "Failed to decompile: $class_name"
            fi
            
            # Limit output to avoid overwhelming
            if [ $decompiled_count -ge 5 ]; then
                echo_info "Limiting preview to first 5 classes. All classes are being decompiled..."
                break
            fi
        fi
    done < "$OUTPUT_DIR/all_license_classes.txt"
fi

echo_step "Step 6: Generate Comprehensive Analysis Report"

REPORT_FILE="$OUTPUT_DIR/comprehensive_analysis_report.md"
cat > "$REPORT_FILE" << EOF
# ThingsBoard License Client Analysis Report

**Generated:** $(date)
**Analyzer:** Enhanced Decompilation Script v3.0
**ThingsBoard JAR:** $MAIN_THINGSBOARD_JAR

## 📊 Summary

### Source JAR
- **Path:** $MAIN_THINGSBOARD_JAR
- **Size:** $(du -h "$MAIN_THINGSBOARD_JAR" | cut -f1)

### Analyzed JARs
$(for jar in "${FOUND_LICENSE_JARS[@]}"; do echo "- $(basename "$jar")"; done)

### Direct Classes Found
$([ ${#FOUND_LICENSE_CLASSES[@]} -gt 0 ] && echo "${#FOUND_LICENSE_CLASSES[@]} license-related classes found directly" || echo "No direct license classes found")

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
    "LicenseValidator"
    "LicenseChecker"
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
find $OUTPUT_DIR -name "*License*.java" -exec cat {} \;

# Signature verification
find $OUTPUT_DIR -name "*Signature*.java" -exec cat {} \;

# Response/Request structures
find $OUTPUT_DIR -name "*CheckInstance*.java" -exec cat {} \;
\`\`\`

### Search for Specific Methods
\`\`\`bash
# Find signature verification methods
grep -r "verify\|signature" $OUTPUT_DIR/*.java 2>/dev/null || echo "No matches"

# Find license validation logic
grep -r "valid\|check\|license" $OUTPUT_DIR/*.java 2>/dev/null || echo "No matches"

# Find network communication
grep -r "http\|request\|response" $OUTPUT_DIR/*.java 2>/dev/null || echo "No matches"
\`\`\`

## 🎯 Key Areas to Focus On

1. **License Client Classes** - Main license validation logic
2. **Signature Verification** - Signature verification bypass points
3. **Network Communication** - License server communication
4. **Validation Flows** - Main validation logic paths

## 🚀 Next Steps

1. Review decompiled source code for license validation logic
2. Identify signature verification points
3. Understand communication protocol with license server
4. Plan bytecode modification strategy
5. Create targeted patches for key validation methods

---
*Analysis completed: $(date)*
*ThingsBoard JAR: $MAIN_THINGSBOARD_JAR*
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
find "$OUTPUT_DIR" -name "*.java" 2>/dev/null | head -10

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
echo "   find $OUTPUT_DIR -name \"*.java\" -exec grep -l 'methodName' {} \;"
echo "   find $OUTPUT_DIR -name \"*License*.java\" -exec cat {} \;"
echo "   find $OUTPUT_DIR -name \"*Signature*.java\" -exec cat {} \;"
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

find "$OUTPUT_DIR" -name "*.java" -exec grep -H -n -i -A 5 -B 2 "$PATTERN" {} \; 2>/dev/null || {
    echo "No matches found for: $PATTERN"
}
SEARCH_EOF

chmod +x "$OUTPUT_DIR/search_patterns.sh"

echo_step "Step 8: Final Summary and Next Steps"

echo_success "🎉 Enhanced Decompilation Complete!"
echo ""
echo_highlight "📊 Analysis Results:"
echo "   - Source JAR: $MAIN_THINGSBOARD_JAR"
echo "   - Analyzed JARs: ${#FOUND_LICENSE_JARS[@]}"
echo "   - Direct classes: ${#FOUND_LICENSE_CLASSES[@]}"
echo "   - Decompiled classes: $(find "$OUTPUT_DIR" -name "*.java" 2>/dev/null | wc -l)"
echo "   - Total lines of code: $(find "$OUTPUT_DIR" -name "*.java" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)"
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
echo "   # View decompiled classes"
echo "   find $OUTPUT_DIR -name '*.java' -exec ls -la {} \;"
echo ""
echo_highlight "🎯 Key Files to Review:"
KEY_FILES_FOUND=$(find "$OUTPUT_DIR" -name "*.java" | head -5)
if [ -n "$KEY_FILES_FOUND" ]; then
    echo "$KEY_FILES_FOUND" | while read java_file; do
        echo "   ✅ cat $java_file"
    done
else
    echo "   ⚠️  No Java files found - check extraction process"
fi

echo ""
echo_warning "💡 Next Steps:"
echo "   1. Review the comprehensive analysis report"
echo "   2. Focus on signature verification logic"
echo "   3. Understand license validation flow"
echo "   4. Plan targeted bytecode modifications"
echo "   5. Create custom patches based on findings"

# Show some helpful diagnostics if no classes were found
if [ $(find "$OUTPUT_DIR" -name "*.java" 2>/dev/null | wc -l) -eq 0 ]; then
    echo ""
    echo_warning "🔍 No classes were decompiled. Possible reasons:"
    echo "   - License code might be obfuscated"
    echo "   - Different package structure than expected"
    echo "   - License validation in native code"
    echo "   - Different ThingsBoard version structure"
    echo ""
    echo_info "Manual investigation suggested:"
    echo "   - Check $THINGSBOARD_EXTRACT_DIR for actual structure"
    echo "   - Look for Spring Boot classes in BOOT-INF/"
    echo "   - Search for any .class files manually"
fi

echo ""
echo_success "✅ All analysis tools ready for use!"
