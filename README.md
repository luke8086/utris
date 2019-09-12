### µTris

A rudimentary tetris clone that fits into a 512b bootsector of x86 devices and works without an operating system

### Running

```
nasm utris.asm -o utris.o

# Either prepare a floppy disk image for an emulator:

dd if=/dev/zero of=floppy.img bs=1k count=1440
dd if=utris.o of=floppy.img conv=notrunc

# Or install on a physical floppy, HDD or a USB disk
# for booting a real device (USE WITH CAUTION):

dd if=utris.o of=/dev/disk2
```

### Controls ###

    move   - left/right/down
    rotate - up
    drop   - space bar

### Screenshot ###

![screenshot.png](screenshot.png)
