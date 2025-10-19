# NiceFS

A very simple filesystem meant for booting on unmanaged drives, ideal for boot partitions.
It is very limited in features and simple to implement readers for.

# Structure

Sector `1` is left untouched. This is to allow drives to use it for boot signatures, such as with an MBR table.

Sector `2` contains the super block.
Sectors above `2` are actual data blocks.

Each block is exactly *1* sector, for simplicity.

Integers are stored in **big-endian**, for simplicity when decoding in Lua 5.2 using a multiply-and-add algorithm.

Null blocks are at a mythical sector `0`.
Sector indexes are stored as 16-bit unsigned integers.

The data structures are defined as the following C types:
```c
// sector 2
struct superblock {
    char header[8] = "NiceFS1\0";
    uint16_t nextFreeBlock;
    uint16_t freeList;
    uint16_t activeBlockCount;
    entry rootDirectory;
};

// 32 bytes
struct entry {
    char name[16]; // padded with NULLs. All NULLs should be removed when reading out the name of the file.
    uint24_t fileSizeAndMode; // highest 4 bits are for the file mode, more on that later
    // firstBlock can be null, in which case there is no data associated with the entry. This allows 0 byte files to truly take up 0 bytes.
    uint16_t firstBlock;
    // 11 bytes reserved, should be 0.
};

// if you shift fileSizeAndMode by 20 bytes to the right, or do an integer division by 2^20, you'll get a 4-bit fileMode
enum fileMode {
    // file can be read by anyone
    readable = 1,
    // file can be written to by anyone
    writable = 2,
    // file can be executed by anyone who can read it
    executable = 4,
    // file is a directory
    directory = 8,
};

// an actual block of data pointed to by, for example, firstBlock in the entry.
struct dataBlock {
    uint16_t nextBlock; // Null for the last block
    // 30 bytes reserved, should be 0. This simplifies reading directories as it makes the blocks fit an even amount of entries.
    uint8_t data[]; // rest of sector
};
```

`nextFreeBlock` points to the first sector in the unused space of the filesystem. `freeList` should point to the most recently freed block, and represents a
singled linked list of blocks which can be re-used. `activeBlockCount` represents the number of blocks which are in active use, and should be at least 2, as
sector 1 and the superblock do count. This, times the sector size, is the total space used of the storage volume.

For directories, the file size is the amount of *entries*.

# Booting

When booting off of a partition or device with a `nicefs` filesystem on it, it should load `init.lua` off of it just like on a managed filesystem.
