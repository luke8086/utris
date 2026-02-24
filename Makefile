all: disk.img

%.bin: %.asm
	nasm -f bin -o $@ $<

disk.img: utris.bin
	dd if=/dev/zero of=$@ bs=1k count=1440
	dd if=$< of=$@ conv=notrunc

clean:
	rm -f *.bin *.img

.PHONY: all clean
