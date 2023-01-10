
check: lddtree.sh tests/Kyuafile Kyuafile
	kyua test || (kyua report --verbose && exit 1)

tests/Kyuafile: $(wildcard tests/*_test)
	echo "syntax(2)" > $@.tmp
	echo 'test_suite("lddtree")' >> $@.tmp
	for i in $(notdir $(wildcard tests/*_test)); do \
		echo "atf_test_program{name='$$i',timeout=5}" >> $@.tmp ; \
	done
	mv $@.tmp $@

Kyuafile:
	echo "syntax(2)" > $@.tmp
	echo "test_suite('alpine-conf')" >> $@.tmp
	echo "include('tests/Kyuafile')" >> $@.tmp
	mv $@.tmp $@

