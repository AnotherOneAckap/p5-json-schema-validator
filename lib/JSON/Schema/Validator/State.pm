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
	$state->{path}           = '$';
	$state->{schema_root}    = $args{schema};
	$state->{errors}         = {};
	$state->{schemas_by_url} = {};
	$state->{schemas_by_id}  = {};

	bless $state, $proto;

	$state->id_lookup;

	return $state;
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

sub id_lookup {
	my ( $state, $schema, $seen ) = @_;


	$schema ||= $state->{schema_root};
	$seen   ||= {};

	return unless defined $schema && ref $schema eq 'HASH';

	return if exists $seen->{$schema};

	$seen->{$schema} = 1;

	if ( exists $schema->{'$id'} ) {
		$state->{schemas_by_id}{ $schema->{'$id'} } = $schema;
	}

	while ( my ( $k, $subschema ) = each %$schema ) {
		$state->id_lookup( $subschema, $seen );
	}
}

1;
