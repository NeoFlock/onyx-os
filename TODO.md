# For the kernel
- Get rid of a lot of internal functions and replace them with pure syscalls
- Replace files internally with resource handles, so everything has a file descriptor both externally and internally
- Make `FS-openFile` return a resource instead of just a file handle to allow opening files as different resources
- Try to reduce memory usage
- Unmount automatically when device is removed
- Lock mounts when driver is removed and allow new drivers to "rescue" old mounts
- Make devfs support opening handles to more hardware
- Make file permissions exist and matter
- Add some kind of inotify-like system

## New resource model system

A way to unify files, sockets, devices and locks as *resources.*

A resource would internally just be a `{type: "file"|"socket"|"dev"|"lock", refc: integer, callback: (function(action: string, ...): ...)}`.

That way, writing simply means `local ok, err = resource.callback("write", "data")`

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
