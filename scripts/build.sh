#!/usr/bin/env bash
# Compila o kernel do POCO X6 5G (garnet) com BakaSU + Droidspaces.
#
# Entradas (variáveis de ambiente, todas opcionais exceto BOOT_IMG):
#   BOOT_IMG        boot.img stock da sua ROM (padrão: ./boot.img)
#   KERNEL_COMMIT   commit do kernel (padrão: "auto" = lido do boot.img)
#   KERNEL_BRANCH   fallback se o commit não for encontrado (padrão: lineage-24.0)
#   BAKASU_REPO     padrão: https://github.com/Baka-SU/BakaSU
#   BAKASU_REF      padrão: main
#   KABI_SLOT       6_7_8 | 1_2_3 | 3_4_5   (padrão: 6_7_8)
#   LTO             thin | full             (padrão: thin)
#   CLANG_VERSION   padrão: auto (lido do boot.img, ex.: r596125)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_IMG="${BOOT_IMG:-$ROOT/boot.img}"
KERNEL_COMMIT="${KERNEL_COMMIT:-auto}"
KERNEL_BRANCH="${KERNEL_BRANCH:-lineage-24.0}"
BAKASU_REPO="${BAKASU_REPO:-https://github.com/Baka-SU/BakaSU}"
BAKASU_REF="${BAKASU_REF:-main}"
KABI_SLOT="${KABI_SLOT:-6_7_8}"
LTO="${LTO:-thin}"
CLANG_VERSION="${CLANG_VERSION:-auto}"

WORK="$ROOT/work"
SRC="$WORK/kernel"
OUT="$WORK/out"
DIST="$ROOT/dist"
TOOL="$ROOT/scripts/bootimg_tool.py"
DS_RAW="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/GKI/below-kernel-6.12"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$BOOT_IMG" ] || die "boot.img não encontrado em $BOOT_IMG"
mkdir -p "$WORK" "$DIST"

# ---------------------------------------------------------------------------
log "1/8 Lendo informações do boot.img stock"
STOCK_RELEASE="$(python3 "$TOOL" release "$BOOT_IMG")"
KVER="${STOCK_RELEASE%%-*}"                 # 5.10.269
LOCALVER="${STOCK_RELEASE#"$KVER"}"         # -gki-g5914233baabc
echo "release stock : $STOCK_RELEASE"
echo "localversion  : $LOCALVER"
python3 "$TOOL" config "$BOOT_IMG" "$WORK/stock.config"

if [ "$KERNEL_COMMIT" = "auto" ]; then
  KERNEL_COMMIT="$(printf '%s' "$LOCALVER" | sed -n 's/.*-g\([0-9a-f]\{7,40\}\)$/\1/p')"
  [ -n "$KERNEL_COMMIT" ] || die "não consegui extrair o commit de $LOCALVER"
fi
echo "commit kernel : $KERNEL_COMMIT"

if [ "$CLANG_VERSION" = "auto" ]; then
  CLANG_VERSION="$(sed -n 's/^CONFIG_CC_VERSION_TEXT=.*based on \(r[0-9a-z]*\)).*/\1/p' "$WORK/stock.config")"
  [ -n "$CLANG_VERSION" ] || CLANG_VERSION="r596125"
fi
echo "clang         : $CLANG_VERSION"

# ---------------------------------------------------------------------------
log "2/8 Baixando o kernel (LineageOS/android_kernel_xiaomi_sm7435)"
if [ ! -d "$SRC/.git" ] && [ ! -f "$SRC/Makefile" ]; then
  git clone --filter=blob:none --no-checkout \
    https://github.com/LineageOS/android_kernel_xiaomi_sm7435.git "$SRC"
  cd "$SRC"
  if git checkout -q "$KERNEL_COMMIT" 2>/dev/null; then
    echo "checkout do commit $KERNEL_COMMIT ok"
  else
    echo "AVISO: commit $KERNEL_COMMIT não encontrado; usando a ponta de $KERNEL_BRANCH."
    echo "AVISO: o kernel pode não bater com os módulos da sua ROM."
    git checkout -q "origin/$KERNEL_BRANCH" || die "branch $KERNEL_BRANCH não existe"
  fi
  git rev-parse HEAD > "$WORK/kernel_commit.txt"
  rm -rf .git   # evita "-dirty"/hash extra na versão do kernel
fi
cd "$SRC"
[ -f Makefile ] || die "fonte do kernel incompleta"
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) =' Makefile | tr '\n' ' '; echo
SUB="$(sed -n 's/^SUBLEVEL = //p' Makefile)"
[ "5.10.$SUB" = "$KVER" ] || echo "AVISO: kernel do código é 5.10.$SUB, o stock é $KVER"

# ---------------------------------------------------------------------------
log "3/8 Toolchain clang $CLANG_VERSION"
CLANG_DIR="$WORK/clang"
if [ ! -x "$CLANG_DIR/bin/clang" ]; then
  mkdir -p "$CLANG_DIR"
  ok=0
  for ref in main master mirror-goog-main-llvm-toolchain-source; do
    url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/$ref/clang-$CLANG_VERSION.tar.gz"
    echo "tentando $url"
    if curl -fL --retry 3 -o "$WORK/clang.tgz" "$url" && tar -xzf "$WORK/clang.tgz" -C "$CLANG_DIR" 2>/dev/null \
       && [ -x "$CLANG_DIR/bin/clang" ]; then ok=1; break; fi
    rm -rf "$CLANG_DIR"; mkdir -p "$CLANG_DIR"
  done
  if [ "$ok" != 1 ]; then
    echo "AVISO: não consegui baixar o clang $CLANG_VERSION; usando clang do sistema."
    echo "AVISO: pode falhar com LTO/CFI. Se falhar, informe outra versão em clang_version."
    CLANG_DIR=""
  fi
fi
[ -n "$CLANG_DIR" ] && export PATH="$CLANG_DIR/bin:$PATH"
clang --version | head -1

# ---------------------------------------------------------------------------
log "4/8 Patches de kABI do Droidspaces (slot $KABI_SLOT)"
mkdir -p "$WORK/patches"
P1="001.GKI-below-6.12-fix_sysvipc_kabi_${KABI_SLOT}.patch"
P2="002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch"
curl -fsSL "$DS_RAW/$P1" -o "$WORK/patches/$P1" || die "não consegui baixar $P1"
curl -fsSL "$DS_RAW/$P2" -o "$WORK/patches/$P2" || die "não consegui baixar $P2"
for p in "$P1" "$P2"; do
  if patch -p1 --dry-run -s < "$WORK/patches/$p" >/dev/null; then
    patch -p1 -s < "$WORK/patches/$p"
    echo "aplicado: $p"
  else
    echo "--- dry-run de $p ---"; patch -p1 --dry-run < "$WORK/patches/$p" || true
    die "patch $p não aplica. Tente outro kabi_slot (1_2_3 ou 3_4_5) ou me envie este log."
  fi
done

# ---------------------------------------------------------------------------
log "5/8 Integrando BakaSU ($BAKASU_REPO @ $BAKASU_REF)"
rm -rf "$SRC/KernelSU"
git clone "$BAKASU_REPO" "$SRC/KernelSU"        # histórico completo: o versionCode vem do git
( cd "$SRC/KernelSU" && git checkout -q "$BAKASU_REF" && git log -1 --format='BakaSU commit %h (%cd)' )
[ -d "$SRC/KernelSU/kernel" ] || die "BakaSU sem pasta kernel/"
ln -sfn ../KernelSU/kernel drivers/kernelsu
grep -q 'CONFIG_KSU)' drivers/Makefile || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
if ! grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
  [ "$(tail -n1 drivers/Kconfig)" = "endmenu" ] || die "drivers/Kconfig não termina em endmenu"
  sed -i '$i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi

# ---------------------------------------------------------------------------
log "6/8 Configuração (base = .config do seu kernel stock)"
mkdir -p "$OUT"
cp "$WORK/stock.config" "$OUT/.config"
CFG=(./scripts/config --file "$OUT/.config")
# Droidspaces (lista mínima kABI-safe da documentação oficial)
while read -r sym; do "${CFG[@]}" -e "$sym"; done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT/scripts/droidspaces.config")
# BakaSU
"${CFG[@]}" -e KSU
# Mantém a versão idêntica à do stock para os módulos de vendor carregarem
"${CFG[@]}" -d LOCALVERSION_AUTO --set-str LOCALVERSION "$LOCALVER"
if [ "$LTO" = thin ]; then
  "${CFG[@]}" -d LTO_CLANG_FULL -e LTO_CLANG_THIN
fi

MAKE=(make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-
      KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=github -j"$(nproc)")
"${MAKE[@]}" olddefconfig

echo "--- símbolos importantes no .config final ---"
for s in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS UTS_NS NAMESPACES DEVTMPFS KSU KPROBES LTO_CLANG_FULL LTO_CLANG_THIN CFI_CLANG; do
  grep -E "^(CONFIG_$s=|# CONFIG_$s is not set)" "$OUT/.config" || echo "CONFIG_$s (ausente)"
done
grep -q '^CONFIG_KSU=y' "$OUT/.config"       || die "CONFIG_KSU não ficou =y (veja Kconfig do BakaSU)"
grep -q '^CONFIG_SYSVIPC=y' "$OUT/.config"   || die "CONFIG_SYSVIPC não ficou =y"
grep -q '^CONFIG_POSIX_MQUEUE=y' "$OUT/.config" || die "CONFIG_POSIX_MQUEUE não ficou =y"
for bad in CGROUP_PIDS CFS_BANDWIDTH; do
  if ! diff -q <(grep -E "CONFIG_$bad[= ]" "$WORK/stock.config") <(grep -E "CONFIG_$bad[= ]" "$OUT/.config") >/dev/null; then
    die "CONFIG_$bad mudou em relação ao stock; isso quebra a kABI. Abortando."
  fi
done
diff <(grep -E '^(CONFIG_|# CONFIG_)' "$WORK/stock.config" | sort) \
     <(grep -E '^(CONFIG_|# CONFIG_)' "$OUT/.config" | sort) > "$DIST/config.diff" || true
echo "diferenças de config vs stock: $(grep -c '^[<>]' "$DIST/config.diff") linhas (veja dist/config.diff)"

# ---------------------------------------------------------------------------
log "7/8 Compilando Image (pode levar 30-90 min)"
"${MAKE[@]}" Image
IMG="$OUT/arch/arm64/boot/Image"
[ -f "$IMG" ] || die "Image não foi gerado"

NEW_RELEASE="$(python3 "$TOOL" release "$IMG")"
echo "release novo  : $NEW_RELEASE"
echo "release stock : $STOCK_RELEASE"
[ "$NEW_RELEASE" = "$STOCK_RELEASE" ] || die "versão diferente do stock: os módulos de vendor NÃO vão carregar"

# ---------------------------------------------------------------------------
log "8/8 Gerando saídas"
cp "$IMG" "$DIST/Image"
cp "$OUT/.config" "$DIST/final.config"
python3 "$TOOL" repack "$BOOT_IMG" "$IMG" "$DIST/boot_garnet_bakasu_droidspaces.img"
( cd "$DIST" && sha256sum Image boot_garnet_bakasu_droidspaces.img > SHA256SUMS )
echo; echo "Pronto. Arquivos em $DIST:"; ls -lh "$DIST"
