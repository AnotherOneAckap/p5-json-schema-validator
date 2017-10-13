package JSON::Schema::Validator::State;
use strict;
use warnings;
use overload
	'==' => \&num_comparision,
	'""' => \&to_string,
	bool => \&to_string;

sub new {
	my ( $proto, %args ) = @_;

	my $state = {};
	$state->{path}   = '$';
	$state->{root}   = $args{schema};
	$state->{errors} = {};

	bless $state, $proto;
}

sub to_string { not keys %{$_[0]->{errors}} }
sub num_comparision { shift->to_string == shift }

sub add_path {
	my ( $state, $path ) = @_;
	$state->{path} .= ".$path";
}

sub add_error {
	my ( $state, $path, $msg ) = @_;

	$state->{errors}->{$path} ||= [];
	push @{ $state->{errors}->{$path} }, $msg;
}

1;
