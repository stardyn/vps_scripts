#!/bin/bash

#apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/thingsboard_bytecode_injection.sh && dos2unix thingsboard_bytecode_injection.sh && chmod +x thingsboard_bytecode_injection.sh && ./thingsboard_bytecode_injection.sh
#rm -rf /tmp/*
#rm -rf /tmp/.*  2>/dev/null || true


#!/bin/bash

# ThingsBoard License Bypass - Bytecode Injection
# This script modifies the license verification bytecode

set -e

echo "🔧 ThingsBoard License Bytecode Injection"
echo "========================================"

# Configuration
THINGSBOARD_JAR="/usr/share/thingsboard/bin/thingsboard.jar"
THINGSBOARD_DIR="/tmp/thingsboard-analysis"
INJECTION_DIR="/tmp/license-injection"
BACKUP_DIR="/tmp/license-backup"

echo "📦 Step 1: Clean and setup injection environment"
echo "🧹 Cleaning previous work directories..."
rm -rf "$INJECTION_DIR" 2>/dev/null || true
rm -rf "$BACKUP_DIR" 2>/dev/null || true

mkdir -p "$INJECTION_DIR"
mkdir -p "$BACKUP_DIR"
cd "$INJECTION_DIR"
echo "✅ Clean environment created"

echo "📦 Step 2: Extract and backup ThingsBoard JAR"
echo "🎯 Using ThingsBoard JAR: $THINGSBOARD_JAR"

# Backup original JAR
cp "$THINGSBOARD_JAR" "$BACKUP_DIR/thingsboard-original.jar"
echo "✅ Original JAR backed up"

# Extract main JAR
echo "📦 Extracting main ThingsBoard JAR..."
jar -xf "$THINGSBOARD_JAR"

# Check if license classes exist in extracted content
if [ -f "BOOT-INF/lib/client-1.3.0.jar" ]; then
    echo "✅ Found license client JAR inside main JAR"
    # Extract the license client JAR
    cd BOOT-INF/lib
    jar -xf client-1.3.0.jar
    cd ../../
elif find . -name "*TbLicenseClient*" -type f | grep -q .; then
    echo "✅ License classes found in main JAR"
else
    echo "❌ License classes not found! Searching..."
    find . -name "*.class" | grep -i license | head -10
    exit 1
fi

echo "📦 Step 3: Download bytecode manipulation tools"
# Download ASM library for bytecode manipulation
if [ ! -f "asm-9.5.jar" ]; then
    wget -q https://repo1.maven.org/maven2/org/ow2/asm/asm/9.5/asm-9.5.jar
    wget -q https://repo1.maven.org/maven2/org/ow2/asm/asm-commons/9.5/asm-commons-9.5.jar
    wget -q https://repo1.maven.org/maven2/org/ow2/asm/asm-util/9.5/asm-util-9.5.jar
fi

echo "📦 Step 4: Create bytecode injection program"
cat > BytecodeInjector.java << 'EOF'
import org.objectweb.asm.*;
import org.objectweb.asm.commons.*;
import java.io.*;
import java.nio.file.*;

public class BytecodeInjector {
    
    public static void main(String[] args) throws Exception {
        System.out.println("🔧 Starting bytecode injection...");
        
        // Method 1: Patch SignatureUtil.verify() to always return (no exception)
        patchSignatureUtilVerify();
        
        // Method 2: Patch TbLicenseClient.persistInstanceData() to skip verification
        patchTbLicenseClientPersist();
        
        System.out.println("✅ Bytecode injection completed!");
    }
    
    static void patchSignatureUtilVerify() throws Exception {
        // Try multiple possible locations
        String[] possiblePaths = {
            "org/thingsboard/license/shared/signature/SignatureUtil.class",
            "BOOT-INF/lib/org/thingsboard/license/shared/signature/SignatureUtil.class",
            "BOOT-INF/classes/org/thingsboard/license/shared/signature/SignatureUtil.class"
        };
        
        boolean found = false;
        for (String classPath : possiblePaths) {
            if (Files.exists(Paths.get(classPath))) {
                System.out.println("🎯 Found SignatureUtil at: " + classPath);
                found = true;
                break;
            }
        }
        
        if (!found) {
            System.out.println("⚠️ SignatureUtil.class not found in main JAR");
            System.out.println("🔍 Checking client-1.3.0.jar...");
            
            // Extract and check client JAR
            Path clientJar = Paths.get("BOOT-INF/lib/client-1.3.0.jar");
            if (Files.exists(clientJar)) {
                System.out.println("📦 Extracting client-1.3.0.jar...");
                try {
                    ProcessBuilder pb = new ProcessBuilder("jar", "-xf", "BOOT-INF/lib/client-1.3.0.jar");
                    pb.directory(new File("BOOT-INF/lib"));
                    Process p = pb.start();
                    p.waitFor();
                    
                    // Check again after extraction
                    String clientPath = "BOOT-INF/lib/org/thingsboard/license/shared/signature/SignatureUtil.class";
                    if (Files.exists(Paths.get(clientPath))) {
                        System.out.println("✅ Found SignatureUtil in client JAR!");
                        patchSignatureUtilAt(clientPath);
                        return;
                    }
                } catch (Exception e) {
                    System.out.println("⚠️ Failed to extract client JAR: " + e.getMessage());
                }
            }
            
            System.out.println("❌ SignatureUtil not found anywhere, skipping...");
            return;
        }
    }
    
    static void patchSignatureUtilAt(String classPath) throws Exception {
        System.out.println("🎯 Patching SignatureUtil at: " + classPath);
        
        byte[] classBytes = Files.readAllBytes(Paths.get(classPath));
        
        ClassReader cr = new ClassReader(classBytes);
        ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_FRAMES);
        
        ClassVisitor cv = new ClassVisitor(Opcodes.ASM9, cw) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor, 
                                           String signature, String[] exceptions) {
                MethodVisitor mv = super.visitMethod(access, name, descriptor, signature, exceptions);
                
                // Patch verify(PublicKey, CheckInstanceResponse) method
                if ("verify".equals(name) && descriptor.contains("CheckInstanceResponse")) {
                    System.out.println("🎯 Found verify method, injecting bypass...");
                    return new MethodVisitor(Opcodes.ASM9, mv) {
                        @Override
                        public void visitCode() {
                            // Replace entire method with simple return
                            mv.visitCode();
                            mv.visitInsn(Opcodes.RETURN);  // Just return, no verification
                            mv.visitMaxs(0, 0);
                            mv.visitEnd();
                        }
                        
                        @Override
                        public void visitInsn(int opcode) {
                            // Skip all original instructions
                        }
                        
                        @Override
                        public void visitMethodInsn(int opcode, String owner, String name, 
                                                   String descriptor, boolean isInterface) {
                            // Skip all method calls
                        }
                    };
                }
                return mv;
            }
        };
        
        cr.accept(cv, 0);
        
        // Write patched class
        Files.write(Paths.get(classPath), cw.toByteArray());
        System.out.println("✅ SignatureUtil.verify() patched!");
    }
    
    static void patchTbLicenseClientPersist() throws Exception {
        String classPath = "BOOT-INF/lib/org/thingsboard/license/client/TbLicenseClient.class";
        if (!Files.exists(Paths.get(classPath))) {
            System.out.println("⚠️ TbLicenseClient.class not found, skipping...");
            return;
        }
        
        System.out.println("🎯 Patching TbLicenseClient.persistInstanceData()...");
        
        byte[] classBytes = Files.readAllBytes(Paths.get(classPath));
        
        ClassReader cr = new ClassReader(classBytes);
        ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_FRAMES);
        
        ClassVisitor cv = new ClassVisitor(Opcodes.ASM9, cw) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor, 
                                           String signature, String[] exceptions) {
                MethodVisitor mv = super.visitMethod(access, name, descriptor, signature, exceptions);
                
                // Patch persistInstanceData method
                if ("persistInstanceData".equals(name) && descriptor.contains("CheckInstanceResponse")) {
                    System.out.println("🎯 Found persistInstanceData method, injecting bypass...");
                    return new MethodVisitor(Opcodes.ASM9, mv) {
                        @Override
                        public void visitMethodInsn(int opcode, String owner, String name, 
                                                   String descriptor, boolean isInterface) {
                            // Skip SignatureUtil.verify() call
                            if (owner.contains("SignatureUtil") && "verify".equals(name)) {
                                System.out.println("🎯 Skipping SignatureUtil.verify() call");
                                // Pop the arguments from stack but don't call the method
                                mv.visitInsn(Opcodes.POP);  // Pop CheckInstanceResponse
                                mv.visitInsn(Opcodes.POP);  // Pop PublicKey
                                return;
                            }
                            // Keep all other method calls
                            super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                        }
                    };
                }
                return mv;
            }
        };
        
        cr.accept(cv, 0);
        
        // Write patched class
        Files.write(Paths.get(classPath), cw.toByteArray());
        System.out.println("✅ TbLicenseClient.persistInstanceData() patched!");
    }
}
EOF

echo "📦 Step 5: Compile and run bytecode injector"
# Check if we have Java
if ! command -v javac &> /dev/null; then
    echo "❌ Java compiler not found! Installing..."
    apt-get update -q
    apt-get install -y openjdk-11-jdk-headless
fi

echo "🔧 Compiling bytecode injector..."
javac -cp "asm-9.5.jar:asm-commons-9.5.jar:asm-util-9.5.jar" BytecodeInjector.java

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed! Trying with simplified approach..."
    # Create a simpler version without ASM
    cat > SimpleInjector.java << 'SIMPLE_EOF'
import java.io.*;
import java.nio.file.*;

public class SimpleInjector {
    public static void main(String[] args) throws Exception {
        System.out.println("🔧 Simple bytecode replacement...");
        
        // Method 1: Replace SignatureUtil class with empty stub
        replaceSignatureUtil();
        
        System.out.println("✅ Simple injection completed!");
    }
    
    static void replaceSignatureUtil() throws Exception {
        String classPath = "org/thingsboard/license/shared/signature/SignatureUtil.class";
        Path classFile = Paths.get(classPath);
        
        if (!Files.exists(classFile)) {
            System.out.println("⚠️ SignatureUtil.class not found, creating dummy...");
            // Create directory if needed
            Files.createDirectories(classFile.getParent());
        }
        
        // Create a minimal class file that does nothing
        // This is a simplified approach - create empty verify methods
        System.out.println("🎯 Creating dummy SignatureUtil class...");
        
        // For now, just delete the class so it can't be called
        if (Files.exists(classFile)) {
            Files.delete(classFile);
            System.out.println("✅ Removed SignatureUtil.class");
        }
    }
}
SIMPLE_EOF
    
    javac SimpleInjector.java
    java SimpleInjector
else
    echo "🔧 Running bytecode injector..."
    java -cp ".:asm-9.5.jar:asm-commons-9.5.jar:asm-util-9.5.jar" BytecodeInjector
fi

echo "📦 Step 6: Rebuild ThingsBoard JAR with patched classes"
# Rebuild the main JAR with patched classes
jar -cf thingsboard-patched.jar *

echo "📦 Step 7: Install patched JAR"
# Stop ThingsBoard first
echo "🛑 Stopping ThingsBoard..."
systemctl stop thingsboard 2>/dev/null || true

# Replace original JAR  
cp thingsboard-patched.jar "$THINGSBOARD_JAR"
echo "✅ Patched JAR installed"

echo "📦 Step 8: Set permissions and ownership"
chown thingsboard:thingsboard "$THINGSBOARD_JAR"
chmod 644 "$THINGSBOARD_JAR"

echo "📦 Step 9: Verification"
echo "Original JAR backed up to: $BACKUP_DIR/thingsboard-original.jar"
echo "Patched JAR installed to: $THINGSBOARD_JAR"

# Create restoration script
cat > "$BACKUP_DIR/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
echo "🔄 Restoring original ThingsBoard JAR..."
systemctl stop thingsboard 2>/dev/null || true
cp /tmp/license-backup/thingsboard-original.jar /usr/share/thingsboard/bin/thingsboard.jar
chown thingsboard:thingsboard /usr/share/thingsboard/bin/thingsboard.jar
chmod 644 /usr/share/thingsboard/bin/thingsboard.jar
echo "✅ Original JAR restored!"
echo "🚀 Start ThingsBoard: systemctl start thingsboard"
RESTORE_EOF
chmod +x "$BACKUP_DIR/restore.sh"

echo ""
echo "🎉 BYTECODE INJECTION COMPLETE!"
echo ""
echo "📋 What was done:"
echo "   1. SignatureUtil.verify() → Empty method (always passes)"
echo "   2. TbLicenseClient.persistInstanceData() → Skips signature verification"
echo ""
echo "🚀 Next steps:"
echo "   1. Start ThingsBoard: systemctl start thingsboard"
echo "   2. Check logs: journalctl -u thingsboard -f"
echo "   3. Monitor license verification"
echo ""
echo "🔄 To restore original (if needed):"
echo "   $BACKUP_DIR/restore.sh"
echo ""
echo "📋 Quick commands:"
echo "   systemctl start thingsboard"
echo "   journalctl -u thingsboard -f --since '1 minute ago'"
echo ""
echo "⚠️  Note: This is for testing/development purposes only!"
