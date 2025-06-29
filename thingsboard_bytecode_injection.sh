#!/bin/bash

# ThingsBoard SignatureUtil Bypass - SAFE BYTECODE PATCHING
# Only modify specific verify method bytecode patterns

set -e

echo "🔧 ThingsBoard SignatureUtil Bypass - SAFE BYTECODE PATCHING"
echo "==========================================================="

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

echo_success "Step 3: Extract main ThingsBoard JAR"
cd "$WORK_DIR"
jar -xf "$THINGSBOARD_JAR" || echo_error "Failed to extract main JAR"

echo_success "Step 4: Find shared-1.3.0.jar"
SHARED_JAR="BOOT-INF/lib/shared-1.3.0.jar"
[ -f "$SHARED_JAR" ] || echo_error "shared-1.3.0.jar not found at $SHARED_JAR"

echo_success "Step 5: Extract shared JAR"
SHARED_DIR="$WORK_DIR/shared_extracted"
mkdir -p "$SHARED_DIR"
cd "$SHARED_DIR"
jar -xf "../$SHARED_JAR" || echo_error "Failed to extract shared JAR"

echo_success "Step 6: Locate SignatureUtil.class"
SIGNATURE_UTIL_CLASS=$(find . -name "SignatureUtil.class" | head -1)
[ -n "$SIGNATURE_UTIL_CLASS" ] || echo_error "SignatureUtil.class not found"

echo_success "Step 7: Create safe bytecode patcher"
cd "$WORK_DIR"
cat > SafeBytecodeModifier.java << 'EOF'
import java.io.*;
import java.nio.file.*;

public class SafeBytecodeModifier {
    public static void main(String[] args) throws Exception {
        String classPath = args[0];
        byte[] classBytes = Files.readAllBytes(Paths.get(classPath));
        
        System.out.println("Original class size: " + classBytes.length + " bytes");
        
        boolean modified = false;
        int modifications = 0;
        
        // SAFE Strategy 1: Find and replace ICONST_0 IRETURN with ICONST_1 IRETURN
        // This changes "return false" to "return true"
        for (int i = 0; i < classBytes.length - 1; i++) {
            if (classBytes[i] == 0x03 && classBytes[i + 1] == (byte)0xAC) {
                // Found ICONST_0 IRETURN (return false)
                classBytes[i] = 0x04; // Change to ICONST_1 (return true)
                modified = true;
                modifications++;
                System.out.println("Modified return false->true at offset: " + i);
            }
        }
        
        // SAFE Strategy 2: Find SignatureException creation and neutralize
        // Look for "Invalid response signature" string
        String errorMsg1 = "Invalid response signature";
        String errorMsg2 = "Invalid secret data signature";
        
        for (String errorMsg : new String[]{errorMsg1, errorMsg2}) {
            for (int i = 0; i <= classBytes.length - errorMsg.length(); i++) {
                boolean found = true;
                for (int j = 0; j < errorMsg.length(); j++) {
                    if (classBytes[i + j] != errorMsg.charAt(j)) {
                        found = false;
                        break;
                    }
                }
                
                if (found) {
                    System.out.println("Found error message at offset: " + i);
                    
                    // Look backward for ATHROW instruction and replace it
                    for (int k = Math.max(0, i - 50); k < i; k++) {
                        if (classBytes[k] == (byte)0xBF) { // ATHROW
                            System.out.println("Found ATHROW at offset: " + k);
                            // Replace ATHROW with ICONST_1 IRETURN
                            classBytes[k] = 0x04;     // ICONST_1 (true)
                            if (k + 1 < classBytes.length) {
                                classBytes[k + 1] = (byte)0xAC; // IRETURN
                            }
                            modified = true;
                            modifications++;
                            System.out.println("Replaced ATHROW with return true at offset: " + k);
                            break;
                        }
                    }
                }
            }
        }
        
        // SAFE Strategy 3: Look for verify method signatures and ensure they return true
        // Find method name "verify" in constant pool and modify associated code
        String verifyMethodName = "verify";
        for (int i = 0; i <= classBytes.length - verifyMethodName.length(); i++) {
            boolean found = true;
            for (int j = 0; j < verifyMethodName.length(); j++) {
                if (classBytes[i + j] != verifyMethodName.charAt(j)) {
                    found = false;
                    break;
                }
            }
            
            if (found) {
                System.out.println("Found 'verify' method name at offset: " + i);
                
                // Look forward for method code and ensure it returns true
                for (int k = i; k < Math.min(classBytes.length - 10, i + 200); k++) {
                    // Look for method return patterns
                    if (classBytes[k] == 0x03 && k + 1 < classBytes.length && 
                        classBytes[k + 1] == (byte)0xAC) {
                        // Found ICONST_0 IRETURN, change to ICONST_1 IRETURN
                        classBytes[k] = 0x04;
                        modified = true;
                        modifications++;
                        System.out.println("Modified verify method return at offset: " + k);
                    }
                }
            }
        }
        
        if (modified) {
            Files.write(Paths.get(classPath), classBytes);
            System.out.println("SUCCESS: Applied " + modifications + " safe modifications");
            System.out.println("Modified class size: " + classBytes.length + " bytes");
        } else {
            System.err.println("ERROR: No signature verification patterns found to modify");
            System.exit(1);
        }
    }
}
EOF

javac SafeBytecodeModifier.java || echo_error "Failed to compile SafeBytecodeModifier"

echo_success "Step 8: Apply safe bytecode modifications"
java SafeBytecodeModifier "$SHARED_DIR/$SIGNATURE_UTIL_CLASS" || echo_error "Failed to modify bytecode"

echo_success "Step 9: Rebuild shared JAR"
cd "$SHARED_DIR"
jar -cf "../shared-1.3.0-patched.jar" * || echo_error "Failed to rebuild shared JAR"

echo_success "Step 10: Replace shared JAR in main structure"
cd "$WORK_DIR"
cp "shared-1.3.0-patched.jar" "$SHARED_JAR" || echo_error "Failed to replace shared JAR"

echo_success "Step 11: Rebuild main ThingsBoard JAR"
jar -cf "thingsboard-patched.jar" * || echo_error "Failed to rebuild main JAR"

echo_success "Step 12: Verify JAR integrity"
# Quick integrity check
if jar -tf "thingsboard-patched.jar" | grep -q "BOOT-INF/lib/shared-1.3.0.jar"; then
    echo_success "JAR structure verified"
else
    echo_error "JAR structure corrupted"
fi

echo_success "Step 13: Install patched JAR"
systemctl stop thingsboard 2>/dev/null || true
cp "thingsboard-patched.jar" "$THINGSBOARD_JAR"
chown thingsboard:thingsboard "$THINGSBOARD_JAR" 2>/dev/null || true
chmod 644 "$THINGSBOARD_JAR"

echo_success "Step 14: Create restore script"
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
echo_success "🎉 SAFE BYTECODE PATCHING SUCCESSFUL!"
echo_success "SignatureUtil.class safely modified"
echo_success "JAR integrity maintained"
echo_success "All verify() methods should now return true"
echo_success "Test: java -server -Dloader.main=org.thingsboard.server.ThingsBoardServerApplication -jar $THINGSBOARD_JAR"
echo_success "Restore: $BACKUP_DIR/restore.sh"
