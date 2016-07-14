lddtree
=======

Fork of pax-utils' lddtree python script

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

  -a              Show all duplicated dependencies
  -x              Run with debugging
  -b <backend>    Force use of specific backend tools (scanelf or binutils)
  -R <root>       Use this ROOT filesystem tree
  --no-auto-root  Do not automatically prefix input ELFs with ROOT
  --no-recursive  Do not recursivly parse dependencies
  --no-header     Do not show header (binary and interpreter info)
  -l              Display output in a flat format
  -h              Show this help output
  -V              Show version information
```
