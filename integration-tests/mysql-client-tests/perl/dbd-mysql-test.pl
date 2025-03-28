use strict;

use DBI;

my $QUERY_RESPONSE = [
    { "create table test (pk int, `value` int, primary key(pk))" => '0E0' },
    { "describe test" => 2 },
    { "insert into test (pk, `value`) values (0,0)" => 1 },
    { "select * from test" => 1 },
    {"select dolt_add('-A');" => 1 },
    {"select dolt_commit('-m', 'my commit')" => 1},
    {"select dolt_checkout('-b', 'mybranch')" => 1 },
    {"insert into test (pk, `value`) values (1,1)" => 1 },
    {"select dolt_commit('-a', '-m', 'my commit2')" => 1 },
    {"select dolt_checkout('main')" => 1 },
    {"select dolt_merge('mybranch')" => 1 },
    {"select COUNT(*) FROM dolt_log" => 1 },
];

my $user = $ARGV[0];
my $port = $ARGV[1];
my $db   = $ARGV[2];

my $dsn = "DBI:mysql:database=$db;host=127.0.0.1;port=$port";
my $dbh = DBI->connect($dsn, $user, "");

foreach my $query_response ( @{$QUERY_RESPONSE} ) {
    my @query_keys = keys %{$query_response};
    my $query      = $query_keys[0];
    my $exp_result = $query_response->{$query};

    my $result = $dbh->do($query);
    if ( $result != $exp_result ) {
	print "QUERY: $query\n";
	print "EXPECTED: $exp_result\n";
	print "RESULT: $result\n";
	exit 1
    }
}

exit 0;
