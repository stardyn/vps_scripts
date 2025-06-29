#!/bin/bash

# ThingsBoard License Bypass - Bytecode Injection
# This script modifies the license verification bytecode

#apt-get install -y dos2unix && cd /tmp && wget https://raw.githubusercontent.com/stardyn/vps_scripts/main/thingsboard_bytecode_injection.sh && dos2unix thingsboard_bytecode_injection.sh && chmod +x thingsboard_bytecode_injection.sh && ./thingsboard_bytecode_injection.sh

set -e

echo "🔧 ThingsBoard License Bytecode Injection"
echo "========================================"

# Configuration
THINGSBOARD_DIR="/tmp/thingsboard-analysis"
INJECTION_DIR="/tmp/license-injection"
BACKUP_DIR="/tmp/license-backup"

echo "📦 Step 1: Setup injection environment"
mkdir -p "$INJECTION_DIR"
mkdir -p "$BACKUP_DIR"
cd "$INJECTION_DIR"

echo "📦 Step 2: Extract and backup original JARs"
# Find license client JAR
LICENSE_JAR=$(find "$THINGSBOARD_DIR" -name "*client*.jar" -type f | head -1)
echo "Found license JAR: $LICENSE_JAR"

# Backup original
cp "$LICENSE_JAR" "$BACKUP_DIR/client-original.jar"

# Extract JAR
jar -xf "$LICENSE_JAR"

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
        String classPath = "org/thingsboard/license/shared/signature/SignatureUtil.class";
        if (!Files.exists(Paths.get(classPath))) {
            System.out.println("⚠️ SignatureUtil.class not found, skipping...");
            return;
        }
        
        System.out.println("🎯 Patching SignatureUtil.verify()...");
        
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
        String classPath = "org/thingsboard/license/client/TbLicenseClient.class";
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
                            if ("SignatureUtil".equals(owner.substring(owner.lastIndexOf('/') + 1)) && 
                                "verify".equals(name)) {
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
javac -cp "asm-9.5.jar:asm-commons-9.5.jar:asm-util-9.5.jar" BytecodeInjector.java
java -cp ".:asm-9.5.jar:asm-commons-9.5.jar:asm-util-9.5.jar" BytecodeInjector

echo "📦 Step 6: Rebuild JAR with patched classes"
jar -cf client-patched.jar *

echo "📦 Step 7: Replace original JAR"
cp client-patched.jar "$LICENSE_JAR"

echo "📦 Step 8: Verification"
echo "Original JAR backed up to: $BACKUP_DIR/client-original.jar"
echo "Patched JAR installed to: $LICENSE_JAR"

# Create restoration script
cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
echo "🔄 Restoring original ThingsBoard license JAR..."
LICENSE_JAR=$(find /tmp/thingsboard-analysis -name "*client*.jar" -type f | head -1)
cp /tmp/license-backup/client-original.jar "$LICENSE_JAR"
echo "✅ Original JAR restored!"
EOF
chmod +x "$BACKUP_DIR/restore.sh"

echo ""
echo "🎉 BYTECODE INJECTION COMPLETE!"
echo ""
echo "📋 What was done:"
echo "   1. SignatureUtil.verify() → Empty method (always passes)"
echo "   2. TbLicenseClient.persistInstanceData() → Skips signature verification"
echo ""
echo "🚀 Next steps:"
echo "   1. Restart ThingsBoard: systemctl restart thingsboard"
echo "   2. Check if license verification passes"
echo ""
echo "🔄 To restore original (if needed):"
echo "   $BACKUP_DIR/restore.sh"
echo ""
echo "⚠️  Note: This is for testing/development purposes only!"
