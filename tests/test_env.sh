# shellcheck shell=sh

SRCDIR=$(atf_get_srcdir)/..
PATH=$SRCDIR:$PATH

init_tests() {
	TESTS=
	for t; do
		TESTS="$TESTS $t"
		atf_test_case "$t"
	done
	export TESTS
}

atf_init_test_cases() {
	for t in $TESTS; do
		atf_add_test_case "$t"
	done
}
