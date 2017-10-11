package JSON::Schema::Validator::Draft6;
use strict;
use warnings;
use Data::Dumper;
use JSON::PP::Boolean;
use JSON qw( encode_json );

sub validate {
	my ( $schema, $instance, $path, $errors, $root ) = @_;

	my $result = 1;

	$path   = '$'     unless defined $path;
	$root   = $schema unless defined $root;
	$errors = {}      unless defined $errors;

	warn $path, encode_json $errors, "\n";

	if ( is_object($schema) ) {
		my @keywords = sort keys %$schema;

		for my $keyword (@keywords) {
			my $value;

			if ( $keyword eq '$ref' ) {
				$value = dereference( $schema->{$keyword}, $root );
				return validate( $value, $instance, $path, $errors, $root );
			}
			else {
				$value = ref $schema eq 'HASH' ? $schema->{$keyword} : $keyword;
			}

			no strict 'refs';
			my %symbols_table = %{ __PACKAGE__ . '::' };
			my $method_name   = "validate_$keyword";
			my $symbol        = $symbols_table{$method_name};

			if ( defined $symbol && *{$symbol}{CODE} ) {
				$result &&= $method_name->( $value, $instance, $path, $errors, $root );
			}
		}

		return $path eq '$' ? { ok => $result, errors => $errors } : $result;
	}
	elsif ( is_boolean($schema) ) {
		$result = $schema ? validate_true( $schema, $instance, $path, $errors, $root ) : validate_false( $schema, $instance, $path, $errors, $root );
		return $path eq '$' ? { ok => $result, errors => $errors } : $result;
	}

	die "JSON Schema MUST be an object or a boolean. See http://json-schema.org/latest/json-schema-core.html#rfc.section.4.4";
}

sub dereference {
	my ( $ref, $schema ) = @_;

	my @path = split '/', substr $ref, 2;

	my $result = $schema;

	$result = $result->{$_} for @path;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.4
#
# 6.4. minimum
# The value of "minimum" MUST be a number, representing an inclusive upper limit for a numeric instance.
# If the instance is a number, then this keyword validates only if the instance is greater than or exactly equal to "minimum".

sub validate_minimum {
	my ( $value, $instance, $path, $errors ) = @_;

	my $result = int $instance > $value;

	unless ($result) {
		$errors->{$path} ||= [];
		push @{ $errors->{$path} }, "minimum";
	}

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.17
#
# 6.17. required
# The value of this keyword MUST be an array. Elements of this array, if any, MUST be strings, and MUST be unique.
# An object instance is valid against this keyword if every item in the array is the name of a property in the instance.
# Omitting this keyword has the same behavior as an empty array.

sub validate_required {
	my ( $value, $instance, $path, $errors ) = @_;

	my $result = 1;

	for my $name (@$value) {
		unless ( exists $instance->{$name} ) {
			$errors->{$path} ||= [];
			push @{ $errors->{"$path.$name"} }, "required";
			$result = 0;
		}
	}

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.18
#
# 6.18. properties
# The value of "properties" MUST be an object. Each value of this object MUST be a valid JSON Schema.
# This keyword determines how child instances validate for objects, and does not directly validate the immediate instance itself.
# Validation succeeds if, for each name that appears in both the instance and as a name within this keyword's value, the child instance for that name successfully validates against the corresponding schema.
# Omitting this keyword has the same behavior as an empty object.

sub validate_properties {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	my $result = 1;

	my @properties = sort keys %$value;

	for my $name (@properties) {
		my $subschema = $value->{$name};

		if ( ref $instance eq 'HASH' && exists $instance->{$name} ) {
			#DBG my $res = validate( $subschema, $instance->{$name}, "$path.$name", $errors, $root );
			#DBG warn sprintf "validate_properties $name %s %s $res\n", $instance->{$name}, encode_json( $subschema );
			#DBG $result &&= $res;
			$result &&= validate( $subschema, $instance->{$name}, "$path.$name", $errors, $root );
		}
		# else skip validation
	}

	warn "properties $result\n";
	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.19
#
# 6.19. patternProperties
# The value of "patternProperties" MUST be an object. Each property name of this object SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect. Each property value of this object MUST be a valid JSON Schema.
# This keyword determines how child instances validate for objects, and does not directly validate the immediate instance itself. Validation of the primitive instance type against this keyword always succeeds.
# Validation succeeds if, for each instance name that matches any regular expressions that appear as a property name in this keyword's value, the child instance for that name successfully validates against each schema that corresponds to a matching regular expression.
# Omitting this keyword has the same behavior as an empty object.

sub validate_patternProperties {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of "patternProperties" MUST be an object. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.19' unless is_object( $value );

	return 1 unless is_object( $instance );

	my $result = 1;

	while ( my ( $re, $subschema ) = each %$value ) {
		my $qr = qr/$re/;

		for my $name ( keys %$instance ) {
			if ( $name =~ $qr ) {
				#DBG my $res = validate( $subschema, $instance->{$name}, "$path.$name", $errors, $root );
				#DBG warn sprintf "validate_patternProperties $name %s %s $res\n", encode_json($instance->{$name}), encode_json( $subschema );
				#DBG $result &&= $res;
				$result &&= validate( $subschema, $instance, "$path.$name", $errors, $root );
			}
		}
	}

	warn "patternProperties $result\n";
	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.20
#
# 6.20. additionalProperties
# The value of "additionalProperties" MUST be a valid JSON Schema.
# This keyword determines how child instances validate for objects, and does not directly validate the immediate instance itself.
# Validation with "additionalProperties" applies only to the child values of instance names that do not match any names in "properties", and do not match any regular expression in "patternProperties".
# For all such properties, validation succeeds if the child instance validates against the "additionalProperties" schema.
# Omitting this keyword has the same behavior as an empty schema.

sub validate_additionalProperties {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of "additionalProperties" MUST be an object. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.20' unless is_json_schema( $value );

	return 1 unless is_object( $instance );

	my $result = 1;

	my %properties = %{$root->{'properties'} || {}};
	my @pattern_properties = keys %{$root->{'patternProperties'} || {}};

	for my $name ( keys %$instance ) {
		next if exists $properties{ $name };
		next if grep { $name =~ qr/$_/ } @pattern_properties;
		my $res = validate( $value, $instance->{$name}, "$path.$name", $errors, $root );
		warn sprintf "validate_additionalProperties $name %s %s $res\n", encode_json([$instance->{$name}]), encode_json([ $value ]);
		$result &&= $res;
		#PROD $result &&= validate( $value, $instance->{$name}, "$path.$name", $errors, $root );
	}	

	warn "additionalProperties $result\n";
	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.25
#
# 6.25. type
# The value of this keyword MUST be either a string or an array. If it is an array, elements of the array MUST be strings and MUST be unique.
# String values MUST be one of the six primitive types ("null", "boolean", "object", "array", "number", or "string"), or "integer" which matches any number with a zero fractional part.
# An instance validates if and only if the instance is in any of the sets listed for this keyword.

sub validate_type {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	my $result = 1;

	my $type_validators = {
		null    => \&is_null,
		boolean => \&is_boolean,
		object  => \&is_object,
		array   => \&is_array,
		number  => \&is_number,
		integer => \&is_integer,
		string  => \&is_string,
	};

	for my $v ( ref $value eq 'ARRAY' ? @$value : $value ) {
		$result &&= $type_validators->{$value}->($instance);
		last if $result;
	}

	unless ($result) {
		$errors->{$path} ||= [];
		push @{ $errors->{$path} }, 'type';
	}

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.11
#
# 6.11. maxItems
# The value of this keyword MUST be a non-negative integer.
# An array instance is valid against "maxItems" if its size is less than, or equal to, the value of this keyword.

sub validate_maxItems {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die "The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.11" unless is_integer( $value ) && $value >= 0;

	return 1 unless is_array( $instance );

	return 1 if scalar @$instance <= $value;

	$errors->{$path} ||= [];
	push @{ $errors->{$path} }, 'maxItems';

	return 0;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.12
#
# 6.12. minItems
# The value of this keyword MUST be a non-negative integer.
# An array instance is valid against "minItems" if its size is greater than, or equal to, the value of this keyword.
# Omitting this keyword has the same behavior as a value of 0.

sub validate_minItems {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die "The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.12" unless is_integer( $value ) && $value >= 0;

	return 1 unless is_array( $instance );

	return 1 if scalar @$instance >= $value;

	$errors->{$path} ||= [];
	push @{ $errors->{$path} }, 'minItems';

	return 0;
}

sub validate_true {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	return 1;
}

sub validate_false {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	$errors->{$path} ||= [];
	push @{ $errors->{$path} }, 'false';

	return 0;
}

# Primitive type validators
sub is_null($) { !defined $_[0] }
sub is_boolean($) { defined $_[0] && ref $_[0] eq 'JSON::PP::Boolean' }
sub is_object($) { defined $_[0] && ref $_[0] && ref $_[0] eq 'HASH' }
sub is_array($)  { defined $_[0] && ref $_[0] && ref $_[0] eq 'ARRAY' }
sub is_number($) { defined $_[0] && $_[0] =~ /(?:[+-])?\d+(?:\.\d)?/ }
sub is_integer($) { defined $_[0] && $_[0] =~ /^[+-]?\d+$/ }
sub is_string($)  { defined $_[0] && !ref $_[0] }
sub is_json_schema($) { is_object( $_[0] ) || is_boolean( $_[0] ) }

1;
