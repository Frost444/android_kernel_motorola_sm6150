#!/usr/bin/env bash
#
# Cybertron Kernel Build Script (cyber.sh)
# Targets: Motorola SM6150 (One Fusion+ [liber], G40/G60 [hanoip], G9 Plus [odessa])
# Base: Linux 4.14.357-openela
# Maintainer: cool585 (DhineshCool)
#

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Dynamically determine Script and Kernel Root Directories
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "${SCRIPT_SOURCE}" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
    SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
    [[ ${SCRIPT_SOURCE} != /* ]] && SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"

# Find Kernel Root (directory containing Makefile and Kconfig)
if [ -f "${SCRIPT_DIR}/Makefile" ] && [ -f "${SCRIPT_DIR}/Kconfig" ]; then
    KERNEL_ROOT="${SCRIPT_DIR}"
elif [ -f "$(pwd)/Makefile" ] && [ -f "$(pwd)/Kconfig" ]; then
    KERNEL_ROOT="$(pwd)"
else
    SEARCH_DIR="${SCRIPT_DIR}"
    while [ "${SEARCH_DIR}" != "/" ] && [ -n "${SEARCH_DIR}" ]; do
        if [ -f "${SEARCH_DIR}/Makefile" ] && [ -f "${SEARCH_DIR}/Kconfig" ]; then
            KERNEL_ROOT="${SEARCH_DIR}"
            break
        fi
        SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
    done
fi
KERNEL_ROOT="${KERNEL_ROOT:-$(pwd)}"

if [ ! -f "${KERNEL_ROOT}/Makefile" ] || [ ! -f "${KERNEL_ROOT}/Kconfig" ]; then
    echo -e "${RED}[ERROR]: Valid Linux kernel root not found (missing Makefile or Kconfig in ${KERNEL_ROOT})!${NC}"
    exit 1
fi

DEVICE="odessa"
CLEAN_BUILD=0
MENUCONFIG=0
UPDATE_TC=0

show_help() {
    echo -e "${BOLD}Usage:${NC} $0 [DEVICE] [OPTIONS]"
    echo ""
    echo -e "${BOLD}Devices:${NC}"
    echo "  liber     - Motorola One Fusion+ (vendor/liber_defconfig) [default]"
    echo "  hanoip    - Motorola Moto G40/G60 (vendor/hanoip_defconfig)"
    echo "  odessa    - Motorola Moto G9 Plus (vendor/odessa_defconfig)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -c, --clean             Clean out directory before building"
    echo "  -m, --menuconfig        Launch kernel menuconfig interface"
    echo "  -u, --update-toolchain  Update Neutron-Clang toolchain via antman"
    echo "  -h, --help              Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 liber"
    echo "  $0 hanoip --clean"
    echo "  $0 liber -m"
    echo "  $0 odessa --clean"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        liber|hanoip|odessa)
            DEVICE="$1"
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=1
            shift
            ;;
        -m|--menuconfig)
            MENUCONFIG=1
            shift
            ;;
        -u|--update-toolchain)
            UPDATE_TC=1
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${YELLOW}[WARN]: Unknown argument '$1'. Defaulting to device '$DEVICE'.${NC}"
            shift
            ;;
    esac
done

case "${DEVICE}" in
    liber)
        DEFCONFIG="vendor/liber_defconfig"
        DEVICE_NAME="Motorola One Fusion+ (liber)"
        ZIP_NAME_DEFAULT="anykernel"
        ;;
    hanoip)
        DEFCONFIG="vendor/hanoip_defconfig"
        DEVICE_NAME="Motorola Moto G40/G60 (hanoip)"
        ZIP_NAME_DEFAULT="anykernel-hanoip"
        ;;
    odessa)
        DEFCONFIG="vendor/odessa_defconfig"
        DEVICE_NAME="Motorola Moto G9 Plus (odessa)"
        ZIP_NAME_DEFAULT="anykernel-odessa"
        ;;
    *)
        echo -e "${RED}[ERROR]: Unsupported device: ${DEVICE}${NC}"
        exit 1
        ;;
esac

PARENT_DIR="$(cd "${KERNEL_ROOT}/.." && pwd)"
if [ -z "${ZIP_DIR}" ]; then
    if [ "${DEVICE}" = "odessa" ] && [ -d "${KERNEL_ROOT}/Cybertron" ]; then
        ZIP_DIR="${KERNEL_ROOT}/Cybertron"
    elif [ -d "${PARENT_DIR}/${ZIP_NAME_DEFAULT}" ]; then
        ZIP_DIR="${PARENT_DIR}/${ZIP_NAME_DEFAULT}"
    elif [ -d "${KERNEL_ROOT}/${ZIP_NAME_DEFAULT}" ]; then
        ZIP_DIR="${KERNEL_ROOT}/${ZIP_NAME_DEFAULT}"
    elif [ "${DEVICE}" != "odessa" ] && [ -d "${PARENT_DIR}/anykernel" ]; then
        ZIP_DIR="${PARENT_DIR}/anykernel"
    elif [ -d "${HOME}/${ZIP_NAME_DEFAULT}" ]; then
        ZIP_DIR="${HOME}/${ZIP_NAME_DEFAULT}"
    else
        ZIP_DIR="${PARENT_DIR}/${ZIP_NAME_DEFAULT}"
    fi
fi

OUT_DIR="${KERNEL_ROOT}/out"
BUILD_DIR="${KERNEL_ROOT}/build"
if [ "${DEVICE}" = "odessa" ]; then
    OUT_DIR="${KERNEL_ROOT}/out-odessa"
    BUILD_DIR="${BUILD_DIR}/odessa"
fi

export KBUILD_BUILD_USER="cool585"
export KBUILD_BUILD_HOST="cybertron"
export ARCH=arm64
export SUBARCH=arm64

echo -e "${CYAN}${BOLD}"
echo "=================================================="
echo "          Cybertron Kernel Builder (v18)          "
echo "=================================================="
echo -e "${NC}"
echo -e " Target Device : ${GREEN}${BOLD}${DEVICE_NAME}${NC}"
echo -e " Defconfig     : ${GREEN}${DEFCONFIG}${NC}"
echo -e " Kernel Root   : ${KERNEL_ROOT}"
echo -e " Out Directory : ${OUT_DIR}"
echo -e " AnyKernel Dir : ${ZIP_DIR}"
echo -e " Build Threads : $(nproc --all)"
echo "--------------------------------------------------"

if [ -d "${KERNEL_ROOT}/.git" ]; then
    echo -e "${BLUE}[INFO]: Updating git submodules...${NC}"
    git -C "${KERNEL_ROOT}" submodule update --init --recursive &>/dev/null || true
fi

REQ_FILE="/tmp/.cybertron_kernel_requirements"
if [ ! -f "${REQ_FILE}" ]; then
    echo -e "${BLUE}[INFO]: Checking build requirements...${NC}"
    PKGS=(
        git device-tree-compiler lz4 xz-utils zlib1g-dev gcc g++ python3
        python-is-python3 p7zip-full build-essential zip curl libc6-dev
        libncurses-dev make bc grep tofrodos libxml2-utils xsltproc
        cpio kmod openssl libelf-dev libssl-dev zstd
    )
    if command -v apt-get &>/dev/null && sudo -n true 2>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends "${PKGS[@]}" || true
    fi
    touch "${REQ_FILE}" 2>/dev/null || true
fi

mkdir -p "${OUT_DIR}" "${BUILD_DIR}" "${HOME}/toolchains"

if [ -d "${PARENT_DIR}/toolchains/neutron-clang" ]; then
    TOOLCHAINS_ROOT="${PARENT_DIR}/toolchains"
else
    TOOLCHAINS_ROOT="${TOOLCHAIN_DIR:-${HOME}/toolchains}"
fi

NEUTRON_DIR="${NEUTRON_DIR:-${TOOLCHAINS_ROOT}/neutron-clang}"
if [ ! -d "${NEUTRON_DIR}" ] || [ ! -f "${NEUTRON_DIR}/bin/clang" ]; then
    echo -e "${YELLOW}[INFO]: Initializing Neutron-Clang Toolchain via antman...${NC}"
    mkdir -p "${NEUTRON_DIR}"
    cd "${NEUTRON_DIR}"
    curl -sSLo antman "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman"
    chmod +x antman
    if ! ./antman -S --noconfirm; then
        echo -e "${YELLOW}[WARN]: Latest tag failed, trying pinned tag 05082026...${NC}"
        ./antman -S --tag=05082026 --noconfirm
    fi
    ./antman --patch=glibc || true
    cd "${KERNEL_ROOT}"
elif [ "${UPDATE_TC}" -eq 1 ]; then
    echo -e "${YELLOW}[INFO]: Updating Neutron-Clang Toolchain...${NC}"
    cd "${NEUTRON_DIR}"
    ./antman -u --noconfirm || true
    ./antman --patch=glibc || true
    cd "${KERNEL_ROOT}"
fi

GCC_DIR="${GCC_DIR:-${TOOLCHAINS_ROOT}/gcc/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu}"
if [ ! -d "${GCC_DIR}" ] || [ ! -f "${GCC_DIR}/bin/aarch64-none-linux-gnu-gcc" ]; then
    echo -e "${YELLOW}[INFO]: Downloading ARM GNU Toolchain 14.2.rel1...${NC}"
    mkdir -p "${TOOLCHAINS_ROOT}/gcc"
    cd "${TOOLCHAINS_ROOT}/gcc"
    curl -LO "https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz"
    tar -xf arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
    rm -f arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
    cd "${KERNEL_ROOT}"
fi

export PATH="${TOOLCHAINS_ROOT}/bin:${NEUTRON_DIR}/bin:${GCC_DIR}/bin:${PATH}"
export NEUTRON_PATH="${NEUTRON_DIR}/bin"
export LD_LIBRARY_PATH="${NEUTRON_DIR}/lib:${LD_LIBRARY_PATH}"

BUILD_CROSS_COMPILE="${GCC_DIR}/bin/aarch64-none-linux-gnu-"

if command -v ccache &>/dev/null; then
    CC_BIN="ccache ${NEUTRON_PATH}/clang"
    export CCACHE_DIR="${HOME}/.ccache"
    export CCACHE_EXEC="$(command -v ccache)"
    export USE_CCACHE=1
    echo -e "${BLUE}[INFO]: Using ccache for accelerated builds.${NC}"
else
    CC_BIN="${NEUTRON_PATH}/clang"
fi

BUILD_OPTIONS=(
    -C "${KERNEL_ROOT}"
    O="${OUT_DIR}"
    -j"$(nproc --all)"
    ARCH=arm64
    CROSS_COMPILE="${BUILD_CROSS_COMPILE}"
    CC="${CC_BIN}"
    CLANG_TRIPLE=aarch64-linux-gnu-
    LLVM=1
    LLVM_IAS=1
    AR="${NEUTRON_PATH}/llvm-ar"
    NM="${NEUTRON_PATH}/llvm-nm"
    LD="${NEUTRON_PATH}/ld.lld"
    STRIP="${NEUTRON_PATH}/llvm-strip"
    OBJCOPY="${NEUTRON_PATH}/llvm-objcopy"
    OBJDUMP="${NEUTRON_PATH}/llvm-objdump"
    READELF="${NEUTRON_PATH}/llvm-readelf"
    HOSTCC="${NEUTRON_PATH}/clang"
    HOSTCXX="${NEUTRON_PATH}/clang++"
    DTC_EXT="$(command -v dtc || echo /usr/bin/dtc)"
)

if [ "${CLEAN_BUILD}" -eq 1 ]; then
    echo -e "${YELLOW}[INFO]: Cleaning output directory...${NC}"
    rm -rf "${OUT_DIR}"/*
fi

echo -e "${BLUE}[INFO]: Loading ${DEFCONFIG}...${NC}"
make "${BUILD_OPTIONS[@]}" "${DEFCONFIG}"

if [ "${MENUCONFIG}" -eq 1 ]; then
    echo -e "${CYAN}[INFO]: Launching menuconfig...${NC}"
    make "${BUILD_OPTIONS[@]}" menuconfig
    echo -e "${GREEN}[INFO]: Menuconfig finished. Exiting.${NC}"
    exit 0
fi

START_TIME=$(date +%s)
echo -e "\n${BLUE}[INFO]: Building Kernel Image, Device Tree Blobs (DTBs), and Modules...${NC}\n"

make "${BUILD_OPTIONS[@]}" Image.gz dtbs modules

KERNEL_IMG="${OUT_DIR}/arch/arm64/boot/Image.gz"
if [ ! -f "${KERNEL_IMG}" ]; then
    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        echo -e "${YELLOW}[INFO]: Compressing raw Image to Image.gz...${NC}"
        gzip -k -9 "${OUT_DIR}/arch/arm64/boot/Image"
    else
        echo -e "\n${RED}[ERROR]: Kernel compilation failed! No Image found in ${OUT_DIR}/arch/arm64/boot/${NC}"
        exit 1
    fi
fi

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))
MINUTES=$((BUILD_DURATION / 60))
SECONDS=$((BUILD_DURATION % 60))

echo -e "\n${GREEN}${BOLD}[SUCCESS]: Kernel compilation completed in ${MINUTES}m ${SECONDS}s!${NC}\n"

cp -f "${KERNEL_IMG}" "${BUILD_DIR}/Image.gz"
if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
    cp -f "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/Image"
fi

if [ "${DEVICE}" = "odessa" ]; then
    DTB_DIR="${OUT_DIR}/arch/arm64/boot/dts/qcom"
    ODESSA_TREES=(
        sdmmagpie-odessa-base.dtb
        sdmmagpie-odessa-evt1-overlay.dtbo
        sdmmagpie-odessa-dvt2-overlay.dtbo
        sdmmagpie-odessa-pvt-overlay.dtbo
    )
    mkdir -p "${BUILD_DIR}/dtbs"
    for tree in "${ODESSA_TREES[@]}"; do
        if [ ! -s "${DTB_DIR}/${tree}" ]; then
            echo -e "${RED}[ERROR]: Missing Odessa device tree: ${tree}${NC}"
            exit 1
        fi
        cp -f "${DTB_DIR}/${tree}" "${BUILD_DIR}/dtbs/${tree}"
    done
    cp -f "${DTB_DIR}/sdmmagpie-odessa-base.dtb" "${BUILD_DIR}/dtb"
    echo -e "${YELLOW}[INFO]: Odessa preserves the installed DTBO. Compatible ROM overlays are required.${NC}"
fi

validate_odessa_anykernel() {
    local installer="${ZIP_DIR}/anykernel.sh"
    local devices

    if [ ! -f "${installer}" ]; then
        echo -e "${YELLOW}[DEBUG]: Missing anykernel.sh in ${ZIP_DIR}${NC}" >&2
        return 1
    fi
    if [ ! -f "${ZIP_DIR}/tools/ak3-core.sh" ]; then
        echo -e "${YELLOW}[DEBUG]: Missing tools/ak3-core.sh${NC}" >&2
        return 1
    fi
    if [ ! -f "${ZIP_DIR}/META-INF/com/google/android/update-binary" ]; then
        echo -e "${YELLOW}[DEBUG]: Missing META-INF/com/google/android/update-binary${NC}" >&2
        return 1
    fi
    if [ ! -f "${ZIP_DIR}/META-INF/com/google/android/updater-script" ]; then
        echo -e "${YELLOW}[DEBUG]: Missing META-INF/com/google/android/updater-script${NC}" >&2
        return 1
    fi
    if ! grep -Eq '^[[:space:]]*do.devicecheck=1[[:space:]]*$' "${installer}"; then
        echo -e "${YELLOW}[DEBUG]: do.devicecheck is not set to 1 in anykernel.sh${NC}" >&2
        return 1
    fi
    devices=$(sed -n 's/^[[:space:]]*device\.name[0-9][0-9]*=//p' "${installer}" | sed '/^[[:space:]]*$/d')
    if [ -z "${devices}" ] || [ -n "$(printf '%s\n' "${devices}" | grep -vx 'odessa' || true)" ]; then
        echo -e "${YELLOW}[DEBUG]: device.name entries are not exclusively 'odessa'${NC}" >&2
        return 1
    fi
    if [ -e "${ZIP_DIR}/dtbo.img" ] || [ -e "${ZIP_DIR}/dtbo" ]; then
        echo -e "${YELLOW}[DEBUG]: dtbo.img or dtbo must not exist in AnyKernel dir for odessa${NC}" >&2
        return 1
    fi
}

TIMESTAMP=$(date +"%Y%m%d-%H%M")
ZIP_NAME="Cybertron-v18-${DEVICE}-${TIMESTAMP}.zip"

if [ ! -d "${ZIP_DIR}" ] && [ "${DEVICE}" != "odessa" ]; then
    echo -e "${YELLOW}[INFO]: AnyKernel directory not found at ${ZIP_DIR}. Cloning fallback AnyKernel3...${NC}"
    git clone https://github.com/osm0sis/AnyKernel3.git "${ZIP_DIR}"
fi

PACKAGE_KERNEL=1
if [ "${DEVICE}" = "odessa" ] && ! validate_odessa_anykernel; then
    PACKAGE_KERNEL=0
    echo -e "${YELLOW}[WARN]: Odessa ZIP skipped: provide Cybertron/, anykernel-odessa or ZIP_DIR with complete AnyKernel3 installer files, Odessa-only device checks and no DTBO image.${NC}"
fi

if [ -d "${ZIP_DIR}" ] && [ "${PACKAGE_KERNEL}" -eq 1 ]; then
    echo -e "${BLUE}[INFO]: Packaging AnyKernel3 flashable zip in ${ZIP_DIR}...${NC}"
    cd "${ZIP_DIR}"

    rm -f *.zip Image.gz dtb *.dtb *.dtbo Image
    rm -rf modules

    cp -f "${BUILD_DIR}/Image.gz" "${ZIP_DIR}/Image.gz"

    DTB_DIR="${OUT_DIR}/arch/arm64/boot/dts/qcom"
    if [ "${DEVICE}" = "odessa" ]; then
        cp -f "${BUILD_DIR}/dtb" "${ZIP_DIR}/dtb"
        # Copy revision-specific overlays into the ZIP
        for tree in "${ODESSA_TREES[@]}"; do
            if [[ "${tree}" == *.dtbo ]]; then
                cp -f "${BUILD_DIR}/dtbs/${tree}" "${ZIP_DIR}/${tree}"
            fi
        done
    elif [ -d "${DTB_DIR}" ]; then
        MAGPIE_DTBS=$(find "${DTB_DIR}" -maxdepth 1 -name "*${DEVICE}*.dtb" 2>/dev/null || true)
        if [ -n "${MAGPIE_DTBS}" ]; then
            echo -e "${BLUE}[INFO]: Concatenating DTBs for ${DEVICE}...${NC}"
            cat "${DTB_DIR}"/*"${DEVICE}"*.dtb > "${ZIP_DIR}/dtb" 2>/dev/null || true
            cp -f "${ZIP_DIR}/dtb" "${BUILD_DIR}/dtb" 2>/dev/null || true
       fi
    fi

    MODULES=$(find "${OUT_DIR}" -name "*.ko" 2>/dev/null || true)
    if [ -n "${MODULES}" ]; then
        echo -e "${BLUE}[INFO]: Packaging built kernel modules into AnyKernel3...${NC}"
        MODULES_DIR="${ZIP_DIR}/modules/vendor/lib/modules"
        mkdir -p "${MODULES_DIR}"
        for mod in ${MODULES}; do
            mod_base="$(basename "${mod}")"
            echo -e "  -> ${mod_base}"
            "${NEUTRON_PATH}/llvm-strip" --strip-unneeded "${mod}" -o "${MODULES_DIR}/${mod_base}" 2>/dev/null || \
                cp -f "${mod}" "${MODULES_DIR}/${mod_base}"
        done
        if [ -f "anykernel.sh" ]; then
            sed -i "s/do.modules=.*/do.modules=1/g" anykernel.sh
            sed -i "s/do.systemless=.*/do.systemless=0/g" anykernel.sh
        fi
    else
        if [ -f "anykernel.sh" ]; then
            sed -i "s/do.modules=.*/do.modules=0/g" anykernel.sh
        fi
    fi

    if [ -f "version" ]; then
        sed -i "s/Cybertron-V[0-9]\+.*\"/Cybertron-v18\"/g" version 2>/dev/null || true
        sed -i "s/Cybertron-v[0-9]\+.*\"/Cybertron-v18\"/g" version 2>/dev/null || true
    fi

    if [ "${DEVICE}" != "odessa" ] && [ -f "anykernel.sh" ]; then
        sed -i "s/device.name1=.*/device.name1=${DEVICE}/g" anykernel.sh
        sed -i "s/device.name2=.*/device.name2=${DEVICE}/g" anykernel.sh
    fi

    zip -r9 "${ZIP_NAME}" ./* -x .git* README.md ./*placeholder &>/dev/null

    cp -f "${ZIP_NAME}" "${BUILD_DIR}/${ZIP_NAME}"
    cp -f "${ZIP_NAME}" "${ZIP_DIR}/${DEVICE}.zip"
    cp -f "${ZIP_NAME}" "${BUILD_DIR}/${DEVICE}.zip"
    if [ "${DEVICE}" = "odessa" ]; then
        cp -f "${ZIP_NAME}" "${ZIP_DIR}/anykernel.zip"
        cp -f "${ZIP_NAME}" "${BUILD_DIR}/anykernel.zip"
    fi

    ZIP_SIZE=$(du -h "${BUILD_DIR}/${ZIP_NAME}" | cut -f1)

    echo -e "\n${GREEN}${BOLD}=================================================="
    echo "            FLASHABLE ZIP GENERATED!             "
    echo "==================================================${NC}"
    echo -e " File       : ${CYAN}${BOLD}${ZIP_NAME}${NC} (${ZIP_SIZE})"
    echo -e " Location   : ${GREEN}${BUILD_DIR}/${ZIP_NAME}${NC}"
    echo -e " Alias      : ${GREEN}${BUILD_DIR}/${DEVICE}.zip${NC}"
    if [ "${DEVICE}" = "odessa" ]; then
        echo -e " AnyKernel  : ${GREEN}${ZIP_DIR}/anykernel.zip${NC}"
        echo -e " Copy       : ${GREEN}${BUILD_DIR}/anykernel.zip${NC}"
    fi
    echo -e " Total Time : ${BOLD}${MINUTES}m ${SECONDS}s${NC}"
    echo "=================================================="
else
    echo -e "${YELLOW}[WARN]: Flashable ZIP not generated; a compatible AnyKernel directory is required (${ZIP_DIR}).${NC}"
    echo -e "Kernel Image is available at: ${GREEN}${BUILD_DIR}/Image.gz${NC}"
fi

cd "${KERNEL_ROOT}"
exit 0