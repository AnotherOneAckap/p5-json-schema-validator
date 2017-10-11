#!/usr/bin/perl
use strict;
use warnings;
use autodie;
use lib 'lib';

use JSON;
use Test::More;
use JSON::Schema::Validator::Draft6;

my $test_file = $ARGV[0];
my $test_case_no = $ARGV[1];

my $test_cases;

do {
	local $/;
	open my $fh, '<', $test_file;
	my $data = <$fh>;
	eval { $test_cases = decode_json $data };
	die "Can't parse test file $test_file: $@" if $@;
	close $fh;
};

die "File $test_file doesn't contain array of tests" unless $test_cases && ref $test_cases eq 'ARRAY';

plan tests => scalar @$test_cases;

my $i = 0;

for my $test_case ( @$test_cases ) {
	$i++;
	next if defined $test_case_no && $i != $test_case_no;

	warn "# TEST CASE $test_case->{description}\n";

	for my $t ( @{$test_case->{tests}} ) {
		my $result = JSON::Schema::Validator::Draft6::validate( $test_case->{schema}, $t->{data} );
		ok $result->{ok} == $t->{valid}, $t->{description};
	}
}

exit 0;
