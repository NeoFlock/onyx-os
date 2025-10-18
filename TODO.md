# For the kernel
- Get rid of a lot of internal functions and replace them with pure syscalls
- Make `FS-openFile` return a resource instead of just a file handle to allow opening files as different resources
- Allow multiple screens at once
- Try to reduce memory usage
- Unmount automatically when device is removed
- Lock mounts when driver is removed and allow new drivers to "rescue" old mounts
- Make devfs support opening handles to more hardware
- Make file permissions exist and matter
- Add some kind of inotify-like system

# For the build system
- Make `luatok` support all Lua syntax properly
- Make `luamin` rename locals

# For the OS
- add a package manager
- making the current coreutils match the POSIX/GNU versions
- implementing more coreutils
- Add support for unmanaged filesystems and partition tables
- Add support for various networking stacks
- add async I/O support to the networking drivers
