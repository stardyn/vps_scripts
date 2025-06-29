#!/bin/bash

# ThingsBoard SignatureUtil Hex-Level Bypass
# Direct hex editing approach

set -e

echo "🔧 ThingsBoard SignatureUtil Hex-Level Bypass"
echo "============================================"

# Configuration
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
WORK_DIR="/tmp/hex-bypass"
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

trap auto_restore ERR

echo_success "Step 1: Setup"
rm -rf "$WORK_DIR" "$BACKUP_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR" "$BACKUP_DIR"

[ -f "$THINGSBOARD_JAR" ] || echo_error "ThingsBoard JAR not found: $THINGSBOARD_JAR"
command -v java >/dev/null 2>&1 || echo_error "Java not found!"

echo_success "Step 2: Backup original JAR"
cp "$THINGSBOARD_JAR" "$BACKUP_DIR/thingsboard-original.jar"

echo_success "Step 3: Extract main JAR"
cd "$WORK_DIR"
jar -xf "$THINGSBOARD_JAR" || echo_error "Failed to extract main JAR"

echo_success "Step 4: Extract shared JAR"
SHARED_JAR="BOOT-INF/lib/shared-1.3.0.jar"
[ -f "$SHARED_JAR" ] || echo_error "shared-1.3.0.jar not found"

SHARED_DIR="$WORK_DIR/shared"
mkdir -p "$SHARED_DIR"
cd "$SHARED_DIR"
jar -xf "../$SHARED_JAR" || echo_error "Failed to extract shared JAR"

echo_success "Step 5: Find SignatureUtil.class"
SIG_CLASS=$(find . -name "SignatureUtil.class" | head -1)
[ -n "$SIG_CLASS" ] || echo_error "SignatureUtil.class not found"
echo "Found: $SIG_CLASS"

echo_success "Step 6: Create hex editor"
cd "$WORK_DIR"
cat > HexEditor.java << 'JAVA_EOF'
import java.io.*;
import java.nio.file.*;

public class HexEditor {
    public static void main(String[] args) throws Exception {
        String classFile = args[0];
        byte[] data = Files.readAllBytes(Paths.get(classFile));
        
        System.out.println("File size: " + data.length + " bytes");
        
        int changes = 0;
        
        // Strategy 1: Replace error strings with valid strings
        changes += replaceString(data, "Invalid response signature", "BYPASSED_response_signatur");
        changes += replaceString(data, "Invalid secret data signature", "BYPASSED_secret_data_signatu");
        
        // Strategy 2: Change all ICONST_0 to ICONST_1 (false to true)
        for (int i = 0; i < data.length; i++) {
            if (data[i] == 0x03) { // ICONST_0
                data[i] = 0x04; // ICONST_1
                changes++;
            }
        }
        
        System.out.println("Applied " + changes + " changes");
        
        if (changes > 0) {
            Files.write(Paths.get(classFile), data);
            System.out.println("SUCCESS: File modified");
        } else {
            System.err.println("ERROR: No changes made");
            System.exit(1);
        }
    }
    
    static int replaceString(byte[] data, String find, String replace) {
        if (find.length() != replace.length()) {
            System.err.println("ERROR: String lengths don't match");
            return 0;
        }
        
        byte[] findBytes = find.getBytes();
        byte[] replaceBytes = replace.getBytes();
        int changes = 0;
        
        for (int i = 0; i <= data.length - findBytes.length; i++) {
            boolean match = true;
            for (int j = 0; j < findBytes.length; j++) {
                if (data[i + j] != findBytes[j]) {
                    match = false;
                    break;
                }
            }
            
            if (match) {
                System.out.println("Replacing '" + find + "' at offset " + i);
                for (int j = 0; j < replaceBytes.length; j++) {
                    data[i + j] = replaceBytes[j];
                }
                changes++;
                i += findBytes.length - 1; // Skip ahead
            }
        }
        
        return changes;
    }
}
JAVA_EOF

javac HexEditor.java || echo_error "Failed to compile HexEditor"

echo_success "Step 7: Apply hex modifications"
java HexEditor "$SHARED_DIR/$SIG_CLASS" || echo_error "Failed to modify class"

echo_success "Step 8: Rebuild shared JAR"
cd "$SHARED_DIR"
jar -cf "../shared-modified.jar" * || echo_error "Failed to rebuild shared JAR"

echo_success "Step 9: Replace shared JAR"
cd "$WORK_DIR"
cp "shared-modified.jar" "$SHARED_JAR" || echo_error "Failed to replace shared JAR"

echo_success "Step 10: Rebuild main JAR"
jar -cf "thingsboard-bypassed.jar" * || echo_error "Failed to rebuild main JAR"

echo_success "Step 11: Install patched JAR"
systemctl stop thingsboard 2>/dev/null || true
cp "thingsboard-bypassed.jar" "$THINGSBOARD_JAR"
chown thingsboard:thingsboard "$THINGSBOARD_JAR" 2>/dev/null || true
chmod 644 "$THINGSBOARD_JAR"

echo_success "Step 12: Create restore script"
cat > "$BACKUP_DIR/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
systemctl stop thingsboard 2>/dev/null || true
cp /tmp/license-backup/thingsboard-original.jar /usr/share/thingsboard/bin/thingsboard.jar
chown thingsboard:thingsboard /usr/share/thingsboard/bin/thingsboard.jar 2>/dev/null || true
chmod 644 /usr/share/thingsboard/bin/thingsboard.jar
echo "✅ Original JAR restored"
RESTORE_EOF
chmod +x "$BACKUP_DIR/restore.sh"

trap - ERR

echo ""
echo_success "🎉 HEX-LEVEL BYPASS SUCCESSFUL!"
echo_success "Error strings replaced with BYPASSED messages"
echo_success "All false constants changed to true constants"
echo_success "Test JAR: java -server -Dloader.main=org.thingsboard.server.ThingsBoardServerApplication -jar $THINGSBOARD_JAR"
echo_success "Restore: $BACKUP_DIR/restore.sh"
