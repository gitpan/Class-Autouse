#!/usr/bin/perl -w

# Formal testing for Class::Autouse

use strict;
use File::Spec::Functions qw{:ALL};
# Includes for development AND installation testing
use lib catdir( curdir(), 'modules' ),
        catdir( 't', 'modules' ),
        catdir( updir(), updir(), 'modules' );
use UNIVERSAL 'isa';
use Test::More tests => 10;

BEGIN { $| = 1 }




# Check their perl version
BEGIN {
	ok( $] >= 5.005, "Your perl is new enough" );
}





# Does the module load
use_ok( 'Class::Autouse' );



# Test the class_exists class detector
ok( Class::Autouse->class_exists( 'Class::Autouse' ), '->class_exists works for existing class' );
ok( ! Class::Autouse->class_exists( 'Class::Autouse::Nonexistant' ), '->class_exists works for non-existant class' );




# Test the can bug
ok( Class::Autouse->load( 'D' ), 'Test class D loads ok' );
ok( D->can('method'), "'can' found sub 'method' in D" );




# This should fail below Class::Autouse 0.8
# If class 'F' isa 'E' and method 'foo' in F uses SUPER::foo, make sure it find the method 'foo' in E.
ok( Class::Autouse->autouse( 'E' ), 'Test class E autouses ok' );
ok( Class::Autouse->autouse( 'F' ), 'Test class F autouses ok' );
ok( F->foo eq 'Return value from E->foo', 'Class->SUPER::method works safely' );




# This should fail for Class::Autouse 0.8 and 0.9
# If an non packaged based class is empty, but for an ISA to an existing class,
# and method 'foo' exists in the parent class, UNIVERSAL::can SHOULD return true.
# After the addition of the UNIVERSAL::can replacement Class::Autouse::_can, it didn't.
# In particular, this was causing problems with MakeMaker.
@G::ISA = 'E';
ok( G->can('foo'), "_can handles the empty class with \@ISA case correctly" );
