lddtree
=======

Fork of pax-utils' lddtree.sh

This is a shell version of pax-utils' lddtree. This tool is useful for resolving
elf dependencies when creating initramfs images.

Differences from pax-utils' bash version:
* don't use /bin/bash
* resolv symlinks

lddtree.sh depends on scasnelf from pax-utils.
