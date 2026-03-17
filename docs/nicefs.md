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
They're offset by 2, so sector index `1` means sector `3`.
With 512 byte sectors, it leads to supporting roughly 32MiB of storage maximum.

The data structures are defined as the following C types:
```c
// sector 2
struct superblock {
    char header[8] = "NiceFS1\0";
    uint16_t nextFreeBlock;
    uint16_t freeList;
    uint16_t activeBlockCount;
    entry rootDirectory;
    // rest of sector should be 0.
};

// 32 bytes
struct entry {
    char name[16]; // padded with NULLs. All NULLs should be removed when reading out the name of the file.
    uint24_t fileSizeAndMode; // highest 4 bits are for the file mode, more on that later
    // firstStorage can be null, in which case there is no data associated with the entry. This allows 0 byte files to truly take up 0 bytes.
    // points to a fileStorage struct.
    uint16_t firstStorage;
    // 11 bytes reserved, should be 0.
};

// if you shift fileSizeAndMode by 20 bits to the right, or do an integer division by 2^20, you'll get a 4-bit fileMode
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

// this stores the blocks used by the file
struct fileStorage {
    // the next file storage in line.
    // if null, 0.
    uint16_t nextFileStorage;
    uint16_t blocks[];
};

// a block which was freed.
struct freeBlock {
    // next block in the free list
    uint16_t nextFreeBlock;
    // rest is random unallocated garbage.
};
```

`nextFreeBlock` points to the first sector in the unused space of the filesystem. `freeList` should point to the most recently freed block, and represents a
singled linked list of blocks which can be re-used. `activeBlockCount` represents the number of blocks which are in active use, however the superblock does not
count. This, plus 2, times the sector size, is the space used of the storage volume.

For directories, the file size should be the amount of entries allocated. Empty filename means NULL entry.
Free list and the fileStorage lists is NULL-terminated.

# Booting

When booting off of a partition or device with a `nicefs` filesystem on it, it should load `init.lua` off of it just like on a managed filesystem.
In general, the FS should be treated like a managed filesystem, and thus the booting convention of managed filesystems should be used.
