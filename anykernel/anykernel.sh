### AnyKernel3 - garnet (POCO X6 5G / Redmi Note 13 Pro 5G) - BakaSU + Droidspaces
properties() { '
kernel.string=garnet BakaSU + Droidspaces
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=garnet
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
}

BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# só troca o kernel (Image); não mexe no ramdisk
split_boot;
flash_boot;
