#!/usr/bin/perl

# Formal testing for Class::Autouse

use strict;
use lib '../../../../modules'; # For development testing
use lib '../lib'; # For installation testing
use UNIVERSAL 'isa';
use Test::Simple tests => 4;

# Set up any needed globals
use vars qw{$loaded};
BEGIN {
	$loaded = 0;
	$| = 1;
}




# Check their perl version
BEGIN {
	ok( $] >= 5.005, "Your perl is new enough" );
}
	




# Does the module load
END { ok( 0, 'Class::Autouse loads' ) unless $loaded; }
use Class::Autouse;
$loaded = 1;
ok( 1, 'Class::Autouse loads' );




# Test the class_exists class detector
ok( Class::Autouse->class_exists( 'Class::Autouse' ), '->class_exists works for existing class' );
ok( ! Class::Autouse->class_exists( 'Class::Autouse::Nonexistant' ), '->class_exists works for non-existant class' );
