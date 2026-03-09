# Kernel for OpenComputers Operating Systems (rewritten)

This is a rewrite of the kernel in `usr/src/kocos`. It is mostly compatible.
It was started because the code is a mess due to a few poor design decisions and a rewrite was needed.

## Why a separate folder?

A rewrite of the kernel takes time. The old version is kept so you can boot it.
To switch to the new version, run `lua build.lua` with the `ONYX_KERNEL` environment variable set to `new_kocos`.
