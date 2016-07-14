#!/bin/sh
# Copyright 2007-2013 Gentoo Foundation
# Copyright 2007-2013 Mike Frysinger <vapier@gentoo.org>
# Copyright 2014-2015 Natanael Copa <ncopa@alpinelinux.org>
# Distributed under the terms of the GNU General Public License v2

argv0=${0##*/}
version=1.25

: ${ROOT:=/}

[ "${ROOT}" = "${ROOT%/}" ] && ROOT="${ROOT}/"
[ "${ROOT}" = "${ROOT#/}" ] && ROOT="${PWD}/${ROOT}"

usage() {
	cat <<-EOF
	Display ELF dependencies as a tree

	Usage: ${argv0} [options] <ELF file[s]>

	Options:
	  -a              Show all duplicated dependencies
	  -x              Run with debugging
	  -b              Force use of specific backend tools (scanelf or binutils)
	  -R <root>       Use this ROOT filesystem tree
	  --no-auto-root  Do not automatically prefix input ELFs with ROOT
	  -l              Display output in a flat format
	  -h              Show this help output
	  -V              Show version information
	EOF
	exit ${1:-0}
}

version() {
	exec echo "lddtree-${version}"
}

error() {
	echo "${argv0}: $*" 1>&2
	ret=1
	return 1
}

# functions for scanelf backend
elf_rpath_scanelf() {
	scanelf -qF '#F%r' "$@"
}

elf_interp_scanelf() {
	scanelf -qF '#F%i' "$@"
}

elf_needed_scanelf() {
	scanelf -qF '#F%n' "$@"
}

elf_specs_scanelf() {
	# %a = machine (EM) type
	# %M = EI class
	# %D = endian
	# %I = osabi

	# With glibc, the NONE, SYSV, GNU, and LINUX OSABI's are compatible.
	# LINUX and GNU are the same thing, as are NONE and SYSV, so normalize
	# GNU & LINUX to NONE. #442024 #464380
	scanelf -BF '#F%a %M %D %I' "$1" | \
		sed -r 's: (LINUX|GNU)$: NONE:'
}

# functions for binutils backend
elf_rpath_binutils() {
	objdump -x "$@" | awk '$1 == "RPATH" || $1 == "RUNPATH" { print $2 }'
}

elf_interp_binutils() {
	# readelf -p .interp ouputs:
	#
	# String dump of section '.interp':
	#  [     0]  /lib/ld-musl-x86_64.so.1
	#
	readelf  -p .interp "$1" | sed -E -n '/\[\s*[0-9]\]/s/^\s*\[.*\]\s*(.*)/\1/p'
}

elf_needed_binutils() {
	objdump -x "$@" | awk '$1 == "NEEDED" { line=line sep $2 ; sep="," } END { print line }'
}

elf_specs_binutils() {
	# get Class, Data, Machine and OS/ABI.
	# the OS/ABI 'GNU', 'System V' and 'Linux' are compatible so normalize
	readelf -h "$1" \
		| awk -F: '$1 ~ /Class|Data|Machine|OS.ABI/ {gsub(/^ +/, "", $2); print $2}' \
		| sed -E -e 's/UNIX - (System V|Linux|GNU)/UNIX/' \
		| tr '\n' ' '
}

# elf wrapper functions
elf_rpath() { elf_rpath_$BACKEND "$@"; }
elf_interp() { elf_interp_$BACKEND "$@"; }
elf_needed() { elf_needed_$BACKEND "$@"; }
elf_specs() { elf_specs_$BACKEND "$1"; }

unset lib_paths_fallback
for p in ${ROOT}lib* ${ROOT}usr/lib* ${ROOT}usr/local/lib*; do
	lib_paths_fallback="${lib_paths_fallback}${lib_paths_fallback:+:}${p}"
done
c_ldso_paths_loaded='false'
find_elf() {
	_find_elf=''

	local elf=$1 needed_by=$2
	if [ "${elf}" != "${elf##*/}" ] && [ -e "${elf}" ] ; then
		_find_elf=${elf}
		return 0
	else
		check_paths() {
			local elf="$1"
			local pathstr="$2"
			IFS=:
			set -- $pathstr
			unset IFS
			local path pe
			for path ; do
				: ${path:=${PWD}}
				if [ "${path#${ROOT}}" = "${path}" ]; then
					path="${ROOT}${path#/}"
				fi
				pe="${path%/}/${elf#/}"
				if [ -e "${pe}" ] ; then
					if [ "$(elf_specs "${pe}")" = "${elf_specs}" ] ; then
						_find_elf=${pe}
						return 0
					fi
				fi
			done
			return 1
		}

		if [ "${c_last_needed_by}" != "${needed_by}" ] ; then
			c_last_needed_by="${needed_by}"
			c_last_needed_by_rpaths=$(elf_rpath "${needed_by}" | \
				sed -e "s:[$]ORIGIN:${needed_by%/*}:")
		fi
		if [ -n "${c_last_needed_by_rpaths}" ]; then
			check_paths "${elf}" "${c_last_needed_by_rpaths}" && return 0
		fi

		if [ -n "${LD_LIBRARY_PATH}" ] ; then
			check_paths "${elf}" "${LD_LIBRARY_PATH}"
		fi

		if ! ${c_ldso_paths_loaded} ; then
			c_ldso_paths_loaded='true'
			c_ldso_paths=
			if [ -r ${ROOT}etc/ld.so.conf ] ; then
				read_ldso_conf() {
					local line p
					for p ; do
						# if the glob didnt match anything #360041,
						# or the files arent readable, skip it
						[ -r "${p}" ] || continue
						while read line ; do
							case ${line} in
								"#"*) ;;
								"include "*) read_ldso_conf ${line#* } ;;
								*) c_ldso_paths="$c_ldso_paths:${ROOT}${line#/}";;
							esac
						done <"${p}"
					done
				}
				# the 'include' command is relative
				local _oldpwd="$PWD"
				cd "$ROOT"etc >/dev/null
				read_ldso_conf "${ROOT}"etc/ld.so.conf
				cd "$_oldpwd"
			fi
		fi
		if [ -n "${c_ldso_paths}" ] ; then
			check_paths "${elf}" "${c_ldso_paths}" && return 0
		fi

		check_paths "${elf}" "${lib_paths_ldso:-${lib_paths_fallback}}" && return 0
	fi
	return 1
}

list_existing_file() {
	if [ -e "$1" ]; then
		echo "$1"
	else
		echo "$1: Not found." >&2
	fi
}

# echo all intermediate symlinks and return the resolved path in
# global variable _resolv_links
resolv_links() {
	_resolv_links="$1"
	_list_files="$2"
	local oldpwd="$PWD"
	[ "$_list_files" = yes ] && list_existing_file "${_resolv_links}"
	cd "${_resolv_links%/*}"
	while [ -L "$_resolv_links" ]; do
		_resolv_links=$(readlink "$_resolv_links")
		case "$_resolv_links" in
		/*)	_resolv_links="${ROOT}${_resolv_links#/}"
			cd "${_resolv_links%/*}"
			;;
		*/*)	cd "${_resolv_links%/*}"
			;;
		esac
		_resolv_links=$(pwd -P)/${_resolv_links##*/}
		[ "$_list_files" = yes ] && list_existing_file "${_resolv_links}"
	done
	cd "$oldpwd"
}

show_elf() {
	local elf=$1 indent=$2 parent_elfs=$3
	local rlib lib libs
	local interp resolved
	find_elf "${elf}"
	resolved=${_find_elf}
	elf=${elf##*/}

	${LIST} || printf "%${indent}s%s => " "" "${elf}"
	case ",${parent_elfs}," in
	*,${elf},*)
		${LIST} || printf "!!! circular loop !!!\n" ""
		return
		;;
	esac
	parent_elfs="${parent_elfs},${elf}"
	if ${LIST} ; then
		resolv_links "${resolved:-$1}" yes
	else
		resolv_links "${resolved:-$1}" no
		printf "${resolved:-not found}"
	fi
	resolved=${_resolv_links}
	if [ ${indent} -eq 0 ] ; then
		elf_specs=$(elf_specs "${resolved}")
		interp=$(elf_interp "${resolved}")
		# ignore interpreters that do not have absolute path
		[ "${interp#/}" = "${interp}" ] && interp=
		[ -n "${interp}" ] && interp="${ROOT}${interp#/}"

		if ${LIST} ; then
			[ -n "${interp}" ] && resolv_links "${interp}" yes
		else
			printf " (interpreter => ${interp:-none})"
		fi
		if [ -r "${interp}" ] ; then
			# Extract the default lib paths out of the ldso.
			lib_paths_ldso=$(
				strings "${interp}" | \
				sed -nr -e "/^\/.*lib/{s|^/?|${ROOT}|;s|/$||;s|/?:/?|:${ROOT}|g;p}" | \
				tr '\n' ':'
			)
		fi
		interp=${interp##*/}
	fi
	${LIST} || printf "\n"

	[ -z "${resolved}" ] && return

	libs=$(elf_needed "${resolved}")

	local my_allhits
	if ! ${SHOW_ALL} ; then
		my_allhits="${allhits}"
		allhits="${allhits},${interp},${libs}"
	fi

	oifs="$IFS"
	IFS=,
	set -- ${libs}
	IFS="$oifs"

	for lib; do
		lib=${lib##*/}
		case ",${my_allhits}," in
			*,${lib},*) continue;;
		esac
		find_elf "${lib}" "${resolved}"
		rlib=${_find_elf}
		show_elf "${rlib:-${lib}}" $((indent + 4)) "${parent_elfs}"
	done
}

SHOW_ALL=false
SET_X=false
LIST=false
AUTO_ROOT=true

while getopts haxVb:R:l-:  OPT ; do
	case ${OPT} in
	a) SHOW_ALL=true;;
	x) SET_X=true;;
	h) usage;;
	V) version;;
	R) ROOT="${OPTARG%/}/";;
	l) LIST=true;;
	b) BACKEND="${OPTARG%}";;
	-) # Long opts ftw.
		case ${OPTARG} in
		no-auto-root) AUTO_ROOT=false;;
		*) usage 1;;
		esac
		;;
	?) usage 1;;
	esac
done
shift $(( $OPTIND - 1))
[ -z "$1" ] && usage 1

${SET_X} && set -x

if [ -z "${BACKEND}" ]; then
	if which scanelf >/dev/null; then
		BACKEND=scanelf
	elif which objdump >/dev/null && which readelf >/dev/null; then
		BACKEND=binutils
	else
		error "This tool needs either scanelf or binutils (objdump and readelf)"
		exit 1
	fi
fi

ret=0
for elf ; do
	unset lib_paths_ldso
	unset c_last_needed_by
	if ${AUTO_ROOT} && [ -z "${elf##/*}" ] ; then
		elf="${ROOT}${elf#/}"
	fi
	if [ ! -e "${elf}" ] ; then
		error "${elf}: file does not exist"
	elif [ ! -r "${elf}" ] ; then
		error "${elf}: file is not readable"
	elif [ -d "${elf}" ] ; then
		if $LIST; then
			echo ${elf}
		else
			error "${elf}: is a directory"
		fi
	else
		allhits=""
		[ "${elf##*/*}" = "${elf}" ] && elf="./${elf}"
		show_elf "${elf}" 0 ""
	fi
done
exit ${ret}
