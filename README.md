# Kernel BakaSU + Droidspaces para POCO X6 5G (garnet) — LineageOS 24.0

Compila na nuvem (GitHub Actions) um kernel idêntico ao da sua ROM
(`lineage-24.0-20261118-nightly-garnet`, kernel `5.10.269-gki-g5914233baabc`) com:

- **BakaSU** (root no kernel, hook padrão "tracepoint syscall redirect" do GKI 5.10)
- **Droidspaces** (`SYSVIPC`, `POSIX_MQUEUE`, `IPC_NS`, `PID_NS`, `DEVTMPFS`… + patches de kABI)

Tudo é derivado do **seu `boot.img`**: commit do kernel, versão (`uname -r`), `.config` e versão do clang.
O build **aborta** se a versão final não for idêntica à do stock (senão os módulos de vendor — Wi-Fi, toque, câmera — não carregariam).

## Passo a passo

1. **Instale a ROM** (24.0, 20261118) e confirme que tudo funciona. Guarde o `boot.img` dessa ROM (é o que você já tem).
2. **Compacte o boot.img** (tem 192 MB, o limite do GitHub é 100 MB):
   `gzip -9 boot.img`  → gera `boot.img.gz`
3. Crie um repositório **público** no GitHub (Actions é grátis em público) e envie todo este conteúdo
   **+ o `boot.img.gz` na raiz**.
4. Aba **Actions → Build garnet kernel → Run workflow**. Deixe os padrões na 1ª vez. Demora ~40–90 min.
5. Ao terminar, baixe o artefato **garnet-kernel** (contém `boot_garnet_bakasu_droidspaces.img`, o zip AnyKernel3, `Image`, `final.config`, `build.log`).

## Flash (a parte sua)

Antes: **guarde o boot original** (`boot.img` da ROM) para voltar se der problema.

```
adb reboot bootloader
fastboot flash boot boot_garnet_bakasu_droidspaces.img
fastboot reboot
```
(Alternativa: zip AnyKernel3 pelo recovery.) Se o aparelho reclamar de verificação (AVB), só então:
`fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img` (o `vbmeta.img` vem do zip da ROM).

Para voltar: `fastboot flash boot boot.img` (o original).

## Depois de bootar

- `adb shell uname -r` → deve ser `5.10.269-gki-g5914233baabc`.
- Instale o **manager do BakaSU** com o mesmo commit do `KernelSU/` usado no build (o versionCode precisa bater; o `build.log` mostra o commit).
- Droidspaces: rode o `droidspaces check` e veja se algo obrigatório falta.

## Se algo falhar

| Sintoma | O que fazer |
|---|---|
| Patch kABI não aplica | rode de novo com `kabi_slot` = `1_2_3` e depois `3_4_5` |
| Bootloop / trava no logo | volte o boot original; tente outro `kabi_slot` |
| Build sem memória / cancelado | mantenha `lto = thin` |
| clang não baixa | informe `clang_version` manualmente (veja `CONFIG_CC_VERSION_TEXT` do log) |
| `CONFIG_KSU` não fica `y` | me envie o trecho "símbolos importantes" do `build.log` |
| Wi-Fi/toque não funcionam | kABI quebrou: envie `dmesg` e `config.diff` |

**Aviso:** o workflow não foi executado antes (não há como rodá-lo fora do GitHub). Espere ajustar algo no primeiro run; mande o log do erro.
