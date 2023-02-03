# Example postgresql.conf custom awk configuration script
# 
# Input has ' = ' as delimiter, e.g. [[:space:]]=[[:space:]], so that $1 is the setting name and $2
# is the setting value (any any trailing comments).
#
# To match settings that may be commented out, use a regex like ""^#?setting_name$".
#
# To substitute a setting value, preserving trailing comments, use the sub regex like "[^[:space:]]+".
#
# For any setting block, be sure to end with 'next'. The default block will print out the original line.

BEGIN {
	auto_expl = 0
	stat_stmt = 0
}

$1 ~ "^#?work_mem" {
	sub("[^[:space:]]+", "16MB", $2)
	printf "work_mem = %s\n", $2
	next
}

$1 ~ "^#?wal_init_zero$" {
	sub("[^[:space:]]+", "off", $2)
	printf "wal_init_zero = %s\n", $2
	next
}

$1 ~ "^#?wal_recycle$" {
	sub("[^[:space:]]+", "off", $2)
	printf "wal_recycle = %s\n", $2
	next
}

$1 ~ "^#?jit$" {
	sub("[^[:space:]]+", "off", $2)
	printf "jit = %s\n", $2
	next
}

$1 ~ "^auto_explain$" {
	auto_expl = 1
}

$1 ~ "^pg_stat_statements$" {
	stat_stmt = 1
}

{
	# default unless matched and skipped via next: print out original line
	print $0
}

END {
	if ( !auto_expl ) {
		print ""
		print "#------------------------------------------------------------------------------"
		print "# AUTO EXPLAIN"
		print "#------------------------------------------------------------------------------"
		print "auto_explain.log_min_duration = 1000    # minimum number of ms execution time to log, -1 to disable"
		print "auto_explain.log_analyze = off          # do EXPLAIN ANLYZE logging (impacts performance)"
		print "auto_explain.log_verbose = off          # do EXPLAIN VERBOSE logging"
		print "auto_explain.log_nested_statements = on # log nested statements within statements"
	}
	if ( !stat_stmt ) {
		print ""
		print "#------------------------------------------------------------------------------"
		print "# STAT STATEMENTS"
		print "#------------------------------------------------------------------------------"
		print "pg_stat_statements.track = all"
		print "pg_stat_statements.track_utility = off"
	}
}
