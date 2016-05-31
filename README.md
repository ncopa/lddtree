lddtree
=======

Fork of pax-utils' lddtree python script

This is a shell version of pax-utils' lddtree. This tool is useful for
resolving elf dependencies when creating initramfs images.

Differences from pax-utils' bash version:
* don't use /bin/bash
* resolv symlinks

lddtree.sh depends on scanelf binary from pax-utils when using default backend tool 'scanelf'
lddtree.sh depends on readelf binary when using 'readelf' backend tool

```
Usage: lddtree.sh [options] ELFFILE...

Options:

  -a              Show all duplicated dependencies
  -R <root>       Use this ROOT filesystem tree
  --no-auto-root  Do not automatically prefix input ELFs with ROOT
  -l              List binary, interpreter and found dependencies files and their resolved links
  -m              List dependencies in flat output
  -b              Change default backend tools (default is scanelf, alternative is readelf)
  --no-recursive	Do not recursivly parse dependencies
  --no-header			Do not show header first line (including interpreter)

  -h              Show this help output
  -x              Run with debugging
  -V              Show version information
```
