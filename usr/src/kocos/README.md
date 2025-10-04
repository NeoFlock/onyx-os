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

# Executable formats

## LuaExec

A file starting with `--!lua` is considered a **Lua executable**.
It is launched with the code as the `_start` symbol AND the main thread.
However, it also loads in the *Lua runtime* (LuaRT), which is defined in `/lib/luart.lua` by default. It is done using a `require("luart")`, thus it checks `LUA_PATH`.

## KELF
> Kocos Executable & Loadable File (very different from ELF)

The KELF format can be described with the following C structs:
```c
struct kelf_file {
    char header[5] = "KELF\n";
    char version[]; // new-line terminated base10 integer
    char osversion[]; // new-line terminated string. Stores the OS this binary was compiled for. Does not mean other OSes can't run it.
    char architecture[]; // new-line terminated string. Stores the architecture this binary was compiled for (for Lua, it is the _VERSION). Does not mean other versions can't run it.
    char filetype; // single character, indicates what type of file.
    char interpreter[]; // new-line terminated base10 integer. If empty, it is statically linked.
    char dependencyCount[]; // new-line terminated base10 integer
    char dependencies[][dependencyCount]; // array of new-line terminated strings.
    char sectionCount[]; // new-line terminated base10 integer
    kelf_section sections[sectionCount];
};

enum kelf_filetype {
    EXECUTABLE = 'X',
    OBJECT = 'O',
    LIBRARY = 'L',
};

struct kelf_section {
    char name[]; // new-line terminated string
    char flags[]; // new-line terminated flag array string
    char symbolCount[]; // new-line terminated base10 integer
    kelf_symbol symbols[symbolCount];
};

enum kelf_sectionFlags {
    READONLY = 'R',
    EXECUTABLE = 'X',
    RELOCATABLE = 'O',
};

struct kelf_symbol {
    char name[]; // new-line terminated string
    char source[]; // new-line terminated string, indicates the "source path" for debug information
    char size[]; // new-line terminated base10 integer
    uint8_t contents[size];
};

enum kelf_symbolFlags {
    WEAK = 'W', // this means linker may rename them and may not need to expose them
    GLOBAL = 'G', // should be exported
};
```

A `char` is a single *ASCII character*. Unicode is allowed, but should be treated as *multiple characters*.

For Lua, the `.lua` section is used for general-purpose Lua code. Sections for more specific versions can be used, like `.Lua 5.2` (more accurately, `"." .. _VERSION`)
If used for architectures or on platforms which may require **link information**, it may be stored in the `.linking` section.

# Terminal Sequences

## Terminal Output Sequences

Effectively just [https://en.wikipedia.org/wiki/ANSI_escape_code#C0_control_codes](ANSI)

### C0 control codes

- `0x07` (`\a`) Bell, make a bell noise
- `0x08` (`\b`) Backspace, move cursor to the left (undefined behavior if at the start of line)
- `0x09` (`\t`) Tab, move to the next tab stop
- `0x0A` (`\n`) Line Feed, move to the START of the next line
- `0x0C` (`\f`) Form Feed, move to the next page
- `0x0D` (`\r`) Carriage Return, move the cursor to the start of the current line
- `0x1b` (`\x1b`) Escape, start an escape sequence

### CSI

TODO: CSI sequences

### OSC

TODO: OSC sequences

## Terminal Input Sequences

Heavily based off ANSI, but not identical.

```
<char> -> char
<esc><esc> - esc

<esc>[<charcode>;<keycode>(;<modifier>)~ - Effectively a key_down event
<esc>[<charcode>;<keycode>(;<modifier>)^ - Effectively a key_up event. Rarely enabled.
<esc>[<size in bytes>|<contents> - Effectively a clipboard event
```

Terminals may only use `char` if the charcode is a printable character, as defined in `/lib/keyboard.lua`'s `isTerminalPrintable`, and either there are no modifiers,
or the only modifier is `Shift` and its an upper-case letter.

## The built-in virtual terminal

KOCOS itself comes with a built-in virtual terminal implementation, backed by a simple GPU, screen and keyboard.
