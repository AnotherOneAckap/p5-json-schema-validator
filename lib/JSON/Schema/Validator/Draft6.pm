package JSON::Schema::Validator::Draft6;
use strict;
use warnings;
use Data::Dumper;
use JSON::PP::Boolean;
use JSON qw( encode_json );
use Scalar::Util qw( looks_like_number );

use constant DBG => 0;

sub validate {
	my ( $schema, $instance, $path, $errors, $root ) = @_;

	my $result = 1;

	$path   = '$'     unless defined $path;
	$root   = $schema unless defined $root;
	$errors = {}      unless defined $errors;

	warn "# ", $path, encode_json $errors, "\n" if DBG;

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

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.2
#
# 6.2. maximum
# The value of "maximum" MUST be a number, representing an inclusive upper limit for a numeric instance.
# If the instance is a number, then this keyword validates only if the instance is less than or exactly equal to "maximum".

sub validate_maximum {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of "maximum" MUST be a number, representing an inclusive upper limit for a numeric instance. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.2' unless is_number( $value );

	return 1 unless is_number( $instance );

	my $result = $instance <= $value;

	unless ($result) {
		$errors->{$path} ||= [];
		push @{ $errors->{$path} }, "maximum";
	}

	return $result;
}

# See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.4
#
# 6.4. minimum
# The value of "minimum" MUST be a number, representing an inclusive upper limit for a numeric instance.
# If the instance is a number, then this keyword validates only if the instance is greater than or exactly equal to "minimum".

sub validate_minimum {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of "minimum" MUST be a number, representing an inclusive upper limit for a numeric instance. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.4' unless is_number( $value );

	return 1 unless is_number( $instance );

	my $result = $instance >= $value;

	unless ($result) {
		$errors->{$path} ||= [];
		push @{ $errors->{$path} }, "minimum";
	}

	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.6
#
# 6.6. maxLength
# The value of this keyword MUST be a non-negative integer.
# A string instance is valid against this keyword if its length is less than, or equal to, the value of this keyword.
# The length of a string instance is defined as the number of its characters as defined by RFC 7159 [RFC7159].

sub validate_maxLength {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.6' unless is_integer( $value ) && $value >= 0;

	return 1 unless is_string( $instance );

	my $result = length $instance <= $value;

	unless ($result) {
		$errors->{$path} ||= [];
		push @{ $errors->{$path} }, "maxLength";
	}

	warn "# maxLength $result\n" if DBG;
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
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of this keyword MUST be a non-negative integer. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.7' unless is_integer( $value ) && $value >= 0;

	return 1 unless is_string( $instance );

	my $result = length $instance >= $value;

	unless ($result) {
		$errors->{$path} ||= [];
		push @{ $errors->{$path} }, "minLength";
	}

	warn "# minLength $result\n" if DBG;
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

	die 'The value of this keyword MUST be an array. Elements of this array, if any, MUST be strings, and MUST be unique. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.17' unless is_array( $value );

	my $result = 1;

	for my $name (@$value) {
		next if exists $instance->{$name};
		$errors->{$path} ||= [];
		push @{ $errors->{"$path.$name"} }, "required";
		$result = 0;
	}

	warn "# required $result\n" if DBG;
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

	warn "# properties $result\n" if DBG;
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
				my $res = validate( $subschema, $instance->{$name}, "$path.$name", $errors, $root );
				warn sprintf "validate_patternProperties $name %s %s $res\n", ( ref $instance->{$name} ? encode_json($instance->{$name}) : $instance->{$name} ), ( ref $subschema ? encode_json( $subschema ) : $subschema ) if DBG;
				$result &&= $res;
			}
		}
	}

	warn "# patternProperties $result\n" if DBG;
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
		warn sprintf "# validate_additionalProperties $name %s %s $res\n", encode_json([$instance->{$name}]), encode_json([ $value ]) if DBG;
		$result &&= $res;
		#PROD $result &&= validate( $value, $instance->{$name}, "$path.$name", $errors, $root );
	}	

	warn "# additionalProperties $result\n" if DBG;
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

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.26
#
# 6.26. allOf
# This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema.
# An instance validates successfully against this keyword if it validates successfully against all schemas defined by this keyword's value.

sub validate_allOf {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die "This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.26" unless is_array( $value ) && scalar @$value;

	my $result = 1;

	for my $subschema ( @$value ) {
		$result &&= validate( $subschema, $instance, "$path.allOf", $errors, $root );# TODO
	}

	warn "# allOf $result\n" if DBG;
	return $result;
}

# http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.27
#
# 6.27. anyOf
# This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema.
# An instance validates successfully against this keyword if it validates successfully against at least one schema defined by this keyword's value.

sub validate_anyOf {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die "This keyword's value MUST be a non-empty array. Each item of the array MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.27" unless is_array( $value ) && scalar @$value;

	my $result = 0;

	for my $subschema ( @$value ) {
		$result = validate( $subschema, $instance, "$path.anyOf", $errors, $root );# TODO
		last if $result;
	}

	warn "# anyOf $result\n" if DBG;
	return $result;
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
	my ( $value, $instance, $path, $errors, $root ) = @_;

	my $result = 1;

	return 1 unless is_array( $instance );

	if ( is_json_schema( $value ) ) {
		for ( my $i = 0; $i < scalar @$instance; $i++ ) {
			$result &&= validate( $value, $instance->[$i], "$path.$i", $errors, $root );
		}

		warn "# items $result\n" if DBG;
		return $result;
	}
	elsif ( is_array( $value ) ) {
		for ( my $i = 0; $i < scalar @$instance; $i++ ) {
			next unless defined $value->[$i];
			$result &&= validate( $value->[$i], $instance->[$i], "$path.$i", $errors, $root );
		}

		warn "# items $result\n" if DBG;
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
	my ( $value, $instance, $path, $errors, $root ) = @_;

	die 'The value of "additionalItems" MUST be a valid JSON Schema. See http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.10' unless is_json_schema( $value );

	return 1 unless is_array( $root->{items} ) && is_array( $instance );

	my $result = 1;

	for ( my $i = scalar @{$root->{items}}; $i < scalar @$instance; $i++ ) {
		$result &&= validate( $value, $instance->[$i], "$path.$i", $errors, $root );
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

	warn "# true 1\n" if DBG;
	return 1;
}

sub validate_false {
	my ( $value, $instance, $path, $errors, $root ) = @_;

	$errors->{$path} ||= [];
	push @{ $errors->{$path} }, 'false';

	warn "# false 0\n" if DBG;
	return 0;
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
	warn "# number $result\n" if DBG;
	return $result;
}

sub is_integer($) {
	my $result = defined $_[0] && ! ref $_[0] && looks_like_number $_[0] && $_[0] =~ /^[+-]?\d+$/;
	warn "# integer $result\n" if DBG;
	return $result;
}

sub is_string($)  {
	my $result = defined $_[0] && ! ref $_[0] && ! looks_like_number $_[0];
	warn "# string $result\n" if DBG;
	return $result;
}

sub is_json_schema($) { is_object( $_[0] ) || is_boolean( $_[0] ) }

1;
