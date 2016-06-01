#!/bin/sh
# Copyright 2007-2013 Gentoo Foundation
# Copyright 2007-2013 Mike Frysinger <vapier@gentoo.org>
# Copyright 2014-2015 Natanael Copa <ncopa@alpinelinux.org>
# Distributed under the terms of the GNU General Public License v2

# StudioEtrange <nomorgan@gmail.com>
# 	New option -b : to choose a backend tool (scanelf [by default] or readelf)
# 	Bug fixed with replace of $ORIGIN in RPATH
#		Bug fixed when elf path passed as arg is relative, RPATH values are turned into relative path with $ORIGIN and might not be resolved
#		New option --no-recursive : do not try to resolve dependencies of dependencies
#		New option --no-header : do not print first line (scaned elf file and interpreter information)

argv0=${0##*/}
version=1.25-CURRENT

: ${ROOT:=/}

[ "${ROOT}" = "${ROOT%/}" ] && ROOT="${ROOT}/"
[ "${ROOT}" = "${ROOT#/}" ] && ROOT="${PWD}/${ROOT}"

# Default backend tool to analyse elf
BACKEND="scanelf"

usage() {
	cat <<-EOF
	Display ELF dependencies as a tree

	Usage: ${argv0} [options] <ELF file[s]>

	Options:
	  -a              Show all duplicated dependencies
	  -R <root>       Use this ROOT filesystem tree
	  --no-auto-root  Do not automatically prefix input ELFs with ROOT
	  -l              List binary, interpreter and found dependencies files and their resolved links
	  -m              List dependencies in flat output
	  -b              Change default backend tools (default is scanelf, alternative is readelf)
	  --no-recursive  Do not recursivly parse dependencies
	  --no-header     Do not show header first line (including interpreter)

	  -h              Show this help output
	  -x              Run with debugging
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



# Backend functions
elf_specs_scanelf() {
	local _file="$1"
	# With glibc, the NONE, SYSV, GNU, and LINUX OSABI's are compatible.
	# LINUX and GNU are the same thing, as are NONE and SYSV, so normalize
	# GNU & LINUX to NONE. #442024 #464380
	scanelf -BF '#F%a %M %D %I' "$_file" | sed -r 's: (LINUX|GNU)$: NONE:'
}

elf_specs_readelf() {
	local _file="$1"
	readelf -h "$_file" | grep -E 'Class:|Data:|Machine:' | cut -d ':' -f 2 | sed 's/^ *//g' | tr '\n' ' '
}

elf_specs() {
	elf_specs_$BACKEND "$@"
}

elf_get_rpath_scanelf() {
	local _file="$1"
	# NOTE fixed g flag on sed
	scanelf -qF '#F%r' "${_file}" | sed -e "s:[$]ORIGIN:${_file%/*}:g"
}

elf_get_rpath_readelf() {
	local _file="$1"
	local _tmp_rpath=$(readelf -d "${needed_by}" | grep RUNPATH | cut -d '[' -f 2 | sed 's/]//' | sed -e "s:[$]ORIGIN:${needed_by%/*}:g")
	[ "$_tmp_rpath" = "" ] && _tmp_rpath=$(readelf -d "${needed_by}" | grep RPATH | cut -d '[' -f 2 | sed 's/]//' | sed -e "s:[$]ORIGIN:${needed_by%/*}:g")
	echo "${_tmp_rpath}"
}

elf_get_rpath() {
	elf_get_rpath_$BACKEND "$@"
}

elf_get_interp_scanelf() {
	local _file="$1"
	scanelf -qF '#F%i' "${_file}"
}

elf_get_interp_readelf() {
	local _file="$1"
	readelf -e "${_file}" | grep "interpreter:" | cut -d ':' -f 2 | sed 's/]//g' | sed 's/^ *//g'
}

elf_get_interp() {
	elf_get_interp_$BACKEND "$@"
}

elf_get_linked_lib_scanelf() {
	local _file="$1"
	scanelf -qF '#F%n' "${_file}"
}

elf_get_linked_lib_readelf() {
	local _file="$1"
	readelf -d "${_file}" | grep "NEEDED" | grep -o -E "\[[^]]*\]" | grep -o -E "[^][]*" | tr '\n' ',' | sed 's/,$//'
}

elf_get_linked_lib() {
	elf_get_linked_lib_$BACKEND "$@"
}


# Other functions
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

				# if path is relative (because of replacing $ORIGIN rpath with a relative elf path)
				# adding absolute path with current directory
				[ -z "${path##/*}" ] || path="${PWD}/${path}"

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
			c_last_needed_by_rpaths=
			if [ ! "${needed_by}" = "" ]; then
				c_last_needed_by_rpaths="$(elf_get_rpath "${needed_by}")"
			fi
		fi

		if [ -n "${c_last_needed_by_rpaths}" ]; then
			# search in rpath
			check_paths "${elf}" "${c_last_needed_by_rpaths}" && return 0
		fi

		if [ -n "${LD_LIBRARY_PATH}" ] ; then
			# search in LD_LIBRARY_PATH
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
			# search in ld.so configured paths
			check_paths "${elf}" "${c_ldso_paths}" && return 0
		fi
		# search in default ld.so path and some fallback path
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
	local oldpwd="$PWD"
	list_existing_file "${_resolv_links}"
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
		list_existing_file "${_resolv_links}"
	done
	cd "$oldpwd"
}

show_elf() {
	local elf=$1 indent=$2 parent_elfs=$3 recurs=$4
	local rlib lib libs
	local interp resolved
	find_elf "${elf}"
	resolved=${_find_elf}
	elf=${elf##*/}

	if [ ${indent} -eq 0 ]; then
		if ${HEADER}; then
			if ${MATCH_LIST} ; then
				printf "%s%s => " "" "${elf}"
			else
				${LIST} || printf "%${indent}s%s => " "" "${elf}"
			fi
		fi
	else
		if ${MATCH_LIST} ; then
			printf "%s%s => " "" "${elf}"
		else
			${LIST} || printf "%${indent}s%s => " "" "${elf}"
		fi
	fi


	case ",${parent_elfs}," in
	*,${elf},*)
		${LIST} || printf "!!! circular loop !!!\n" ""
		return
		;;
	esac
	parent_elfs="${parent_elfs},${elf}"
	if [ ${indent} -eq 0 ]; then
		if ${HEADER}; then
			${LIST} && resolv_links "${resolved:-$1}" || \
			printf "${resolved:-not found}"
			[ -z "${resolved}" ] && ret=1
		fi
	else
		${LIST} && resolv_links "${resolved:-$1}" || \
		printf "${resolved:-not found}"
		[ -z "${resolved}" ] && ret=1
	fi

	if [ ${indent} -eq 0 ] ; then
		elf_specs=$(elf_specs "${resolved}")
		interp="$(elf_get_interp "${resolved}")"

		# ignore interpreters that do not have absolute path
		[ "${interp#/}" = "${interp}" ] && interp=
		[ -n "${interp}" ] && interp="${ROOT}${interp#/}"

		if ${HEADER} ; then
			if ${LIST} ; then
				[ -n "${interp}" ] && resolv_links "${interp}"
			else
				printf " (interpreter => ${interp:-none})"
			fi
		fi

		if [ -r "${interp}" ] ; then
			# Extract the default lib paths out of the ldso.
			lib_paths_ldso=$(
				strings "${interp}" | \
				sed -nr -e "/^\/.*lib/{s|^/?|${ROOT}|;s|/$||;s|/?:/?|:${ROOT}|g;p}"
			)
		fi
		interp=${interp##*/}
	fi
	if [ ${indent} -eq 0 ]; then
		if ${HEADER}; then
			${LIST} || printf "\n"
		fi
	else
		${LIST} || printf "\n"
	fi



	[ -z "${resolved}" ] && return
	if ${recurs} ; then
		libs="$(elf_get_linked_lib "${resolved}")"
	fi
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
		# FIXED : do not remove path yet. So if we have an absolute path as linked lib, it could be matched in find_elf
		#lib=${lib##*/}
		case ",${my_allhits}," in
			*,${lib},*) continue;;
		esac
		find_elf "${lib}" "${resolved}"
		rlib=${_find_elf}
		show_elf "${rlib:-${lib}}" $((indent + 4)) "${parent_elfs}" ${RECURSIVE}
	done
}


# main

SHOW_ALL=false
SET_X=false
LIST=false
AUTO_ROOT=true
MATCH_LIST=false
# Recursive parse dependent libs
RECURSIVE=true
HEADER=true

while getopts haxVb:R:ml-:  OPT ; do
	case ${OPT} in
	a) SHOW_ALL=true;;
	x) SET_X=true;;
	h) usage;;
	V) version;;
	b) BACKEND="${OPTARG%}";;
	R) ROOT="${OPTARG%/}/";;
	l) LIST=true
		 MATCH_LIST=false;;
	m) MATCH_LIST=true
		 LIST=false;;
	-) # Long opts ftw.
		case ${OPTARG} in
		no-auto-root) AUTO_ROOT=false;;
		no-recursive) RECURSIVE=false;;
		no-header) HEADER=false;;
		*) usage 1;;
		esac
		;;
	?) usage 1;;
	esac
done


shift $(( $OPTIND - 1))
[ -z "$1" ] && usage 1

${SET_X} && set -x
ret=0
for elf ; do
	unset lib_paths_ldso
	unset c_last_needed_by

	# if auto root is setted and elf path is absolute
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
		show_elf "${elf}" 0 "" true
	fi
done
exit ${ret}
