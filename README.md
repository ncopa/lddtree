lddtree
=======

Fork of [pax-utils](https://github.com/gentoo/pax-utils)' [lddtree.sh](https://github.com/gentoo/pax-utils/blob/master/lddtree.sh)

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
  -a, --all           Show all duplicated dependencies
  -h, --help          Show this help output
  -l, --flat          Display output in a flat format
      --no-auto-root  Do not automatically prefix input ELFs with ROOT
  -R, --root ROOT     Use this ROOT filesystem tree
  -V, --version       Show version information
  -x, --debug         Run with debugging
```

