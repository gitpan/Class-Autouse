#!/usr/bin/perl -w

use strict;
use File::Spec::Functions qw{:ALL};
use lib catdir( updir(), updir(), 'modules' ),
        catdir( curdir(), 'modules' ); # Development testing
use lib catdir( 't', 'modules' ); # Installation testing
use UNIVERSAL 'isa';
use Test::More tests => 4;
use Class::Autouse qw{:devel};

# Set up any needed globals
BEGIN {
        $| = 1;
}




# Check their perl version
BEGIN {
        ok( $] >= 5.005, "Your perl is new enough" );
}





# Does the module load
use_ok( 'Class::Autouse::Parent' );


# Test the loading of children
use_ok( 'A' );
ok( $A::B::loaded, 'Parent class loads child class OK' );
$A::B::loaded ? 1 : 0 # Shut a warning up

