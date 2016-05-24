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
  -x              Run with debugging
  -R <root>       Use this ROOT filesystem tree
  --no-auto-root  Do not automatically prefix input ELFs with ROOT
  -l              Display output in a flat format
  -b		  Change default backend tool (default is scanelf, alternative is readelf)
  -h              Show this help output
  -V              Show version information
```
