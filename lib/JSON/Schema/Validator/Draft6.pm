package JSON::Schema::Validator::Draft6;
use strict;
use warnings;
use JSON::Schema::Validator::State;
use Data::Dumper;
use JSON::PP::Boolean;
use JSON qw( encode_json decode_json );
use Scalar::Util qw( looks_like_number );
use Furl;

use constant DBG => 0;

sub validate {
	my ( $schema, $instance, $state ) = @_;

	my $result = 1;

	$state = JSON::Schema::Validator::State->new( schema => $schema ) unless $state;

	if ( is_object($schema) ) {
		my @keywords = sort keys %$schema;

		for my $keyword (@keywords) {
			my $value;

			if ( $keyword eq '$ref' ) {
				$value = dereference( $schema->{$keyword}, $state->{schema_root} );
				$state->{schema_root} = $value;
				return validate( $value, $instance, $state );
			}
			else {
				$value = ref $schema eq 'HASH' ? $schema->{$keyword} : $keyword;
			}

			no strict 'refs';
			my %symbols_table = %{ __PACKAGE__ . '::' };
			my $method_name   = "validate_$keyword";
			my $symbol        = $symbols_table{$method_name};

			if ( defined $symbol && *{$symbol}{CODE} ) {
				$method_name->( $value, $instance, $state );
			}
		}
	
		debug( 'validate', $state ) if DBG;
		return $state;
	}
	elsif ( is_boolean($schema) ) {
		validate_boolean( $schema, $instance, $state );

		debug( 'validate', $state ) if DBG;
		return $state;
	}

	die 'Not schema ', Data::Dumper::Dumper( $schema, $instance );
	die "JSON Schema MUST be an object or a boolean. See http://json-schema.org/latest/json-schema-core.html#rfc.section.4.4";
}

sub dereference {
	my ( $ref, $schema ) = @_;

	my $result;

	if ( $ref eq '#' ) {
		$result = $schema;
	}
	elsif ( 'http' eq substr $ref, 0, 4 ) {
		my $res = Furl->new->get( $ref );
		$result = decode_json $res->body;
	}
	else {
		my @path = split '/', substr $ref, 2;

		$result = $schema;

		for ( @path ) {
			if ( is_object($result) ) {
				$result = $result->{$_};
			}
			elsif( is_array($result) ) {
				$result = $result->[$_];
			}
			else {
				die Data::Dumper::Dumper( $result );
			}
		}
	}

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.1
#
# 6.1. multipleOf
# The value of "multipleOf" MUST be a number, strictly greater than 0.
# A numeric instance is valid only if division by this keyword's value results in an integer.

sub validate_multipleOf {
	my ( $value, $instance, $state ) = @_;

	die 'The value of "multipleOf" MUST be a number, strictly greater than 0. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.1' unless is_number( $value ) && $value > 0;

	return 1 unless is_number( $instance );

	my $result = is_integer( $instance / $value );

	$state->add_error( $state->{path} => "multipleOf" ) unless $result;

	debug( 'multipleOf', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.2
#
# 6.2. maximum
# The value of "maximum" MUST be a number, representing an inclusive upper limit for a numeric instance.
# If the instance is a number, then this keyword validates only if the instance is less than or exactly equal to "maximum".

sub validate_maximum {
	my ( $value, $instance, $state ) = @_;

	die 'The value of "maximum" MUST be a number, representing an inclusive upper limit for a numeric instance. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.2' unless is_number( $value );

	return 1 unless is_number( $instance );

	my $result = $instance <= $value;

	$state->add_error( $state->{path} => "maximum" ) unless $result;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.3
#
# 6.3. exclusiveMaximum
# The value of "exclusiveMaximum" MUST be number, representing an exclusive upper limit for a numeric instance.
# If the instance is a number, then the instance is valid only if it has a value strictly less than (not equal to) "exclusiveMaximum".

sub validate_exclusiveMaximum {
	my ( $value, $instance, $state ) = @_;

	die 'The value of "exclusiveMaximum" MUST be a number, representing an exclusive upper limit for a numeric instance. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.3' unless is_number( $value );

	return 1 unless is_number( $instance );

	my $result = $instance < $value;

	$state->add_error( $state->{path} => "exclusiveMaximum" ) unless $result;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.4
#
# 6.4. minimum
# The value of "minimum" MUST be a number, representing an inclusive upper limit for a numeric instance.
# If the instance is a number, then this keyword validates only if the instance is greater than or exactly equal to "minimum".

sub validate_minimum {
	my ( $value, $instance, $state ) = @_;

	die 'The value of "minimum" MUST be a number, representing an inclusive upper limit for a numeric instance. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.4' unless is_number( $value );

	return $state unless is_number( $instance );

	my $result = $instance >= $value;

	$state->add_error( $state->{path} => "minimum" ) unless $result;

	return $state;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.5
#
# 6.5. exclusiveMinimum
# The value of "exclusiveMinimum" MUST be number, representing an exclusive upper limit for a numeric instance.
# If the instance is a number, then the instance is valid only if it has a value strictly greater than (not equal to) "exclusiveMinimum".

sub validate_exclusiveMinimum {
	my ( $value, $instance, $state ) = @_;

	die 'The value of "exclusiveMinimum" MUST be a number, representing an exclusive upper limit for a numeric instance. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.5' unless is_number( $value );

	return 1 unless is_number( $instance );

	my $result = $instance > $value;

	$state->add_error( $state->{path} => "exclusiveMinimum" ) unless $result;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.6
#
# 6.6. maxLength
# The value of this keyword MUST be a non-negative integer.
# A string instance is valid against this keyword if its length is less than, or equal to, the value of this keyword.
# The length of a string instance is defined as the number of its characters as defined by RFC 7159 [RFC7159].

sub validate_maxLength {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.6' unless is_integer( $value ) && $value >= 0;

	return 1 unless is_string( $instance );

	my $result = length $instance <= $value;

	$state->add_error( $state->{path} => "maxLength" ) unless $result;

	debug( 'maxLength', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.7
#
# 6.7. minLength
# The value of this keyword MUST be a non-negative integer.
# A string instance is valid against this keyword if its length is greater than, or equal to, the value of this keyword.
# The length of a string instance is defined as the number of its characters as defined by RFC 7159 [RFC7159].
# Omitting this keyword has the same behavior as a value of 0.

sub validate_minLength {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.7' unless is_integer( $value ) && $value >= 0;

	return 1 unless is_string( $instance );

	my $result = length $instance >= $value;

	$state->add_error( $state->{path} => "minLength" ) unless $result;

	debug( 'minLength', $state ) if DBG;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.17
#
# 6.17. required
# The value of this keyword MUST be an array. Elements of this array, if any, MUST be strings, and MUST be unique.
# An object instance is valid against this keyword if every item in the array is the name of a property in the instance.
# Omitting this keyword has the same behavior as an empty array.

sub validate_required {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be an array. Elements of this array, if any, MUST be strings, and MUST be unique. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.17' unless is_array( $value );

	return 1 unless is_object( $instance );

	my $result = 1;

	for my $name (@$value) {
		next if exists $instance->{$name};
		$state->add_error( "$state->{path}.$name" => "required" );
		$result = 0;
	}

	debug( 'required', $state ) if DBG;

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
	my ( $value, $instance, $state ) = @_;

	my $result = 1;

	my @properties = sort keys %$value;

	for my $name (@properties) {
		my $subschema = $value->{$name};

		if ( ref $instance eq 'HASH' && exists $instance->{$name} ) {
			#DBG my $res = validate( $subschema, $instance->{$name}, $state );
			#DBG warn sprintf "validate_properties $name %s %s $res\n", $instance->{$name}, encode_json( $subschema );
			#DBG $result &&= $res;
			$state->add_path( $name );
			$result &&= validate( $subschema, $instance->{$name}, $state );
		}
		# else skip validation
	}

	debug( 'properties', $state ) if DBG;

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
	my ( $value, $instance, $state ) = @_;

	die 'The value of "patternProperties" MUST be an object. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.19' unless is_object( $value );

	return 1 unless is_object( $instance );

	my $result = 1;

	while ( my ( $re, $subschema ) = each %$value ) {
		my $qr = qr/$re/;

		for my $name ( keys %$instance ) {
			if ( $name =~ $qr ) {
				$state->add_path( $name );
				my $res = validate( $subschema, $instance->{$name}, $state );
				$result &&= $res;
			}
		}
	}

	debug( 'patternProperties', $state ) if DBG;

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
	my ( $value, $instance, $state ) = @_;

	die 'The value of "additionalProperties" MUST be an object. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.20' unless is_json_schema( $value );

	return 1 unless is_object( $instance );

	my $result = 1;

	my %properties = %{$state->{schema_root}{properties} || {}};
	my @pattern_properties = keys %{$state->{schema_root}{patternProperties} || {}};

	for my $name ( keys %$instance ) {
		next if exists $properties{ $name };
		next if grep { $name =~ qr/$_/ } @pattern_properties;
		$state->add_path( $name );
		my $res = validate( $value, $instance->{$name}, $state );
		$result &&= $res;
	}	

	debug( 'additionalProperties', $state ) if DBG;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.23
#
# 6.23. enum
# The value of this keyword MUST be an array. This array SHOULD have at least one element. Elements in the array SHOULD be unique.
# An instance validates successfully against this keyword if its value is equal to one of the elements in this keyword's array value.
# Elements in the array might be of any value, including null.

sub validate_enum {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be an array. This array SHOULD have at least one element. Elements in the array SHOULD be unique. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.23' unless is_array( $value ) && scalar @$value;

	my $json = JSON->new->allow_nonref->canonical;
	my %items = map { $json->encode( $_ ) => 1 } @$value;

	my $result = 0;

	my $encoded_instance = $json->encode( $instance );

	for ( @$value ) {
		$result = exists $items{ $encoded_instance };
		last if $result;
	}

	$state->add_error( $state->{path} => 'enum' ) unless $result;

	debug( 'enum', $state ) if DBG;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.24
#
# 6.24. const
# The value of this keyword MAY be of any type, including null.
# An instance validates successfully against this keyword if its value is equal to the value of the keyword.

sub validate_const {
	my ( $value, $instance, $state ) = @_;

	my $result = 0;
	
	my $json = JSON->new->allow_nonref->canonical;
	$result = $json->encode( $value ) eq $json->encode( $instance );

	$state->add_error( $state->{path} => 'const' ) unless $result;

	debug( 'const', $state ) if DBG;

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.25
#
# 6.25. type
# The value of this keyword MUST be either a string or an array. If it is an array, elements of the array MUST be strings and MUST be unique.
# String values MUST be one of the six primitive types ("null", "boolean", "object", "array", "number", or "string"), or "integer" which matches any number with a zero fractional part.
# An instance validates if and only if the instance is in any of the sets listed for this keyword.

sub validate_type {
	my ( $value, $instance, $state ) = @_;

	my $result = 0;

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
		$result ||= $type_validators->{$v}->($instance);
		last if $result;
	}

	$state->add_error( $state->{path} => 'type' ) unless $result;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.26
#
# 6.26. allOf
# This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema.
# An instance validates successfully against this keyword if it validates successfully against all schemas defined by this keyword's value.

sub validate_allOf {
	my ( $value, $instance, $state ) = @_;

	die "This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.26" unless is_array( $value ) && scalar @$value;

	my $result = 1;

	for my $subschema ( @$value ) {
		$result &&= validate( $subschema, $instance, $state );
	}

	debug( 'allOf', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.27
#
# 6.27. anyOf
# This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema.
# An instance validates successfully against this keyword if it validates successfully against at least one schema defined by this keyword's value.

sub validate_anyOf {
	my ( $value, $instance, $state ) = @_;

	die "This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.27" unless is_array( $value ) && scalar @$value;

	my $result = 0;

	for my $subschema ( @$value ) {
		$result = validate( $subschema, $instance, JSON::Schema::Validator::State->new( path => $state->{path}, schema_root => $state->{schema_root} ) );
		last if $result;
	}

	$state->add_error( $state->{path} => 'anyOf' ) unless $result;

	debug( 'anyOf', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.28
#
# 6.28. oneOf
# This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema.
# An instance validates successfully against this keyword if it validates successfully against exactly one schema defined by this keyword's value.

sub validate_oneOf {
	my ( $value, $instance, $state ) = @_;

	die "This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.27" unless is_array( $value ) && scalar @$value;

	my $result = 0;

	for ( @$value ) {
		my $res = validate( $_, $instance, JSON::Schema::Validator::State->new( path => $state->{path}, schema_root => $state->{schema_root} ) );

		if ( $res ) {
			if ( $result ) {
				$result = 0;
				last;
			}
			else {
				$result = 1;
			}
		}
	}

	$state->add_error( $state->{path} => 'oneOf' ) unless $result;

	debug( 'oneOf', $state ) if DBG;

	return $state;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.8
#
# 6.8. pattern
# The value of this keyword MUST be a string. This string SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect.
# A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.

sub validate_pattern {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a string. This string SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.8' unless is_string( $value );

	return $state unless is_string( $instance );

	$state->add_error( $state->{path} => 'pattern' ) unless $instance =~ qr/$value/;

	return $state;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.9
#
# 6.9. items
# The value of "items" MUST be either a valid JSON Schema or an array of valid JSON Schemas.
# This keyword determines how child instances validate for arrays, and does not directly validate the immediate instance itself.
# If "items" is a schema, validation succeeds if all elements in the array successfully validate against that schema.
# If "items" is an array of schemas, validation succeeds if each element of the instance validates against the schema at the same position, if any.
# Omitting this keyword has the same behavior as an empty schema.

sub validate_items {
	my ( $value, $instance, $state ) = @_;

	my $result = 1;

	return 1 unless is_array( $instance );

	if ( is_json_schema( $value ) ) {
		for ( my $i = 0; $i < scalar @$instance; $i++ ) {
			$state->add_path( $i );
			$result &&= validate( $value, $instance->[$i], $state );
		}

		debug( 'items', $state ) if DBG;

		return $result;
	}
	elsif ( is_array( $value ) ) {
		for ( my $i = 0; $i < scalar @$instance; $i++ ) {
			next unless defined $value->[$i];
			$state->add_path( $i );
			$result &&= validate( $value->[$i], $instance->[$i], $state );
		}

		debug( 'items', $state ) if DBG;

		return $result;
	}

	die 'The value of "items" MUST be either a valid JSON Schema or an array of valid JSON Schemas. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.9';
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.10
#
# 6.10. additionalItems
# The value of "additionalItems" MUST be a valid JSON Schema.
# This keyword determines how child instances validate for arrays, and does not directly validate the immediate instance itself.
# If "items" is an array of schemas, validation succeeds if every instance element at a position greater than the size of "items" validates against "additionalItems".
# Otherwise, "additionalItems" MUST be ignored, as the "items" schema (possibly the default value of an empty schema) is applied to all elements.
# Omitting this keyword has the same behavior as an empty schema.

sub validate_additionalItems {
	my ( $value, $instance, $state ) = @_;

	die 'The value of "additionalItems" MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.10' unless is_json_schema( $value );

	return 1 unless is_array( $state->{schema_root}{items} ) && is_array( $instance );

	my $result = 1;

	for ( my $i = scalar @{$state->{schema_root}{items}}; $i < scalar @$instance; $i++ ) {
		$state->add_path( $i );
		$result &&= validate( $value, $instance->[$i], $state );
	}

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.11
#
# 6.11. maxItems
# The value of this keyword MUST be a non-negative integer.
# An array instance is valid against "maxItems" if its size is less than, or equal to, the value of this keyword.

sub validate_maxItems {
	my ( $value, $instance, $state ) = @_;

	die "The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.11" unless is_integer( $value ) && $value >= 0;

	return 1 unless is_array( $instance );

	return 1 if scalar @$instance <= $value;

	$state->add_error( $state->{path} => 'maxItems' );

	return 0;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.12
#
# 6.12. minItems
# The value of this keyword MUST be a non-negative integer.
# An array instance is valid against "minItems" if its size is greater than, or equal to, the value of this keyword.
# Omitting this keyword has the same behavior as a value of 0.

sub validate_minItems {
	my ( $value, $instance, $state ) = @_;

	die "The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.12" unless is_integer( $value ) && $value >= 0;

	return 1 unless is_array( $instance );

	return 1 if scalar @$instance >= $value;

	$state->add_error( $state->{path} => 'minItems' );

	return 0;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.13
#
# 6.13. uniqueItems
# The value of this keyword MUST be a boolean.
# If this keyword has boolean value false, the instance validates successfully. If it has boolean value true, the instance validates successfully if all of its elements are unique.
# Omitting this keyword has the same behavior as a value of false.

sub validate_uniqueItems {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a boolean. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.13' unless is_boolean( $value );

	return 1 unless $value;

	return 1 unless is_array( $instance );

	my $json = JSON->new->allow_nonref;

	my %items = map { $json->encode($_) => 1 } @$instance;

	my $result = scalar @$instance == scalar keys %items;

	$state->add_error( $state->{path} => 'uniqueItems' ) unless $result;

	debug( 'uniqueItems', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.14
#
# 6.14. contains
# The value of this keyword MUST be a valid JSON Schema.
# An array instance is valid against "contains" if at least one of its elements is valid against the given schema.

sub validate_contains {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.14' unless is_json_schema( $value );

	return 1 unless is_array( $instance );

	my $result = 0;

	for ( my $i = 0; $i < scalar @$instance; $i++ ) {
		$result = validate( $value, $instance->[$i], JSON::Schema::Validator::State->new( path => "$state->{path}.$i", schema_root => $state->{schema_root} ) );
		last if $result;
	}

	$state->add_error( $state->{path} => 'contains' ) unless $result;

	debug( 'contains', $state, $result ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.15
#
# 6.15. maxProperties
# The value of this keyword MUST be a non-negative integer.
# An object instance is valid against "maxProperties" if its number of properties is less than, or equal to, the value of this keyword.

sub validate_maxProperties {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.15' unless is_integer( $value ) && $value >= 0;

	return 1 unless is_object( $instance );

	my $result = scalar keys %$instance <= $value;

	$state->add_error( $state->{path} => 'maxProperties' ) unless $result;

	debug( 'maxProperties', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.16
#
# 6.16. minProperties
# The value of this keyword MUST be a non-negative integer.
# An object instance is valid against "minProperties" if its number of properties is greater than, or equal to, the value of this keyword.
# Omitting this keyword has the same behavior as a value of 0.

sub validate_minProperties {
	my ( $value, $instance, $state ) = @_;

	die 'The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.15' unless is_integer( $value ) && $value >= 0;

	return 1 unless is_object( $instance );

	my $result = scalar keys %$instance >= $value;

	$state->add_error( $state->{path} => 'minProperties' ) unless $result;

	debug( 'minProperties', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.29
#
# 6.29. not
# This keyword's value MUST be a valid JSON Schema.
# An instance is valid against this keyword if it fails to validate successfully against the schema defined by this keyword.

sub validate_not {
	my ( $value, $instance, $state ) = @_;

	die "This keyword's value MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.29" unless is_json_schema( $value );

	# need new state here to ignore errors, that can be found inside
	my $result = not validate( $value, $instance, JSON::Schema::Validator::State->new( path => $state->{path}, schema_root => $state->{schema_root} ) );

	$state->add_error( $state->{path} => 'not' ) unless $result;

	debug( 'not', $state ) if DBG;

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.7.1
#
# 7.1. definitions
# This keyword's value MUST be an object. Each member value of this object MUST be a valid JSON Schema.
# This keyword plays no role in validation per se. Its role is to provide a standardized location for schema authors to inline JSON Schemas into a more general schema.

sub validate_definitions {
	my ( $value, $instance, $state ) = @_;

	die "This keyword's value MUST be an object. Each member value of this object MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.7.1" unless is_object( $value );

	return 1;
}

sub validate_boolean {
	my ( $value, $instance, $state ) = @_;

	if ( $value ) {
		debug( 'true', $state ) if DBG;
		return $state;
	}
	else {
		$state->add_error( $state->{path} => 'false' );
		debug( 'false', $state ) if DBG;
		return $state;
	}
}

# Primitive type validators
sub is_null($) {
	!defined $_[0]
}

sub is_boolean($) { defined $_[0] && ref $_[0] eq 'JSON::PP::Boolean' }
sub is_object($) { defined $_[0] && ref $_[0] && ref $_[0] eq 'HASH' }
sub is_array($)  { defined $_[0] && ref $_[0] && ref $_[0] eq 'ARRAY' }

sub is_number($) {
	my $result = defined $_[0] && ! ref $_[0] && looks_like_number $_[0];
	return $result;
}

sub is_integer($) {
	my $result = defined $_[0] && ! ref $_[0] && looks_like_number $_[0] && $_[0] =~ /^[+-]?\d+$/;
	return $result;
}

sub is_string($)  {
	my $result = defined $_[0] && ! ref $_[0] && ! looks_like_number $_[0];
	return $result;
}

sub is_json_schema($) { is_object( $_[0] ) || is_boolean( $_[0] ) }

sub debug {
	my ( $check, $state ) = @_;
	warn sprintf "# '%s' for %s is %s\n", $check, $state->{path}, $state ? 1 : 0;
}

1;
