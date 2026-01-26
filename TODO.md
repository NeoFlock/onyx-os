# For the kernel
- Get rid of a lot of internal functions and replace them with pure syscalls
- Try to reduce memory usage
- Unmount automatically when device is removed
- Lock mounts when driver is removed and allow new drivers to "rescue" old mounts
- Make file permissions exist and matter
- Add some kind of inotify-like system

# For the build system
- Make `luatok` support all Lua syntax properly
- Make `luamin` rename locals

# For the OS
- support hashed passwords
- making the current coreutils match the POSIX/GNU versions
- implementing more coreutils
- Add support for unmanaged filesystems and partition tables
- Add support for various networking stacks
- add async I/O support to the networking drivers
- add Lua 5.2 support
