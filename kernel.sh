#!/bin/bash
set -e

# --- Configuration ---
# Path disesuaikan dengan build.yml ($HOME/clang)
TOOLCHAIN_PATH=$HOME/clang/bin
export KBUILD_BUILD_USER="bhazheng"
export KBUILD_BUILD_HOST="Akbar-Lucky"
export ARCH=arm64
export SUBARCH=arm64
export PATH="$TOOLCHAIN_PATH:$PATH"

GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD)
OUT_DIR="out"
ANYKERNEL_DIR="anykernel"

# Determine if KSU is enabled (Hanya untuk penamaan file ZIP dan KPM Patch)
KSU_ENABLE=0
KSU_ZIP_STR="NoKSU"
if [ "$1" == "ksu" ]; then
    KSU_ENABLE=1
    KSU_ZIP_STR="KSU-SuSFS-v2.0.0"
fi

# Verify toolchain
if ! command -v clang >/dev/null 2>&1; then
    echo "Error: Clang not found at $TOOLCHAIN_PATH"
    exit 1
fi

echo "Cleaning old builds..."
# PENTING: Jangan menghapus $OUT_DIR karena .config sudah digenerate oleh GitHub Actions!
rm -rf $ANYKERNEL_DIR *.zip

echo "Cloning AnyKernel3..."
git clone https://github.com/aqbaloch6205/AnyKernel3 -b kona --single-branch --depth=1 $ANYKERNEL_DIR

echo "Starting Build for Arabella-V60 (KSU=$KSU_ENABLE)..."

# --- Make Arguments ---
MAKE_ARGS=(
    O="$OUT_DIR"
    ARCH=arm64
    CC=clang
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    LLVM=1
    LLVM_IAS=1
    KCFLAGS="-Wno-error -Wno-error=incompatible-pointer-types"
)

# 3. Compile Kernel
# Kita tambahkan target 'dtbo.img' karena V60 memerlukannya.
# Fallback ke 'Image' saja jika source tidak support dtbo (jarang terjadi di SD865).
echo "Compiling Kernel & DTBO..."
make "${MAKE_ARGS[@]}" -j$(nproc) Image dtbo.img || make "${MAKE_ARGS[@]}" -j$(nproc) Image

# 4. Handle Outputs
if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
    echo "Kernel compiled successfully."
    
    # Merge DTBs
    # Menggunakan path '/dts/vendor' agar lebih spesifik dan 'sort' agar urutan deterministik
    echo "Merging DTBs..."
    find $OUT_DIR/arch/arm64/boot/dts -name '*.dtb' | sort | xargs cat > $OUT_DIR/arch/arm64/boot/dtb

    # KPM Support Patch (Xiaomi Dev Method) - Binary Patching pada Image
    if [ $KSU_ENABLE -eq 1 ]; then
        echo "Applying KPM support patch..."
        cd $OUT_DIR/arch/arm64/boot/
        wget https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.5/patch_linux
        chmod +x patch_linux
        ./patch_linux 
        rm Image
        mv oImage Image
        cd -
    fi

    # Prepare AnyKernel folder
    mkdir -p $ANYKERNEL_DIR/kernels/
    cp $OUT_DIR/arch/arm64/boot/Image $ANYKERNEL_DIR/kernels/
    cp $OUT_DIR/arch/arm64/boot/dtb $ANYKERNEL_DIR/kernels/
    
    # Copy dtbo.img jika berhasil dibuat
    if [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]; then
        echo "Found dtbo.img, copying..."
        cp $OUT_DIR/arch/arm64/boot/dtbo.img $ANYKERNEL_DIR/kernels/
    fi

    # Create Flashable Zip
    cd $ANYKERNEL_DIR
    ZIP_NAME="Arabella-V60-${KSU_ZIP_STR}-$(date +%Y%m%d)-${GIT_COMMIT_ID}.zip"
    zip -r9 "../$ZIP_NAME" ./* -x .git .gitignore out/
    cd ..
    
    echo "Build Complete: $ZIP_NAME"
else
    echo "Build Failed: Image not found."
    exit 1
fi
