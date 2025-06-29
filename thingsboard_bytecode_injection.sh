#!/bin/bash

#apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/thingsboard_bytecode_injection.sh && dos2unix thingsboard_bytecode_injection.sh && chmod +x thingsboard_bytecode_injection.sh && ./thingsboard_bytecode_injection.sh
#rm -rf /tmp/*
#rm -rf /tmp/.*  2>/dev/null || true
#!/bin/bash

# Simple ThingsBoard License Signature Bypass
# Only patches TbLicenseClient.persistInstanceData() method
#!/bin/bash

# Enhanced ThingsBoard License Bypass with Better Detection
# Automatically finds and patches license validation components

set -e

echo "🔧 Enhanced ThingsBoard License Bypass v2.0"
echo "============================================="

# Configuration
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
WORK_DIR="/tmp/enhanced-license-patch"
BACKUP_DIR="/tmp/license-backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}📋 $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

echo_info "Step 1: Setup and Validation"
if [ ! -f "$THINGSBOARD_JAR" ]; then
    echo_error "ThingsBoard JAR not found: $THINGSBOARD_JAR"
    echo_info "Please check if ThingsBoard is installed and path is correct"
    exit 1
fi

# Check if we have required tools
command -v java >/dev/null 2>&1 || { echo_error "Java not found. Please install Java."; exit 1; }
command -v javac >/dev/null 2>&1 || { echo_error "Javac not found. Please install JDK."; exit 1; }
command -v jar >/dev/null 2>&1 || { echo_error "Jar tool not found. Please install JDK."; exit 1; }

rm -rf "$WORK_DIR" "$BACKUP_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR" "$BACKUP_DIR"
cd "$WORK_DIR"

echo_info "Step 2: Backup and Extract JAR"
cp "$THINGSBOARD_JAR" "$BACKUP_DIR/thingsboard-original.jar"
echo_success "Backup created: $BACKUP_DIR/thingsboard-original.jar"

echo_info "Extracting JAR (this may take a while)..."
jar -xf "$THINGSBOARD_JAR" >/dev/null 2>&1
echo_success "JAR extracted successfully"

echo_info "Step 3: Advanced License Component Detection"

# Function to search for license-related classes
find_license_classes() {
    echo_info "Searching for license-related classes..."
    
    # Search patterns for license classes
    LICENSE_PATTERNS=(
        "*License*.class"
        "*license*.class" 
        "*TbLicense*.class"
        "*LicenseClient*.class"
        "*LicenseValidator*.class"
        "*LicenseChecker*.class"
        "*LicenseVerifier*.class"
    )
    
    declare -a FOUND_CLASSES
    
    for pattern in "${LICENSE_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            FOUND_CLASSES+=("$file")
        done < <(find . -name "$pattern" -type f -print0 2>/dev/null)
    done
    
    # Remove duplicates and sort
    IFS=$'\n' FOUND_CLASSES=($(printf '%s\n' "${FOUND_CLASSES[@]}" | sort -u))
    
    if [ ${#FOUND_CLASSES[@]} -eq 0 ]; then
        echo_error "No license-related classes found!"
        return 1
    fi
    
    echo_success "Found ${#FOUND_CLASSES[@]} license-related classes:"
    for i in "${!FOUND_CLASSES[@]}"; do
        echo "   $((i+1)). ${FOUND_CLASSES[$i]}"
    done
    
    # Return the array via global variable
    LICENSE_CLASSES=("${FOUND_CLASSES[@]}")
    return 0
}

# Function to analyze class files for license validation methods
analyze_class_file() {
    local class_file="$1"
    echo_info "Analyzing: $class_file"
    
    # Use javap to disassemble and look for license-related methods
    local temp_analysis="/tmp/class_analysis.txt"
    
    # Try to disassemble the class
    if javap -cp . -c "${class_file%.class}" > "$temp_analysis" 2>/dev/null; then
        # Look for common license validation patterns
        local suspicious_methods=$(grep -i -E "(verify|validate|check|sign)" "$temp_analysis" | wc -l)
        local crypto_calls=$(grep -i -E "(signature|rsa|sha|hash)" "$temp_analysis" | wc -l)
        local license_strings=$(strings "$class_file" 2>/dev/null | grep -i -E "(license|valid|signature|verify)" | wc -l)
        
        local score=$((suspicious_methods + crypto_calls + license_strings))
        
        echo "     - Suspicious methods: $suspicious_methods"
        echo "     - Crypto operations: $crypto_calls" 
        echo "     - License strings: $license_strings"
        echo "     - Total score: $score"
        
        rm -f "$temp_analysis"
        return $score
    else
        echo_warning "Could not disassemble class file"
        return 0
    fi
}

# Function to create bytecode patcher
create_bytecode_patcher() {
    cat > AdvancedBytecodeInjector.java << 'EOF'
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class AdvancedBytecodeInjector {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.out.println("Usage: java AdvancedBytecodeInjector <class-file>");
            System.exit(1);
        }
        
        String classPath = args[0];
        System.out.println("🎯 Advanced patching: " + classPath);
        
        byte[] classBytes = Files.readAllBytes(Paths.get(classPath));
        boolean patched = false;
        
        // Strategy 1: Replace signature verification calls
        patched |= patchSignatureVerification(classBytes);
        
        // Strategy 2: Replace boolean returns for validation methods  
        patched |= patchValidationReturns(classBytes);
        
        // Strategy 3: Replace exception throwing
        patched |= patchExceptionThrows(classBytes);
        
        if (patched) {
            // Create backup
            Files.copy(Paths.get(classPath), Paths.get(classPath + ".backup"));
            
            // Write patched class
            Files.write(Paths.get(classPath), classBytes);
            System.out.println("✅ Class successfully patched!");
            System.out.println("📦 Backup saved as: " + classPath + ".backup");
        } else {
            System.out.println("❌ No patchable patterns found in this class");
            System.exit(1);
        }
    }
    
    private static boolean patchSignatureVerification(byte[] classBytes) {
        boolean patched = false;
        
        // Look for INVOKESTATIC signature verification patterns
        for (int i = 0; i < classBytes.length - 10; i++) {
            // INVOKESTATIC opcode (0xB8)
            if (classBytes[i] == (byte)0xB8) {
                // Replace with ICONST_1 (load true) + POP (remove method args) + ICONST_1 (return true)
                // This effectively makes signature verification always return true
                
                // Pattern: B8 XX XX -> 04 57 04 (ICONST_1, POP, ICONST_1)
                classBytes[i] = 0x04;     // ICONST_1 (push true)
                classBytes[i + 1] = 0x57; // POP (remove method arguments)
                classBytes[i + 2] = 0x04; // ICONST_1 (push result true)
                
                patched = true;
                System.out.println("🔧 Patched signature verification at offset " + i);
            }
        }
        
        return patched;
    }
    
    private static boolean patchValidationReturns(byte[] classBytes) {
        boolean patched = false;
        
        // Look for ICONST_0 (false) followed by IRETURN and replace with ICONST_1 (true)
        for (int i = 0; i < classBytes.length - 1; i++) {
            if (classBytes[i] == 0x03 && classBytes[i + 1] == (byte)0xAC) {
                // ICONST_0 IRETURN -> ICONST_1 IRETURN
                classBytes[i] = 0x04; // ICONST_1 instead of ICONST_0
                patched = true;
                System.out.println("🔧 Patched validation return at offset " + i);
            }
        }
        
        return patched;
    }
    
    private static boolean patchExceptionThrows(byte[] classBytes) {
        boolean patched = false;
        
        // Look for ATHROW (exception throwing) and replace with RETURN
        for (int i = 0; i < classBytes.length; i++) {
            if (classBytes[i] == (byte)0xBF) { // ATHROW
                classBytes[i] = (byte)0xB1; // RETURN (void return)
                patched = true;
                System.out.println("🔧 Patched exception throw at offset " + i);
            }
        }
        
        return patched;
    }
}
EOF
}

# Function to create alternative simple patcher
create_simple_patcher() {
    cat > SimpleLicensePatcher.java << 'EOF'
import java.io.*;
import java.nio.file.*;

public class SimpleLicensePatcher {
    public static void main(String[] args) throws Exception {
        String classPath = args[0];
        System.out.println("🎯 Simple patching: " + classPath);
        
        byte[] classBytes = Files.readAllBytes(Paths.get(classPath));
        
        // Create a minimal patch that disables signature checking
        // by replacing key bytecode patterns with NOPs
        
        boolean patched = false;
        int patchCount = 0;
        
        // Replace common signature verification bytecode patterns
        byte[][] patterns = {
            // INVOKESTATIC patterns (method calls)
            {(byte)0xB8, (byte)0x00},  // INVOKESTATIC + index
            // IFEQ patterns (if equals zero - false checks)  
            {(byte)0x99, (byte)0x00},  // IFEQ + branch
            // IFNE patterns (if not equals - true checks)
            {(byte)0x9A, (byte)0x00},  // IFNE + branch
        };
        
        for (byte[] pattern : patterns) {
            for (int i = 0; i < classBytes.length - pattern.length; i++) {
                boolean match = true;
                for (int j = 0; j < pattern.length; j++) {
                    if (pattern[j] != 0x00 && classBytes[i + j] != pattern[j]) {
                        match = false;
                        break;
                    }
                }
                
                if (match) {
                    // Replace with NOPs
                    for (int j = 0; j < pattern.length; j++) {
                        classBytes[i + j] = 0x00; // NOP
                    }
                    patchCount++;
                    patched = true;
                }
            }
        }
        
        if (patched) {
            Files.write(Paths.get(classPath), classBytes);
            System.out.println("✅ Applied " + patchCount + " patches to class file");
        } else {
            System.out.println("❌ No suitable patterns found for patching");
            System.exit(1);
        }
    }
}
EOF
}

# Main execution
if ! find_license_classes; then
    echo_error "No license classes found. This might not be a standard ThingsBoard installation."
    echo_info "Checking JAR structure..."
    
    echo_info "BOOT-INF directory structure:"
    find BOOT-INF -name "*.jar" | head -10
    
    echo_info "Classes directory structure:"
    find . -name "*.class" | grep -i license | head -10
    
    exit 1
fi

echo_info "Step 4: Selecting Best Candidate Classes"

# Analyze each found class and rank by likelihood of being license validation
declare -a CLASS_SCORES
for class_file in "${LICENSE_CLASSES[@]}"; do
    if [ -f "$class_file" ]; then
        score=$(analyze_class_file "$class_file")
        CLASS_SCORES+=("$score:$class_file")
    fi
done

# Sort by score (highest first)
IFS=$'\n' SORTED_CLASSES=($(printf '%s\n' "${CLASS_SCORES[@]}" | sort -nr))

echo_info "Step 5: Patching Strategy"

# Create patchers
create_bytecode_patcher
create_simple_patcher

echo_info "Compiling patchers..."
javac AdvancedBytecodeInjector.java || { echo_error "Failed to compile advanced patcher"; exit 1; }
javac SimpleLicensePatcher.java || { echo_error "Failed to compile simple patcher"; exit 1; }

# Try to patch the top candidate classes
PATCHED_COUNT=0
for class_score in "${SORTED_CLASSES[@]}"; do
    score=${class_score%%:*}
    class_file=${class_score#*:}
    
    if [ "$score" -gt 0 ]; then
        echo_info "Attempting to patch: $class_file (score: $score)"
        
        # Try advanced patcher first
        if java AdvancedBytecodeInjector "$class_file" 2>/dev/null; then
            echo_success "Advanced patch successful: $class_file"
            ((PATCHED_COUNT++))
        elif java SimpleLicensePatcher "$class_file" 2>/dev/null; then
            echo_success "Simple patch successful: $class_file"
            ((PATCHED_COUNT++))
        else
            echo_warning "Could not patch: $class_file"
        fi
    fi
    
    # Limit to top 5 classes to avoid over-patching
    if [ "$PATCHED_COUNT" -ge 5 ]; then
        break
    fi
done

if [ "$PATCHED_COUNT" -eq 0 ]; then
    echo_error "No classes could be patched!"
    echo_info "This might indicate:"
    echo "   - Non-standard ThingsBoard version"
    echo "   - Already patched installation"
    echo "   - Different license implementation"
    exit 1
fi

echo_success "Successfully patched $PATCHED_COUNT classes"

echo_info "Step 6: Rebuilding JAR"
jar -cf thingsboard-patched.jar * >/dev/null 2>&1
echo_success "JAR rebuilt successfully"

echo_info "Step 7: Installing Patched JAR"
systemctl stop thingsboard 2>/dev/null || true
sleep 2

cp thingsboard-patched.jar "$THINGSBOARD_JAR"
chown thingsboard:thingsboard "$THINGSBOARD_JAR" 2>/dev/null || true
chmod 644 "$THINGSBOARD_JAR"

echo_success "Patched JAR installed"

echo_info "Step 8: Creating Restoration Tools"
cat > "$BACKUP_DIR/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
echo "🔄 Restoring original ThingsBoard..."
systemctl stop thingsboard 2>/dev/null || true
cp /tmp/license-backup/thingsboard-original.jar /usr/share/thingsboard/bin/thingsboard.jar
chown thingsboard:thingsboard /usr/share/thingsboard/bin/thingsboard.jar 2>/dev/null || true
chmod 644 /usr/share/thingsboard/bin/thingsboard.jar
echo "✅ Original ThingsBoard restored!"
echo "🚀 Start with: systemctl start thingsboard"
RESTORE_EOF

chmod +x "$BACKUP_DIR/restore.sh"

cat > "$BACKUP_DIR/verify.sh" << 'VERIFY_EOF'
#!/bin/bash
echo "🔍 ThingsBoard License Bypass Verification"
echo "=========================================="
echo "📦 Checking patched classes..."

cd /tmp/enhanced-license-patch
if [ -f thingsboard-patched.jar ]; then
    echo "✅ Patched JAR exists"
    jar -tf thingsboard-patched.jar | grep -i license | head -5
else
    echo "❌ Patched JAR not found"
fi

echo ""
echo "📋 Service status:"
systemctl status thingsboard --no-pager -l

echo ""
echo "📋 Recent logs:"
journalctl -u thingsboard --no-pager -n 20
VERIFY_EOF

chmod +x "$BACKUP_DIR/verify.sh"

echo ""
echo_success "🎉 ENHANCED THINGSBOARD LICENSE BYPASS COMPLETE!"
echo ""
echo_info "📋 Summary:"
echo "   - Analyzed JAR structure automatically"
echo "   - Found and ranked ${#LICENSE_CLASSES[@]} license-related classes"
echo "   - Successfully patched $PATCHED_COUNT classes"
echo "   - Created backup and restoration tools"
echo ""
echo_info "🚀 Next Steps:"
echo "   1. systemctl start thingsboard"
echo "   2. journalctl -u thingsboard -f"
echo "   3. Check ThingsBoard web interface"
echo ""
echo_info "🔧 Troubleshooting Tools:"
echo "   - Restore original: $BACKUP_DIR/restore.sh"
echo "   - Verify patch: $BACKUP_DIR/verify.sh"
echo "   - View logs: journalctl -u thingsboard -f"
echo ""
echo_warning "⚠️  If issues occur:"
echo "   - Check logs for license-related errors"
echo "   - Try starting ThingsBoard step by step"
echo "   - Use restore script if needed"

# Cleanup
cd /
rm -rf "$WORK_DIR"

echo ""
echo_success "✅ Patch installation complete!"
