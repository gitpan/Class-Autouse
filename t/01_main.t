#!/usr/bin/perl -w

# Formal testing for Class::Autouse.
# While this isn't a particularly exhaustive unit test like script, 
# it does test every known bug and corner case discovered. As new bugs
# are found, tests are added to this test script.
# So if everything works for all the nasty corner cases, it should all work
# as advertised... we hope ;)

use strict;
use File::Spec::Functions qw{:ALL};
# Includes for development AND installation testing
use lib catdir( curdir(), 'modules' ),
        catdir( 't', 'modules' ),
        catdir( updir(), updir(), 'modules' );
use UNIVERSAL 'isa';
use Test::More tests => 14;

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






# This should fail in 0.8, 0.9 and 1.0
# Does ->can for an autoused class correctly load the class and find the method.
my $class = 'D';
ok( Class::Autouse->autouse( $class ), "Test class '$class' autoused ok" );
ok( $class->can('method2'), "'can' found sub 'method2' in autoused class '$class'" );
ok( $Class::Autouse::loaded{$class}, "'can' loaded class '$class' while looking for 'method2'" );

# Use the loaded hash again to avoid a warning
$_ = $Class::Autouse::loaded{$class};





# This may fail below Class::Autouse 0.8. If the above tests fail, ignore any failure.
# Does ->can follow the inheritance tree correctly when finding a method.
ok( $class->can('method'), "'can' found sub 'method' in '$class' ( from parent class 'C' )" );





# This should fail below Class::Autouse 0.8
# If class 'F' isa 'E' and method 'foo' in F uses SUPER::foo, make sure it find the method 'foo' in E.
ok( Class::Autouse->autouse( 'E' ), 'Test class E autouses ok' );
ok( Class::Autouse->autouse( 'F' ), 'Test class F autouses ok' );
ok( F->foo eq 'Return value from E->foo', 'Class->SUPER::method works safely' );




# This should fail for Class::Autouse 0.8 and 0.9
# If an non package based class is empty, except for an ISA to an existing class,
# and method 'foo' exists in the parent class, UNIVERSAL::can SHOULD return true.
# After the addition of the UNIVERSAL::can replacement Class::Autouse::_can, it didn't.
# In particular, this was causing problems with MakeMaker.
@G::ISA = 'E';
ok( G->can('foo'), "_can handles the empty class with \@ISA case correctly" );




# Catch bad uses of _can early.
is( Class::Autouse::_can(undef, 'foo'), undef, 'Giving bad stuff to _can returns expected' );
is( Class::Autouse::_can( 'something/random/that/isnt/c/class', 'paths' ), undef, 'Giving bad stuff to _can returns OK' );
