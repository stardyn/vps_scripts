#!/bin/bash

# ThingsBoard SignatureUtil Bypass - MINIMAL REPLACEMENT
# Clean implementation without external dependencies

set -e

echo "🔧 ThingsBoard SignatureUtil Bypass - MINIMAL REPLACEMENT"
echo "======================================================="

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
echo "Found shared JAR: $SHARED_JAR"

echo_success "Step 5: Extract shared JAR"
SHARED_DIR="$WORK_DIR/shared_extracted"
mkdir -p "$SHARED_DIR"
cd "$SHARED_DIR"
jar -xf "../$SHARED_JAR" || echo_error "Failed to extract shared JAR"

echo_success "Step 6: Locate SignatureUtil.class"
SIGNATURE_UTIL_CLASS=$(find . -name "SignatureUtil.class" | head -1)
[ -n "$SIGNATURE_UTIL_CLASS" ] || echo_error "SignatureUtil.class not found"
echo "Found SignatureUtil: $SIGNATURE_UTIL_CLASS"

SIGNATURE_UTIL_DIR=$(dirname "$SIGNATURE_UTIL_CLASS")

echo_success "Step 7: Create minimal replacement SignatureUtil.java"
mkdir -p "$WORK_DIR/replacement/$SIGNATURE_UTIL_DIR"

# Create the MINIMAL replacement class
cat > "$WORK_DIR/replacement/$SIGNATURE_UTIL_DIR/SignatureUtil.java" << 'JAVA_EOF'
package org.thingsboard.license.shared.signature;

import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;

/**
 * BYPASSED SignatureUtil - All verification methods return true
 * Minimal implementation without external dependencies
 */
public class SignatureUtil {
    
    private static final String SHA_ALGORITHM = "SHA512withRSA";
    
    static {
        System.out.println("🔓 SIGNATURE VERIFICATION BYPASSED - All verify() methods return true");
    }
    
    public static PrivateKey loadPrivateKey(String keyPath) throws Exception {
        String privateKeyPEM = readFileToString(keyPath);
        privateKeyPEM = privateKeyPEM.replaceAll("-----BEGIN PRIVATE KEY-----", "")
                                   .replaceAll("-----END PRIVATE KEY-----", "")
                                   .replaceAll("\\s", "");
        byte[] decoded = Base64.getDecoder().decode(privateKeyPEM);
        PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(decoded);
        KeyFactory kf = KeyFactory.getInstance("RSA");
        return kf.generatePrivate(spec);
    }
    
    public static PublicKey loadPublicKeyFromString(String publicKeyPEM) throws Exception {
        publicKeyPEM = publicKeyPEM.replaceAll("-----BEGIN PUBLIC KEY-----", "")
                                 .replaceAll("-----END PUBLIC KEY-----", "")
                                 .replaceAll("\\s", "");
        byte[] decoded = Base64.getDecoder().decode(publicKeyPEM);
        X509EncodedKeySpec spec = new X509EncodedKeySpec(decoded);
        KeyFactory kf = KeyFactory.getInstance("RSA");
        return kf.generatePublic(spec);
    }
    
    public static PublicKey loadPublicKeyFromFile(String keyPath) throws Exception {
        String publicKeyPEM = readFileToString(keyPath);
        return loadPublicKeyFromString(publicKeyPEM);
    }
    
    public static void sign(PrivateKey signatureKey, Object response) throws Exception {
        System.out.println("🔓 BYPASS: Generating fake signature");
        // Create minimal fake signature
        byte[] fakeSignature = new byte[256]; // 2048-bit RSA signature size
        // Set signature using reflection to avoid import issues
        try {
            response.getClass().getMethod("setSignature", byte[].class).invoke(response, fakeSignature);
        } catch (Exception e) {
            // If reflection fails, ignore
        }
    }
    
    // MAIN TARGET: Always return true
    public static boolean verify(PublicKey signatureKey, Object response) throws Exception {
        System.out.println("🔓 BYPASS: SignatureUtil.verify() -> TRUE");
        return true;
    }
    
    // Alternative signature for different parameter types
    public static boolean verify(Object signatureKey, Object response) throws Exception {
        System.out.println("🔓 BYPASS: SignatureUtil.verify() -> TRUE");
        return true;
    }
    
    // Generic getBytesToSign method
    public static byte[] getBytesToSign(Object obj) {
        try {
            // Try to get some basic data from the object
            String data = obj.toString();
            return data.getBytes(StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "default-data".getBytes(StandardCharsets.UTF_8);
        }
    }
    
    private static String readFileToString(String filePath) throws Exception {
        Path path = Paths.get(filePath);
        if (!Files.exists(path)) {
            try {
                path = Paths.get(SignatureUtil.class.getClassLoader().getResource(filePath).toURI());
            } catch (Exception e) {
                throw new Exception("File not found: " + filePath);
            }
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }
}
JAVA_EOF

echo_success "Step 8: Compile minimal SignatureUtil"
cd "$WORK_DIR/replacement"

# Simple compilation with basic classpath
javac -cp "." "$SIGNATURE_UTIL_DIR/SignatureUtil.java" || echo_error "Failed to compile minimal SignatureUtil"

echo_success "Step 9: Replace SignatureUtil.class"
cp "$WORK_DIR/replacement/$SIGNATURE_UTIL_CLASS" "$SHARED_DIR/$SIGNATURE_UTIL_CLASS" || echo_error "Failed to replace SignatureUtil.class"

echo_success "Step 10: Rebuild shared JAR"
cd "$SHARED_DIR"
jar -cf "../shared-1.3.0-patched.jar" * || echo_error "Failed to rebuild shared JAR"

echo_success "Step 11: Replace shared JAR in main structure"
cd "$WORK_DIR"
cp "shared-1.3.0-patched.jar" "$SHARED_JAR" || echo_error "Failed to replace shared JAR"

echo_success "Step 12: Rebuild main ThingsBoard JAR"
jar -cf "thingsboard-patched.jar" * || echo_error "Failed to rebuild main JAR"

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
echo_success "🎉 MINIMAL BYPASS SUCCESSFUL!"
echo_success "SignatureUtil.class completely replaced with minimal version"
echo_success "All verify() methods now return true"
echo_success "No external dependencies required"
echo_success "Start: systemctl start thingsboard"
echo_success "Monitor: journalctl -u thingsboard -f | grep BYPASS"
echo_success "Restore: $BACKUP_DIR/restore.sh"
