lddtree
=======

Fork of pax-utils' lddtree.sh

This is a shell version of pax-utils' lddtree. This tool is useful for
resolving elf dependencies when creating initramfs images.

Differences from pax-utils' bash version:
* don't use /bin/bash
* resolv symlinks
* fall back to objdump and readelf if scanelf is not found

lddtree.sh depends on scanelf from pax-utils or objdump and readelf from
binutils.

```
Usage: lddtree.sh [options] ELFFILE...

Options:

  -a                  Show all duplicated dependencies
  -x                  Run with debugging
  -R <root>           Use this ROOT filesystem tree
  -N, --no-auto-root  Do not automatically prefix input ELFs with ROOT
  -l                  Display output in a flat format
  -h                  Show this help output
  -V                  Show version information
```
