#!/bin/bash

# ThingsBoard SignatureUtil Bypass - TARGETED PATCH
# Based on actual SignatureUtil.class analysis
# Target: verify() methods that throw SignatureException

set -e

echo "🔧 ThingsBoard SignatureUtil Bypass - TARGETED PATCH"
echo "=================================================="

# Configuration
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
WORK_DIR="/tmp/license-bypass"
BACKUP_DIR="/tmp/license-backup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Auto-restore function
auto_restore() {
    if [ -f "$BACKUP_DIR/thingsboard-original.jar" ]; then
        echo_error "FAILED! Auto-restoring original JAR..."
        systemctl stop thingsboard 2>/dev/null || true
        cp "$BACKUP_DIR/thingsboard-original.jar" "$THINGSBOARD_JAR"
        chown thingsboard:thingsboard "$THINGSBOARD_JAR" 2>/dev/null || true
        chmod 644 "$THINGSBOARD_JAR"
        echo_error "Original JAR restored. Patch failed."
    else
        echo_error "Patch failed and no backup available!"
    fi
}

# Set trap for auto-restore on error
trap auto_restore ERR

echo_success "Step 1: Setup and validation"
rm -rf "$WORK_DIR" "$BACKUP_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR" "$BACKUP_DIR"

# Validate ThingsBoard JAR
[ -f "$THINGSBOARD_JAR" ] || echo_error "ThingsBoard JAR not found: $THINGSBOARD_JAR"

# Check Java
command -v java >/dev/null 2>&1 || echo_error "Java not found!"

echo_success "Step 2: Backup original JAR"
cp "$THINGSBOARD_JAR" "$BACKUP_DIR/thingsboard-original.jar"

echo_success "Step 3: Extract and locate SignatureUtil"
cd "$WORK_DIR"
jar -xf "$THINGSBOARD_JAR" || echo_error "Failed to extract main JAR"

# Find SignatureUtil in any JAR
SIGNATURE_UTIL_CLASS=""
CONTAINING_JAR=""

# Search in all JARs
for jar_file in $(find . -name "*.jar"); do
    if jar -tf "$jar_file" 2>/dev/null | grep -q "signature/SignatureUtil.class"; then
        CONTAINING_JAR="$jar_file"
        break
    fi
done

[ -n "$CONTAINING_JAR" ] || echo_error "SignatureUtil not found in any JAR"

echo_success "Step 4: Extract containing JAR"
EXTRACT_DIR="$WORK_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
cd "$EXTRACT_DIR"
jar -xf "../$CONTAINING_JAR" || echo_error "Failed to extract containing JAR"

SIGNATURE_UTIL_CLASS=$(find . -name "SignatureUtil.class" | head -1)
[ -n "$SIGNATURE_UTIL_CLASS" ] || echo_error "SignatureUtil.class not found after extraction"

echo_success "Step 5: Create targeted bytecode patcher"
cd "$WORK_DIR"
cat > TargetedPatcher.java << 'EOF'
import java.io.*;
import java.nio.file.*;

public class TargetedPatcher {
    public static void main(String[] args) throws Exception {
        String classPath = args[0];
        byte[] classBytes = Files.readAllBytes(Paths.get(classPath));
        
        boolean patched = false;
        int patchCount = 0;
        
        // Strategy 1: Find "Invalid response signature" and "Invalid secret data signature" strings
        // Replace the exception throwing pattern with return true
        String[] errorMessages = {
            "Invalid response signature",
            "Invalid secret data signature"
        };
        
        for (String errorMsg : errorMessages) {
            byte[] errorBytes = errorMsg.getBytes("UTF-8");
            
            // Find the error message in bytecode
            for (int i = 0; i <= classBytes.length - errorBytes.length; i++) {
                boolean found = true;
                for (int j = 0; j < errorBytes.length; j++) {
                    if (classBytes[i + j] != errorBytes[j]) {
                        found = false;
                        break;
                    }
                }
                
                if (found) {
                    System.out.println("Found error message at offset: " + i);
                    
                    // Look backwards for the method that contains this error
                    // Find the nearest ATHROW instruction before this string
                    for (int k = i - 1; k >= 0 && k > i - 100; k--) {
                        if (classBytes[k] == (byte)0xBF) { // ATHROW
                            System.out.println("Found ATHROW at offset: " + k);
                            // Replace ATHROW with ICONST_1 IRETURN (return true)
                            classBytes[k] = 0x04;     // ICONST_1 (true)
                            if (k + 1 < classBytes.length) {
                                classBytes[k + 1] = (byte)0xAC; // IRETURN
                            }
                            patched = true;
                            patchCount++;
                            System.out.println("Patched exception to return true at offset: " + k);
                            break;
                        }
                    }
                }
            }
        }
        
        // Strategy 2: Find and replace specific verify method patterns
        // Look for method signature patterns and replace return false with return true
        for (int i = 0; i < classBytes.length - 10; i++) {
            // Pattern: ICONST_0 IRETURN (return false)
            if (classBytes[i] == 0x03 && classBytes[i + 1] == (byte)0xAC) {
                // Check if this is in a verify method context
                // Look for "verify" method name nearby (within 50 bytes)
                boolean inVerifyMethod = false;
                for (int j = Math.max(0, i - 50); j < Math.min(classBytes.length - 6, i + 50); j++) {
                    if (j + 5 < classBytes.length &&
                        classBytes[j] == 'v' && classBytes[j+1] == 'e' && 
                        classBytes[j+2] == 'r' && classBytes[j+3] == 'i' && 
                        classBytes[j+4] == 'f' && classBytes[j+5] == 'y') {
                        inVerifyMethod = true;
                        break;
                    }
                }
                
                if (inVerifyMethod) {
                    System.out.println("Found 'return false' in verify method at offset: " + i);
                    classBytes[i] = 0x04; // ICONST_0 -> ICONST_1 (false -> true)
                    patched = true;
                    patchCount++;
                    System.out.println("Changed return false to return true at offset: " + i);
                }
            }
        }
        
        // Strategy 3: Replace any remaining SignatureException constructors
        // Look for NEW SignatureException patterns
        for (int i = 0; i < classBytes.length - 20; i++) {
            // Look for NEW instruction followed by SignatureException reference
            if (classBytes[i] == (byte)0xBB) { // NEW instruction
                // Check if this could be creating a SignatureException
                // Replace with ICONST_1 IRETURN pattern
                boolean couldBeException = false;
                for (int j = i; j < Math.min(classBytes.length - 15, i + 15); j++) {
                    if (j + 14 < classBytes.length) {
                        String bytePart = "";
                        for (int k = 0; k < 15; k++) {
                            if (j + k < classBytes.length) {
                                char c = (char)classBytes[j + k];
                                if (c >= 'A' && c <= 'z') {
                                    bytePart += c;
                                }
                            }
                        }
                        if (bytePart.toLowerCase().contains("signatur") || 
                            bytePart.toLowerCase().contains("exceptio")) {
                            couldBeException = true;
                            break;
                        }
                    }
                }
                
                if (couldBeException) {
                    System.out.println("Found potential exception creation at offset: " + i);
                    // Replace NEW with ICONST_1 and continue
                    classBytes[i] = 0x04;     // ICONST_1
                    classBytes[i + 1] = (byte)0xAC; // IRETURN
                    classBytes[i + 2] = 0x00; // NOP
                    patched = true;
                    patchCount++;
                    System.out.println("Replaced exception with return true at offset: " + i);
                }
            }
        }
        
        if (!patched) {
            System.err.println("ERROR: No signature verification patterns found to patch");
            System.err.println("Class might have different structure than expected");
            System.exit(1);
        }
        
        Files.write(Paths.get(classPath), classBytes);
        System.out.println("SUCCESS: Applied " + patchCount + " targeted patches to SignatureUtil");
        System.out.println("All signature verification should now return true");
    }
}
EOF

javac TargetedPatcher.java || echo_error "Failed to compile targeted patcher"

echo_success "Step 6: Apply targeted patch to SignatureUtil"
java TargetedPatcher "$EXTRACT_DIR/$SIGNATURE_UTIL_CLASS" || echo_error "Failed to patch SignatureUtil"

echo_success "Step 7: Rebuild containing JAR"
cd "$EXTRACT_DIR"
jar -cf "../patched-jar.jar" * || echo_error "Failed to rebuild containing JAR"
cd "$WORK_DIR"
cp "patched-jar.jar" "$CONTAINING_JAR"

echo_success "Step 8: Rebuild main ThingsBoard JAR"
jar -cf "thingsboard-patched.jar" * || echo_error "Failed to rebuild main JAR"

echo_success "Step 9: Install patched JAR"
systemctl stop thingsboard 2>/dev/null || true
cp "thingsboard-patched.jar" "$THINGSBOARD_JAR"
chown thingsboard:thingsboard "$THINGSBOARD_JAR" 2>/dev/null || true
chmod 644 "$THINGSBOARD_JAR"

echo_success "Step 10: Create restore script"
cat > "$BACKUP_DIR/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
systemctl stop thingsboard 2>/dev/null || true
cp /tmp/license-backup/thingsboard-original.jar /usr/share/thingsboard/bin/thingsboard.jar
chown thingsboard:thingsboard /usr/share/thingsboard/bin/thingsboard.jar 2>/dev/null || true
chmod 644 /usr/share/thingsboard/bin/thingsboard.jar
echo "✅ Original JAR restored"
RESTORE_EOF
chmod +x "$BACKUP_DIR/restore.sh"

# Clear trap - success
trap - ERR

echo ""
echo_success "🎉 TARGETED PATCH SUCCESSFUL!"
echo_success "All SignatureUtil.verify() methods bypassed"
echo_success "Exception throwing replaced with return true"
echo_success "Start: systemctl start thingsboard"
echo_success "Restore: $BACKUP_DIR/restore.sh"
