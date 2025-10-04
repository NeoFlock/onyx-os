# KOCOS
> Kernel for Open Computers Operating Systems

The kernel of ONYX, but it is also perfectly usable outside of it.
It is deisgned for low memory usage while still being fully capable of complex workloads.

## Using KOCOS outside of ONYX

Some ***individuals*** may have an issue with the kernel being the ONYX repos and not its own repo.
This really doesn't matter much, however, to use KOCOS outside of ONYX, you can clone the ONYX repo
and run the following command:
```sh
lua build.lua kocos
```

Or the following Lua code
```lua
os.execute"lua build.lua kocos"
```

KOCOS will be built in `kernel`.

Inside of your more complex build system.

This can be done for an ONYX submodule. There is the downside of having the entirety of ONYX in a submodule,
however unless you're compiling this inside of an OpenComputers machine, you should not run into storage issues
because of this.

ONYX also contains other things you may want to take, like the Lua script runtime that KOCOS depends on, which can be tricky to get right.

## Using KOCOS in OpenOS

**Don't.**
