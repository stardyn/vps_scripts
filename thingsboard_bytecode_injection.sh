#!/bin/bash

# ThingsBoard SignatureUtil Bypass - BOOT-INF/lib PATH
# Target: BOOT-INF/lib/shared-1.3.0.jar inside thingsboard.jar

set -e

echo "🔧 ThingsBoard SignatureUtil Bypass - BOOT-INF/lib PATH"
echo "====================================================="

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

echo_success "Step 4: Find shared-1.3.0.jar in BOOT-INF/lib"
SHARED_JAR="BOOT-INF/lib/shared-1.3.0.jar"
[ -f "$SHARED_JAR" ] || echo_error "shared-1.3.0.jar not found at $SHARED_JAR"
echo "Found shared JAR: $SHARED_JAR"

echo_success "Step 5: Extract shared-1.3.0.jar"
SHARED_DIR="$WORK_DIR/shared_extracted"
mkdir -p "$SHARED_DIR"
cd "$SHARED_DIR"
jar -xf "../$SHARED_JAR" || echo_error "Failed to extract shared JAR"

echo_success "Step 6: Locate SignatureUtil.class"
SIGNATURE_UTIL_CLASS=$(find . -name "SignatureUtil.class" | head -1)
[ -n "$SIGNATURE_UTIL_CLASS" ] || echo_error "SignatureUtil.class not found in shared JAR"
echo "Found SignatureUtil: $SIGNATURE_UTIL_CLASS"

SIGNATURE_UTIL_DIR=$(dirname "$SIGNATURE_UTIL_CLASS")

echo_success "Step 7: Create replacement SignatureUtil.java"
mkdir -p "$WORK_DIR/replacement/$SIGNATURE_UTIL_DIR"

cat > "$WORK_DIR/replacement/$SIGNATURE_UTIL_DIR/SignatureUtil.java" << 'EOF'
package org.thingsboard.license.shared.signature;

import org.thingsboard.license.shared.CheckInstanceResponse;
import org.thingsboard.license.shared.OfflineLicenseData;
import org.thingsboard.license.shared.PlanData;
import org.thingsboard.license.shared.PlanItem;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.nio.ByteBuffer;
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
 */
public class SignatureUtil {
    
    private static final Logger log = LoggerFactory.getLogger(SignatureUtil.class);
    private static final String SHA_ALGORITHM = "SHA512withRSA";
    private static final ObjectMapper mapper = new ObjectMapper();
    
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
    
    public static void sign(PrivateKey signatureKey, CheckInstanceResponse response) throws Exception {
        System.out.println("🔓 BYPASS: Generating fake signature for CheckInstanceResponse");
        byte[] toSignData = getBytesToSign(response);
        
        try {
            Signature signature = Signature.getInstance(SHA_ALGORITHM);
            signature.initSign(signatureKey, new SecureRandom());
            signature.update(toSignData);
            response.setSignature(signature.sign());
        } catch (Exception e) {
            response.setSignature(new byte[256]);
        }
    }
    
    // MAIN TARGET: Always return true
    public static boolean verify(PublicKey signatureKey, CheckInstanceResponse response) throws Exception {
        System.out.println("🔓 BYPASS: SignatureUtil.verify(CheckInstanceResponse) -> TRUE");
        return true;
    }
    
    public static void sign(PrivateKey signatureKey, OfflineLicenseData secretData) throws Exception {
        System.out.println("🔓 BYPASS: Generating fake signature for OfflineLicenseData");
        byte[] toSignData = getBytesToSign(secretData);
        
        try {
            Signature signature = Signature.getInstance(SHA_ALGORITHM);
            signature.initSign(signatureKey, new SecureRandom());
            signature.update(toSignData);
            secretData.setSignature(signature.sign());
        } catch (Exception e) {
            secretData.setSignature(new byte[256]);
        }
    }
    
    // MAIN TARGET: Always return true  
    public static boolean verify(PublicKey signatureKey, OfflineLicenseData secretData) throws Exception {
        System.out.println("🔓 BYPASS: SignatureUtil.verify(OfflineLicenseData) -> TRUE");
        return true;
    }
    
    private static byte[] getBytesToSign(CheckInstanceResponse response) {
        StringBuilder sb = new StringBuilder();
        sb.append(response.getInstanceId());
        response.getPlanData().forEach((k, v) -> {
            sb.append("|").append(k).append("|").append(getValueString(v));
        });
        sb.append("|").append(response.getTs());
        
        byte[] plainData = sb.toString().getBytes(StandardCharsets.UTF_8);
        ByteBuffer bb = ByteBuffer.allocate(plainData.length + response.getEncodedPart().length);
        bb.put(plainData);
        bb.put(response.getEncodedPart());
        return bb.array();
    }
    
    private static byte[] getBytesToSign(OfflineLicenseData secretData) {
        StringBuilder sb = new StringBuilder();
        sb.append(secretData.getClusterIdHash());
        secretData.getPlanData().forEach((k, v) -> {
            sb.append("|").append(k).append("|").append(getValueString(v));
        });
        sb.append("|").append(secretData.getGenerationTs());
        sb.append("|").append(secretData.getCustomerId());
        sb.append("|").append(secretData.getCustomerTitle());
        sb.append("|").append(secretData.getSubscriptionId());
        sb.append("|").append(secretData.getInstanceQuantity());
        sb.append("|").append(secretData.getVersion());
        sb.append("|").append(secretData.getEndTs());
        
        return sb.toString().getBytes(StandardCharsets.UTF_8);
    }
    
    private static String getValueString(PlanItem v) {
        try {
            return mapper.writeValueAsString(v.getValue());
        } catch (Exception e) {
            return "null";
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
EOF

echo_success "Step 8: Compile replacement SignatureUtil"
cd "$WORK_DIR/replacement"

# Build classpath from shared JAR dependencies
CLASSPATH="$SHARED_DIR"

# Add other JARs from BOOT-INF/lib for dependencies
for jar in $(find "$WORK_DIR/BOOT-INF/lib" -name "*.jar" 2>/dev/null | head -10); do
    CLASSPATH="$CLASSPATH:$jar"
done

javac -cp "$CLASSPATH" "$SIGNATURE_UTIL_DIR/SignatureUtil.java" || echo_error "Failed to compile replacement SignatureUtil"

echo_success "Step 9: Replace SignatureUtil.class in shared JAR"
cp "$WORK_DIR/replacement/$SIGNATURE_UTIL_CLASS" "$SHARED_DIR/$SIGNATURE_UTIL_CLASS" || echo_error "Failed to replace SignatureUtil.class"

echo_success "Step 10: Rebuild shared-1.3.0.jar"
cd "$SHARED_DIR"
jar -cf "../shared-1.3.0-patched.jar" * || echo_error "Failed to rebuild shared JAR"

echo_success "Step 11: Replace shared JAR in BOOT-INF/lib"
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
echo_success "🎉 BOOT-INF/lib BYPASS SUCCESSFUL!"
echo_success "BOOT-INF/lib/shared-1.3.0.jar -> SignatureUtil.class REPLACED"
echo_success "All verify() methods now return true"
echo_success "Start: systemctl start thingsboard"
echo_success "Monitor: journalctl -u thingsboard -f | grep BYPASS"
echo_success "Restore: $BACKUP_DIR/restore.sh"
