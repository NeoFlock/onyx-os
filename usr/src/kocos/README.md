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

Effectively just [https://en.wikipedia.org/wiki/ANSI_escape_code](ANSI)

### C0 control codes

- `0x07` (`\a`) Bell, make a bell noise
- `0x08` (`\b`) Backspace, move cursor to the left (undefined behavior if at the start of line)
- `0x09` (`\t`) Tab, move to the next tab stop
- `0x0A` (`\n`) Line Feed, move to the START of the next line
- `0x0C` (`\f`) Form Feed, move to the next page
- `0x0D` (`\r`) Carriage Return, move the cursor to the start of the current line
- `0x1b` (`\x1b`) Escape, start an escape sequence

### Fe Escape sequences

- `ESC \` - string terminator (important for OSC)
- `ESC ]` - OSC, terminated by `ESC \` or `BEL` (byte `0x07`, `\a`, and it does not make a noise), Operating System Command, covered later
- `ESC [` - CSI, terminated by a byte between `0x40` and `0x7E`.

### Fp Escape Sequences

- `ESC 7` - save cursor position
- `ESC 8` - restore cursor to last saved position

### CSI

- `CSI n A` - move cursor up. Default of `n` is 1.
- `CSI n B` - move cursor down. Default of `n` is 1.
- `CSI n C` - move cursor forward (right). Default of `n` is 1.
- `CSI n D` - move cursor backward (left). Default of `n` is 1.
- `CSI n E` - move cursor to the beginning of line, and then `n` lines down (default 1).
- `CSI n F` - move cursor to the beginning of line, and then `n` lines up (default 1).
- `CSI n G` - move cursor to the column `n` (default 1).
- `CSI n;m H` - move cursor to the nth row and mth column. Both default to 1.
- `CSI n J` - Clears part or the entirety of the screen. `n` defaults to 0. If `n` is 0, clears from the cursor to the end of the screen. If n is `1`, it clears
from the cursor to the start of the screen. if n is `2`, it clears the entire screen.
- `CSI n K` - Similar to `J`, except it is in terms of the *current line*, not the entire screen.
- `CSI n S` - Scroll up `n` lines (defaults to 1).
- `CSI n T` - Scroll down `n` lines (defaults to 1).
- `CSI ... m` - An SGR (Select Graphic Rendition) operation. Documented later.
- `CSI 6 n` - A DSR (Device Status Report) operation. It will respond with `CSI n;m R`, where n is the cursor x and m is the cursor y.
- `CSI 7 n` - Like DSR, except n is the columns and m is the rows
- `CSI 8 n` - Like DSR, except n is the maximum amount of colums supported and m is the maximum amount of rows supported
- `CSI 5 i` - Enable AUX port. The aux port may be an associated output device.
- `CSI 4 i` - Disable AUX port.
- `CSI ?25 h` - Shows the cursor. The cursor may blink, but it will certainly move.
- `CSI ?25 l` - Hides the cursor.
- `CSI ?1004 h` - Enables focus reporting. The terminal will output `CSI I` when entering focus and `CSI O` when exiting focus.
- `CSI ?1004 l` - Disables focus reporting.
- `CSI ?2004 h` - Enables key-release reporting.
- `CSI ?2004 l` - Disables key-release reporting.

TODO: scrollable region controls

### SGR (CSI)

A sequence of `;`-separated numbers. If none are present, a `0` is added implicitly.

- `0` - Reset graphical attributes.
- `7` - Swap foreground and background colors.
- `8` - Disable displaying output.
- `28` - Enable displaying output.
- `30 - 37` - Set foreground color (0-7)
- `38;5;n` - Set foreground color as entry `n` (0-255) in 256color table.
- `38;2;r;g;b` - Set foreground color as entry RGB color (`r`, `g` and `b` being 0-255).
- `39` - Set foreground color to default.
- `40 - 47` - Set background color (0-7)
- `48;5;n` - Set background color as entry `n` (0-255) in 256color table.
- `48;2;r;g;b` - Set background color as entry RGB color (`r`, `g` and `b` being 0-255).
- `49` - Set background color to default.
- `90-97` - Set bright foreground color (8-15)
- `100-107` - Set bright background color (8-15)

### GPU (CSI)
> Taken from or inspired by UlOS, these escapes allow GPU operations encoded in CSIs

- `CSI 1;x;y;w;h;c U`, which will perform `gpu.fill(x, y, w, h, unicode.char(c))`
- `CSI 2;x;y;w;h;dx;dy U`, which will perform `gpu.copy(x, y, w, h, dx, dy)`
- `CSI 2;x;y;w;h;dx;dy U`, which will perform `gpu.copy(x, y, w, h, dx, dy)`
- `CSI 3;w;h U`, which will perform `gpu.setResolution(w, h)`
- `CSI 4;x;y U`, which will perform `gpu.get(x, y)`, and will respond with `CSI c;f;b R`, where c is the codepoint of the character, f is the foreground and b is the background

### VRAM buffers (CSI)
> Great for everything from multiplexing to 3D graphics

- `CSI 1 v`, responds like DSR, except the `x` stores the free VRAM memory and `y` stores the total VRAM memory
- `CSI 2;w;h v`, allocates a new VRAM buffer with a resolution of `w`x`h`. Responds like DSR, if x being the buffer index, or 0 if there is an error, and y being the VRAM left after the allocation.
- `CSI 0n`, responds like DSR, except `x` stores the active screen buffer and `y` stores how many buffers are available
- `CSI 1n`, responds like DSR, except with any amount of numbers separated by `;` (including none, which would just be `CSI R`). Each number is a VRAM buffer index.
- `CSI 3;b v`, will free buffer `b`
- `CSI 3;0 v`, will free the current active buffer and switch back to the real screen.
- `CSI 3 v`, will free all VRAM buffers and switch back to real screen. (Great for shells!)
- `CSI 4;d;x;y;w;h;s;a;b v`, will perform a `gpu.bitblt(d,x,y,w,h,s,a,b)`, with defaults just like `bitblt`'s. This copies a region from one buffer to another. It is also used to copy to and from the screen.
- `CSI 5;x v`, switch VRAM buffer to `x` (0 for screen, x defaults to 0)

These escapes may not always be supported (ie. on terminals backed by other hardware or on older versions of OC), and thus using them may cause issues.
It is possible to check by seeing if the total VRAM memory is above 0.

If VRAM buffers are supported, resolution is in terms of the **active buffer**.
Changing resolution for VRAM buffers is not allowed, you should allocate a new buffer instead. Attempts to do so anyways should be ignored.

### OSC

Supported OSCs (specified as the contents between the start and terminator) are:
- `0;<message>`, which will either emit a kernel `L_WARN` log. In other applications, may change window title if applicable
- `8;;link`, which may open a link in some application, if applicable. In the KOCOS virtual terminal, it does nothing
- `Pnrrggbb`, where `n` is a hexadecimal digit and `rrggbb` is an RGB color in hexadecimal. Will change the 16 color palette's appropriate entry to that color.
- `1;<x>;<y>;<msg>`, performs a `gpu.set()`

## Terminal Input Sequences

Heavily based off ANSI, but not identical.

```
<char> -> char
<esc><esc> - esc

<esc>[<charcode>;<keycode>(;<modifier>)~ - Effectively a key_down event
<esc>[<charcode>;<keycode>(;<modifier>)^ - Effectively a key_up event. Rarely enabled.
<esc>[<size in bytes>|<contents> - Effectively a clipboard event
<esc>[1;x;yM - Effectively a screen_resized event, however SIGWINCH is preferred
<esc>[2;x;y;bM - A touch event, with x, y as position and b as the button
<esc>[3;x;y;bM - A drag event
<esc>[4;x;y;bM - A drop event
<esc>[5;x;y;dM - A scroll event, with x, y as position and d as the direction, where positive usually means up
<esc>[6;x;yM - A walk event, rarely useful
```

Terminals may only use `char` if the charcode is a printable character, as defined in `/lib/keyboard.lua`'s `isTerminalPrintable`, and either there are no modifiers,
or the only modifier is `Shift` and its an upper-case letter.

Ctrl + D, for closing stdin, is byte `0x04`, and Ctrl + C, for sending a SIGINT, is `0x03`.
The enter key emits a `\r` carriage return. Libraries which handle reading lines, such as `readline`,
may instead drop it and emit a `\n`, but the virtual terminal itself emits `\r`.

### Modifiers

Modifiers, unlike ANSI, do not have `1` implicitly added to them. Instead,
if they're 0, they're omitted.

The following modifiers are applied to keys:
- Shift = 1
- Alt = 2
- Control = 4
- Meta = 8 (keyboard code `0`)

## The built-in virtual terminal

KOCOS itself comes with a built-in virtual terminal implementation, backed by a simple GPU, screen and keyboard.

### ioctl(fd, "terminfo")

Doing an `ioctl` on a virtual terminal should return a table of the following
```lua
{
    termname = "terminal name",
    hw = {...}, -- list of addresses of associated components. If empty, it can be assumed to be a virtual terminal.
    hw_features = { -- list of hardware-assisted features
        "color", -- has colors. effectively, tier 2+ screen
        "truecolor", -- has an extended palette. effectively, tier 3+ screen
        "vrambuf", -- hardware-backed VRAM. If vrambuf is in term_features but not in hw_features, and the reported total VRAM is above 0, then the buffers are assumed to be emulated.
    },
    term_features = { -- supported sequences
        "ansicolor", -- 4-bit color codes like CSI 30 m
        "256color", -- 8-bit colors like CSI 38;5;0 m
        "truecolor", -- 24-bit colors like CSI 38;2;0;0;0 m
        "gpu", -- GPU (SGR) escapes
        "vrambuf", -- VRAM (SGR) escapes
    },
    columns = ..., -- columns available (terminal width)
    lines = ..., -- lines available (terminal height)
    -- nil if this is the raw TTY, but if it is supervised by a shell, then this is the name of the shell.
    -- Shells may wrap terminals to wrap them with line readers automatically,
    -- or to extend the feature-set.
    shellname = "shell name here",
}
```

This can also be used to check if an fd is a tty
