#!/usr/bin/env bash
# =============================================================================
# 02b-inject-vscode-extensions.sh — CPC GALLOS / UAA
# Builds and injects VS Code extensions (CPH, Microsoft Python & Red Hat Java)
# into a huronOS system partition or mounted directory.
#
# Usage:
#   bash 02b-inject-vscode-extensions.sh [/dev/sdX1 | /path/to/mounted/HURONOS]
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TARGET="${1}"

# Extension definitions: MODULE_ID | DEFAULT_NAME | FALLBACK_URL | LOCAL_CANDIDATE_PATTERNS
EXT_CONFIGS=(
    "vsc-cph|competitive-programming-helper|https://github.com/agrawal-d/cph/releases/download/latest-vsix/competitive-programming-helper-2077.0.0.vsix|competitive-programming-helper-2077.0.0.vsix cph.vsix"
    "vsc-python|python|https://open-vsx.org/api/ms-python/python/2023.14.0/file/ms-python.python-2023.14.0.vsix|ms-python.python-2023.14.0.vsix ms-python.vsix python.vsix"
    "vsc-java|java|https://open-vsx.org/api/redhat/java/1.40.0/file/redhat.java-1.40.0.vsix|redhat.java-1.40.0.vsix redhat-java.vsix java.vsix"
)

TMP_LAB="/tmp/huronos-ext-lab-$$"
mkdir -p "$TMP_LAB"

cleanup_ext_lab() {
    rm -rf "$TMP_LAB" 2>/dev/null || true
}
trap cleanup_ext_lab EXIT INT TERM

# Determine target mount point or device
MOUNTED_BY_US=false
TARGET_DIR=""

if [ -z "$TARGET" ]; then
    ALREADY_MOUNTED=$(findmnt -n -o TARGET -S LABEL=HURONOS 2>/dev/null || true)
    if [ -n "$ALREADY_MOUNTED" ]; then
        TARGET_DIR="$ALREADY_MOUNTED"
        echo "Found mounted huronOS partition at: $TARGET_DIR"
    else
        echo "Searching for partition with label 'HURONOS'..."
        DEV_CANDIDATE=$(blkid -L HURONOS 2>/dev/null || true)
        if [ -n "$DEV_CANDIDATE" ]; then
            TARGET="$DEV_CANDIDATE"
            echo "Found huronOS partition: $TARGET"
        else
            echo "❌ Error: No target specified and no partition labeled 'HURONOS' found."
            echo "Usage: bash $0 [/dev/sdX1 | /path/to/mounted/huronOS]"
            exit 1
        fi
    fi
fi

if [ -z "$TARGET_DIR" ]; then
    if [ -b "$TARGET" ]; then
        EXISTING_MNT=$(findmnt -n -o TARGET "$TARGET" 2>/dev/null || true)
        if [ -n "$EXISTING_MNT" ]; then
            TARGET_DIR="$EXISTING_MNT"
            echo "Using existing mount point: $TARGET_DIR"
        elif command -v udisksctl &>/dev/null && UDISKS_OUT=$(udisksctl mount -b "$TARGET" 2>/dev/null); then
            TARGET_DIR=$(echo "$UDISKS_OUT" | grep -o 'at /.*' | sed 's/at //')
            echo "Mounted via udisksctl to: $TARGET_DIR"
            MOUNTED_BY_US=true
        else
            TARGET_DIR="/tmp/huronos-ext-mnt-$$"
            mkdir -p "$TARGET_DIR"
            echo "Mounting $TARGET to $TARGET_DIR..."
            mount "$TARGET" "$TARGET_DIR"
            MOUNTED_BY_US=true
        fi
    elif [ -d "$TARGET" ]; then
        TARGET_DIR="$TARGET"
    else
        echo "❌ Error: Target '$TARGET' is neither a block device nor a directory."
        exit 1
    fi
fi

cleanup() {
    cleanup_ext_lab
    if [ "$MOUNTED_BY_US" = true ]; then
        echo "Syncing and unmounting $TARGET_DIR..."
        sync
        if [ -b "$TARGET" ] && command -v udisksctl &>/dev/null && mountpoint -q "$TARGET_DIR" 2>/dev/null; then
            udisksctl unmount -b "$TARGET" 2>/dev/null || umount "$TARGET_DIR" 2>/dev/null || true
        elif mountpoint -q "$TARGET_DIR" 2>/dev/null; then
            umount "$TARGET_DIR" || true
        fi
        rm -rf "/tmp/huronos-ext-mnt-$$" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Check huronOS structure
if [ ! -d "$TARGET_DIR/huronOS" ] && [ ! -d "$TARGET_DIR/base" ]; then
    echo "❌ Error: '$TARGET_DIR' does not appear to be a valid huronOS system directory."
    exit 1
fi

BASE_DIR="$TARGET_DIR/huronOS/base"
SOFTWARE_PROG_DIR="$TARGET_DIR/huronOS/software/programming"
CHECKSUMS_FILE="$TARGET_DIR/checksums"

if [ ! -d "$BASE_DIR" ] && [ -d "$TARGET_DIR/base" ]; then
    BASE_DIR="$TARGET_DIR/base"
fi
if [ ! -d "$SOFTWARE_PROG_DIR" ] && [ -d "$TARGET_DIR/software/programming" ]; then
    SOFTWARE_PROG_DIR="$TARGET_DIR/software/programming"
fi
if [ ! -f "$CHECKSUMS_FILE" ] && [ -f "$TARGET_DIR/../checksums" ]; then
    CHECKSUMS_FILE="$TARGET_DIR/../checksums"
fi

echo "Target base directory: $BASE_DIR"
echo "Target programming software directory: $SOFTWARE_PROG_DIR"
echo ""

# Extract existing 05-custom.hsl layer
CUSTOM_HSL="$BASE_DIR/05-custom.hsl"
LAYER_ROOT="$TMP_LAB/squashfs-layer"
mkdir -p "$LAYER_ROOT"

if [ -f "$CUSTOM_HSL" ]; then
    echo "Extracting existing 05-custom.hsl layer..."
    unsquashfs -d "$LAYER_ROOT" -f "$CUSTOM_HSL" >/dev/null 2>&1 || true
fi

mkdir -p "$LAYER_ROOT/opt/codium/contestant/extensions/ids"
mkdir -p "$LAYER_ROOT/opt/codium/vsix"
mkdir -p "$LAYER_ROOT/home/contestant/vsix"
mkdir -p "$LAYER_ROOT/usr/local/bin"
mkdir -p "$LAYER_ROOT/etc/hmm"
mkdir -p "$LAYER_ROOT/etc/hsync"

# Extract base ISO vsc-cpptools if present in software directory
if [ -d "$SOFTWARE_PROG_DIR" ] && [ -f "$SOFTWARE_PROG_DIR/vsc-cpptools.hsm" ]; then
    echo "Pre-extracting base C/C++ Tools extension into 05-custom.hsl..."
    CPP_UNPACK="$TMP_LAB/unpack_base_cpptools"
    mkdir -p "$CPP_UNPACK"
    unsquashfs -d "$CPP_UNPACK" -f "$SOFTWARE_PROG_DIR/vsc-cpptools.hsm" >/dev/null 2>&1 || true
    if [ -d "$CPP_UNPACK/opt/codium/contestant/extensions" ]; then
        cp -rf "$CPP_UNPACK/opt/codium/contestant/extensions/"* "$LAYER_ROOT/opt/codium/contestant/extensions/" 2>/dev/null || true
    fi
fi

declare -a GENERATED_HSMS=()

for ext_spec in "${EXT_CONFIGS[@]}"; do
    IFS='|' read -r MOD_ID DEFAULT_EXT_NAME EXT_URL PATTERNS <<< "$ext_spec"

    echo "----------------------------------------------------"
    echo "Processing extension module: $MOD_ID ($DEFAULT_EXT_NAME)"

    LOCAL_VSIX=""
    for pat in $PATTERNS; do
        if [ -f "$SCRIPT_DIR/$pat" ]; then
            LOCAL_VSIX="$SCRIPT_DIR/$pat"
            break
        fi
    done

    if [ -z "$LOCAL_VSIX" ]; then
        FOUND=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*$DEFAULT_EXT_NAME*.vsix" 2>/dev/null | head -n 1 || true)
        if [ -n "$FOUND" ] && [ -f "$FOUND" ]; then
            LOCAL_VSIX="$FOUND"
        fi
    fi

    if [ -z "$LOCAL_VSIX" ] || [ ! -f "$LOCAL_VSIX" ]; then
        echo "Downloading $MOD_ID VSIX from $EXT_URL..."
        LOCAL_VSIX="$TMP_LAB/${MOD_ID}.vsix"
        curl -fsSL --retry 3 -o "$LOCAL_VSIX" "$EXT_URL"
    fi

    echo "✓ Using VSIX: $LOCAL_VSIX ($(sha256sum "$LOCAL_VSIX" | awk '{print $1}'))"

    # Copy raw VSIX package for offline installation
    VSIX_BASENAME="$(basename "$LOCAL_VSIX")"
    cp -f "$LOCAL_VSIX" "$LAYER_ROOT/opt/codium/vsix/$VSIX_BASENAME"
    cp -f "$LOCAL_VSIX" "$LAYER_ROOT/home/contestant/vsix/$VSIX_BASENAME"

    UNPACK_DIR="$TMP_LAB/unpack_$MOD_ID"
    mkdir -p "$UNPACK_DIR"
    unzip -q "$LOCAL_VSIX" -d "$UNPACK_DIR"

    PKG_JSON="$UNPACK_DIR/extension/package.json"
    RAW_VERSION=$(grep -o '"version": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "1.0.0")
    RAW_PUBLISHER=$(grep -o '"publisher": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "custom")
    RAW_NAME=$(grep -o '"name": *"[^"]*"' "$PKG_JSON" 2>/dev/null | head -n 1 | cut -d'"' -f4 || echo "$DEFAULT_EXT_NAME")

    [ -z "$RAW_VERSION" ] && RAW_VERSION="1.0.0"
    [ -z "$RAW_PUBLISHER" ] && RAW_PUBLISHER="custom"
    [ -z "$RAW_NAME" ] && RAW_NAME="$DEFAULT_EXT_NAME"

    EXT_VERSION="$RAW_VERSION"
    EXT_PUBLISHER=$(echo "$RAW_PUBLISHER" | tr '[:upper:]' '[:lower:]')
    EXT_NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]')

    FULL_EXT_ID="${EXT_PUBLISHER}.${EXT_NAME}"
    EXT_DIR_NAME="${FULL_EXT_ID}-${EXT_VERSION}"

    echo "  Extension ID: $FULL_EXT_ID (version $EXT_VERSION)"
    echo "  Directory:    $EXT_DIR_NAME"

    # Prepare extension tree for 05-custom.hsl and standalone .hsm
    EXT_ROOT="$TMP_LAB/root_$MOD_ID"
    mkdir -p "$EXT_ROOT/opt/codium/contestant/extensions/ids"
    mkdir -p "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME"

    cp -rf "$UNPACK_DIR/extension/"* "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
    if [ -f "$UNPACK_DIR/extension.vsixmanifest" ]; then
        cp -f "$UNPACK_DIR/extension.vsixmanifest" "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/.vsixmanifest"
    fi

    NOW_MS=$(date +%s000)
    cat << EOF > "$EXT_ROOT/opt/codium/contestant/extensions/ids/${MOD_ID}.json"
{"identifier":{"id":"${FULL_EXT_ID}"},"version":"${EXT_VERSION}","location":{"\$mid":1,"fsPath":"/opt/codium/contestant/extensions/${EXT_DIR_NAME}","external":"file:///opt/codium/contestant/extensions/${EXT_DIR_NAME}","path":"/opt/codium/contestant/extensions/${EXT_DIR_NAME}","scheme":"file"},"relativeLocation":"${EXT_DIR_NAME}","metadata":{"installedTimestamp":${NOW_MS}}}
EOF

    # hsync mounts this .hsm above 05-custom.hsl.  The Codium wrapper writes
    # extensions.json at every start, so its topmost extensions directory must
    # remain writable by the unprivileged contestant user as well.
    chmod -R 777 "$EXT_ROOT/opt/codium/contestant/extensions"

    # Copy into layer root
    mkdir -p "$LAYER_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME"
    cp -rf "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"* "$LAYER_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
    if [ -f "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/.vsixmanifest" ]; then
        cp -f "$EXT_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/.vsixmanifest" "$LAYER_ROOT/opt/codium/contestant/extensions/$EXT_DIR_NAME/"
    fi
    cp -f "$EXT_ROOT/opt/codium/contestant/extensions/ids/${MOD_ID}.json" "$LAYER_ROOT/opt/codium/contestant/extensions/ids/${MOD_ID}.json"

    # Build standalone .hsm module
    if [ -d "$SOFTWARE_PROG_DIR" ]; then
        HSM_FILE="$SOFTWARE_PROG_DIR/${MOD_ID}.hsm"
        echo "  Building standalone module: $HSM_FILE"
        TMP_HSM="$TMP_LAB/${MOD_ID}.hsm"
        rm -f "$TMP_HSM"
        NPROCS=$(nproc 2>/dev/null || echo 4)
        mksquashfs "$EXT_ROOT" "$TMP_HSM" -comp xz -b 256K -processors "$NPROCS" -always-use-fragments -noappend >/dev/null
        cp -f "$TMP_HSM" "$HSM_FILE"
        GENERATED_HSMS+=("${MOD_ID}.hsm")
    fi
done

# Pre-compile extensions.json in custom layer
echo "Compiling extensions.json registry for VSCodium..."
EXT_JSON_FILE="$LAYER_ROOT/opt/codium/contestant/extensions/extensions.json"
echo -n "[" > "$EXT_JSON_FILE"
FIRST_ENTRY=true
for id_file in "$LAYER_ROOT/opt/codium/contestant/extensions/ids/"*.json; do
    if [ -f "$id_file" ]; then
        if [ "$FIRST_ENTRY" = true ]; then
            FIRST_ENTRY=false
        else
            echo -n "," >> "$EXT_JSON_FILE"
        fi
        tr -d '\n' < "$id_file" >> "$EXT_JSON_FILE"
    fi
done
echo "]" >> "$EXT_JSON_FILE"

# Provide offline VSIX installation helper script
cat << 'EOF' > "$LAYER_ROOT/usr/local/bin/install-vsix-extensions"
#!/bin/bash
# install-vsix-extensions — Install/reinstall all offline VSIX packages into Codium
set -e

EXT_DIR="/opt/codium/contestant/extensions"
mkdir -p "$EXT_DIR" 2>/dev/null || true
echo "Installing offline VSIX extensions into $EXT_DIR..."
for vsix in /opt/codium/vsix/*.vsix /home/contestant/vsix/*.vsix; do
    if [ -f "$vsix" ]; then
        echo "  -> Installing $(basename "$vsix")..."
        /usr/share/codium/bin/codium --extensions-dir "$EXT_DIR" --install-extension "$vsix"
    fi
done
echo "✓ All offline VSIX extensions processed."
EOF
chmod 755 "$LAYER_ROOT/usr/local/bin/install-vsix-extensions"

# Register extensions in huronOS module lists
if [ ! -f "$LAYER_ROOT/etc/hmm/any" ]; then
    cat << 'EOF' > "$LAYER_ROOT/etc/hmm/any"
HURONDIR=/run/initramfs/memory/system/huronOS/software/
debuggers/ddd                               false
debuggers/gdb                               false
debuggers/valgrind                          false
debuggers/visualvm                          false
internet/chromium                           false
internet/crow                               false
internet/firefox                            false
langs/dotnet                                false
langs/g++                                   false
langs/gcc                                   false
langs/javac                                 false
langs/kotlinc                               false
langs/mono                                  false
langs/pypy3                                 false
langs/python3                               false
langs/ruby                                  false
tools/byobu                                 false
tools/konsole                               false
tools/midnight-commander                    false
programming/atom                            false
programming/clion                           false
programming/codeblocks                      false
programming/eclipse                         false
programming/emacs                           false
programming/geany                           false
programming/gedit                           false
programming/gvim                            false
programming/intellij                        false
programming/joe                             false
programming/kate                            false
programming/kdevelop                        false
programming/neovim                          false
programming/pycharm                         false
programming/rider                           false
programming/sublime                         false
programming/vim                             false
programming/vscode                          false
programming/vsc-clangd                      false
programming/vsc-cpp-compile-run             false
programming/vsc-cpptools                    false
programming/vsc-intellij-idea-keybindings   false
programming/vsc-vscodevim                   false
programming/vsc-cph                         false
programming/vsc-python                      false
programming/vsc-java                        false
EOF
else
    for mod in "programming/vsc-cph" "programming/vsc-python" "programming/vsc-java"; do
        if ! grep -q "$mod" "$LAYER_ROOT/etc/hmm/any"; then
            printf "%-43s false\n" "$mod" >> "$LAYER_ROOT/etc/hmm/any"
        fi
    done
fi

if [ ! -f "$LAYER_ROOT/etc/hsync/all_software" ]; then
    cat << 'EOF' > "$LAYER_ROOT/etc/hsync/all_software"
debuggers/ddd
debuggers/gdb
debuggers/valgrind
debuggers/visualvm
internet/chromium
internet/crow
internet/firefox
langs/dotnet
langs/g++
langs/gcc
langs/javac
langs/kotlinc
langs/mono
langs/pypy3
langs/python3
langs/ruby
tools/byobu
tools/konsole
tools/midnight-commander
programming/atom
programming/clion
programming/codeblocks
programming/eclipse
programming/emacs
programming/geany
programming/gedit
programming/gvim
programming/intellij
programming/joe
programming/kate
programming/kdevelop
programming/neovim
programming/pycharm
programming/rider
programming/sublime
programming/vim
programming/vscode
programming/vsc-clangd
programming/vsc-cpp-compile-run
programming/vsc-cpptools
programming/vsc-intellij-idea-keybindings
programming/vsc-vscodevim
programming/vsc-cph
programming/vsc-python
programming/vsc-java
EOF
else
    for mod in "programming/vsc-cph" "programming/vsc-python" "programming/vsc-java"; do
        if ! grep -q "$mod" "$LAYER_ROOT/etc/hsync/all_software"; then
            echo "$mod" >> "$LAYER_ROOT/etc/hsync/all_software"
        fi
    done
fi

# Ensure permissive access for contestant user
chmod -R 777 "$LAYER_ROOT/opt/codium/contestant/extensions" 2>/dev/null || true
chmod -R 755 "$LAYER_ROOT/opt/codium/vsix" 2>/dev/null || true
chmod -R 777 "$LAYER_ROOT/home/contestant/vsix" 2>/dev/null || true

echo "----------------------------------------------------"
echo "Rebuilding 05-custom.hsl squashfs layer..."
rm -f "$TMP_LAB/05-custom.hsl"
NPROCS=$(nproc 2>/dev/null || echo 4)
mksquashfs "$LAYER_ROOT" "$TMP_LAB/05-custom.hsl" -comp xz -b 1024K -processors "$NPROCS" -always-use-fragments -noappend >/dev/null
cp -f "$TMP_LAB/05-custom.hsl" "$CUSTOM_HSL"
echo "✓ Updated $CUSTOM_HSL with full extension suite."

# Update checksums file if present
if [ -f "$CHECKSUMS_FILE" ]; then
    echo "Updating $CHECKSUMS_FILE with new checksums..."
    CURRENT_PWD="$(pwd)"
    cd "$TARGET_DIR"
    
    NEW_HSL_CHECKSUM=$(sha256sum huronOS/base/05-custom.hsl 2>/dev/null || sha256sum base/05-custom.hsl 2>/dev/null || true)
    if [ -n "$NEW_HSL_CHECKSUM" ]; then
        if grep -q "05-custom.hsl" "$CHECKSUMS_FILE"; then
            sed -i "s|.*05-custom.hsl.*|$NEW_HSL_CHECKSUM|" "$CHECKSUMS_FILE"
        else
            echo "$NEW_HSL_CHECKSUM" >> "$CHECKSUMS_FILE"
        fi
    fi

    for hsm in "${GENERATED_HSMS[@]}"; do
        HSM_PATH="huronOS/software/programming/$hsm"
        [ ! -f "$HSM_PATH" ] && HSM_PATH="software/programming/$hsm"
        if [ -f "$HSM_PATH" ]; then
            NEW_HSM_CHECKSUM=$(sha256sum "$HSM_PATH")
            if grep -q "$hsm" "$CHECKSUMS_FILE"; then
                sed -i "s|.*$hsm.*|$NEW_HSM_CHECKSUM|" "$CHECKSUMS_FILE"
            else
                echo "$NEW_HSM_CHECKSUM" >> "$CHECKSUMS_FILE"
            fi
        fi
    done

    cd "$CURRENT_PWD"
    echo "✓ Checksums updated."
fi

sync
echo ""
echo "============================================="
echo " ✓ VS Code extensions successfully injected!"
echo " Extensions ready in Codium / huronOS:"
echo "   - ms-vscode.cpptools (C/C++ Tools)"
echo "   - DivyanshuAgrawal.competitive-programming-helper (CPH)"
echo "   - ms-python.python (Microsoft Python)"
echo "   - redhat.java (Language Support for Java by Red Hat)"
echo "============================================="
