# For the kernel
- ERASE the pid field from file descriptors and bound modules
- make syscalls based on yielding and request/response
- make TTYs work based off master/slave system (openpty is already implemented)
- Add stats to track how much is written to/read from devices
- Support the basic fs operations missing (`rename`, `symlink`, `link`)
- Add some kind of inotify-like system
- (maybe) some way to reload the entire kernel

# For the build system
- Make `luatok` support all Lua syntax properly
- Make `luamin` rename locals
- Make `luapreproc` a full preprocessor

# For the OS
- support hashed passwords
- support `/etc/shadow`
- making the current coreutils similar to the POSIX/GNU versions
- implementing more coreutils
- Add support for various networking stacks (atomnet `AF_ANET`, minitel `AF_MTEL`)
- add async I/O support to the networking drivers
- add Lua 5.2 support

## Add support for

### Partition tables

- `OSDI` (like in UlOS 2)
- `MBR` (standard classic partition table)
- `GPT` (standard UEFI partition table)
- `KPR` (custom partition table designed to be great for KOCOS)

### Filesystems

- `NiceFS` (obviously)
- `OnyxFS` (a custom-made FS designed to be great for ONYX)
- (maybe) `SimpleFS` (the FS in UlOS)
- (maybe) `FAT16` (the FS in UlOS)

### Booting off unmanaged drives

While the KOCOS kernel supports it through ramfs,
the Orbit bootloader does not. Also, associated
firmware should be provided, with support for:
- loading bootstrap code from MBR
- loading boot partition from MTPT, OSDI, KPR, GPT
- loading first 32KiB

The Orbit bootloader would use the boot address as
the drive to boot from, and try to read the partition
tables and bootloader partition.
It would prob only support NiceFS, as that is meant to
be the filesystem of the boot partition, maybe FAT16
too if ONYX would.
