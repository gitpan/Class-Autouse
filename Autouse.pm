package Class::Autouse;

use strict;
no strict 'refs';

# Become an exporter so we don't get 
# complaints when we act as a pragma
use base 'Exporter';
use Carp 'croak';
use UNIVERSAL;

# Globals
use vars qw{$VERSION $DEBUG};
use vars qw{$devel $superloader %chased %special};
BEGIN {
	$VERSION = 0.3;
	$devel = 0;
	$superloader = 0;
	%chased = ();
	$DEBUG = 0;
	%special = (
		main      => 1,
		UNIVERSAL => 1,
		CORE      => 1,
		);
		
}

# Developer mode flag
sub devel {
	print "Class::Autouse::devel\n" if $DEBUG;
	
	$devel = $_[ 1 ] ? 1 : 0; 
	return $devel;
}

# The main autouse sub
sub autouse(@) {
	print "Class::Autouse::autouse\n" if $DEBUG;
	
	# Remove any reference to ourselves, to allow us to
	# operate as a function, or a method
	shift if $_[ 0 ] eq 'Class::Autouse';
	
	# Ignore and return if nothing passed
	return 1 unless @_;
	
	my @classes = @_;
	foreach my $class ( @classes ) {
		# Control flag handling
		if ( $class eq ':superloader' ) {
			Class::Autouse->superloader();
			next;
		} elsif ( $class eq ':devel' ) {
			Class::Autouse->devel( 1 ); 
			next;
		}
		
		# Load load if in devel mode
		if ( $devel ) {
			Class::Autouse->load( $class ); next;
		}	
		
		# Get the file name
		my $file = _class2file( $class );
		_cry( "'$class' is not a module name" ) unless $file;
		
		# Has the module been loaded
		next if exists $INC{ $file };	
		
		# Make sure we will be able to 
		# load the module when we need to
		unless ( _class_file_exists( $file ) ) {
			_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
		}
		
		# Define the AUTOLOAD sub
		*{"${class}::AUTOLOAD"} = \&_autoload;
		
		# Put an %INC lock on the module to stop it being use'd
		$INC{$file} = 'Class::Autouse';
	}
}

# Link import to autouse, so we can act as a pragma
BEGIN {
	*import = *autouse;
}

# Happy Fun Super Loader!
# The process here to to replace the &UNIVERSAL::AUTOLOAD sub 
# ( which is just a dummy by default ) with a flexible class
# loader. This is evil, but should work nicely and produce a 
# nice level of magic :)
sub superloader {
	print "Class::Autouse::superloader\n" if $DEBUG;
	
	return 1 if $superloader;
	
	# Overwrite UNIVERSAL::AUTOLOAD
	*UNIVERSAL::AUTOLOAD = \&_autoload;
	
	# Attach a dummy sub to the DESTROY method of UNIVERSAL,
	# so that destroy calls don't make it to UNIVERSAL::AUTOLOAD
	# Now I THINK that this will be good enough
	# I'm assuming that nobody would be STUPID enough 
	# to handle a DESTROY call inside an AUTOLOAD... right...?
	# The other solution would be to handle it after the _autoload call
	# but this is a little
	*UNIVERSAL::DESTROY = \&_destroy;
	
	$superloader = 1;
}

sub class_exists {
	my $class = shift;
	my $name = shift;
	
	# Convert to a file name
	my $file = _class2file( $name );
	return undef unless $file;
	
	# Does the file exist
	return _class_file_exists( $file );
}
		




#####################################################################
# Main functional blocks

# Load can handle normal loading, loading from hooks,
# and skipping loading for things already loaded
sub load {
	print "Class::Autouse::load( '$_[1]' )\n" if $DEBUG;

	my $class = $_[1];
	_cry( "Did not specify a class to load" ) unless $class;

	# Is it a special module
	return 1 if _special( $class );
    	
	# Get the file
	my $file = _class2file( $class );
	_cry( "'$class' is not a module name" ) unless $file;
	
	if ( $INC{ $file } eq 'Class::Autouse' ) {	
		# One of ours. Remove the loader hook and %INC lock
		delete ${"${class}::"}{'AUTOLOAD'};
		delete $INC{ $file };

	} elsif ( $INC{ $file } ) {
		# Already loaded
		return 1;
	}
	
	print "Class::Autouse::load -> require $file\n" if $DEBUG;
	
	eval { require ${file} };
	if ( $@ ) {
		if ( $@ =~ /^Can't\slocate/ ) {
			_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
		} else {
			_cry( $@ . "Error loading class" );
		}
	}
}

# Get's linked via the symbol table to any AUTOLOADs are required
sub _autoload {
	print "Class::Autouse::_autoload(), AUTOLOAD = '$Class::Autouse::AUTOLOAD'\n" if $DEBUG;
	
	my $method = $Class::Autouse::AUTOLOAD;
	_cry( "You were missing a method name" ) unless $method;

	# Loop detection ( Just in case )
	$chased{ $method }++;
	_cry( "Undefined subroutine &$method called" ) if $chased{ $method } > 10;

	# Check for special classes
	my ( $original_class, $function ) = _split_sub( $method );
	if ( _special( $original_class, $function ) ) {
		_cry( "Undefined subroutine \&$method called" );
	}

	# First, search tree, loading as we go
	my (@search, %searched) = ();
	my @stack = ( $original_class, 'UNIVERSAL' );
	while ( @stack ) {
		my $class = shift @stack;

		# Skip if duplicate
		next if $searched{ $class };
		$searched{ $class } = 1;

		# Ensure class is loaded
		Class::Autouse->load( $class );
		
		# Check for a matching function
		if ( defined *{"${class}::$function"}{CODE} ) {
			# Goto the matching function
			goto &{"${class}::$function"};
		}

		# Add the class to the AUTOLOAD search stack,
		# and add the @ISA to the function search stack
		push @search, $class;
        	unshift @stack, @{"${class}::ISA"};
	}

	# Remove UNIVERSAL::AUTOLOAD
	pop @search if $search[-1] eq 'UNIVERSAL';
	
	# Check for package AUTOLOADs
	foreach my $class ( @search ) {
        	if ( defined *{ "${class}::AUTOLOAD" }{CODE} ) {
        		# Set the AUTOLOAD variable in the package
        		# we are about to go to, so the AUTOLOAD
        		# sub there will work properly
        		${"${class}::AUTOLOAD"} = $method;
        		        		
        		# Goto the target method
        		goto &{"${class}::AUTOLOAD"};
        	}
	}

	# Can't find the method anywhere. 
	# Throw the same error Perl does
	_cry( "Can't locate object method \"${function}\" via package \"${original_class}\"" );
}

sub _destroy {
	# This just handles a call and does nothing
}




#####################################################################
# Support subs

# Take a class name and turn it into a file name
sub _class2file {
	print "Class::Autouse::_class2file( '$_[0]' )\n" if $DEBUG;

	my $class = shift;
	$class =~ s!::!/!g;
	
	# Format check the result.
	return undef unless $class =~ /^[\w\/]+$/;
	return $class . '.pm';
}
		
# Does a class with a particular file name
# exist somewhere in our include array
sub _class_file_exists {
	print "Class::Autouse::_class_file_exists( '$_[0]' )\n" if $DEBUG;
	
	# Scan @INC for the file
	my $file = shift;
	foreach ( @INC ) { 
		return 1 if -f "$_/$file";
	}
	return undef;
}

# Is this a special class or function
sub _special {
	print "Class::Autouse::_special( '$_[0]' )\n" if $DEBUG;
	
	return $special{$_[0]} ? 1 : 0
}

# Split a fully resolved sub into it's package and sub name
sub _split_sub($) {
	print "Class::Autouse::_split_sub( '$_[0]' )\n" if $DEBUG;
	
	my $full = shift;
	my $colons = rindex( $full, '::' );
	return ( 
		substr( $full, 0, $colons ),
		substr( $full, $colons + 2 ) 
		);
}

# Establish our call depth
sub _call_depth {
	print "Class::Autouse::_carp_depth\n" if $DEBUG;
	
	# Search up the caller stack to find the first call that isn't us.
	my $level = 0;
	while( $level++ < 1000 ) {
		my @call = caller( $level );		
		my ( $subclass ) = _split_sub( $call[3] );
		unless ( $subclass eq 'Class::Autouse' ) {
			# Subtract 1 for this sub's call
			return $level - 1;
		}
	}
	croak( "Infinite loop trying to find call depth" );
}
	
# Die gracefully
sub _cry { 
	print "Class::Autouse::_cry\n" if $DEBUG;

	local $Carp::CarpLevel;
	$Carp::CarpLevel += _call_depth();
	croak( $_[0] );
}

1;
__END__

=pod

=head1 NAME

Class::Autouse - Defer loading of one or more classes.

=head1 SYNOPSIS

  # Load a class on method call
  use Class::Autouse;
  Class::Autouse->autouse( 'CGI' );
  print CGI->header();

  # Use as a pragma
  use Class::Autouse qw{CGI};
  
  # Use developer mode
  use Class::Autouse qw{:devel};
  
  # Turn on the Super Loader
  use Class::Autouse qw{:superloader};

=head1 DESCRIPTION

Class::Autouse allows you to specify a class the will only load when a 
method of that class is called. For large classes that might not be used
during the running of a program, such as Date::Manip, this can save
you large amounts of memory, and decrease the script load time.

=head2 Use as a pragma

Class::Autouse can be used as a pragma, specifying a list of classes
to load as the arguments. For example

   use Class::Autouse qw{CGI Data::Manip This::That};

is equivalent to

   use Class::Autouse;
   Class::Autouse->autouse( 'CGI' );
   Class::Autouse->autouse( 'Data::Manip' );
   Class::Autouse->autouse( 'This::That' );

=head2 Developer Mode

Class::Autouse features a developer mode. In developer mode, classes
are loaded immediately, just like they would be with a normal 'use'
statement. This allows error checking to be done while developing,
at the expense of a larger memory overhead. Developer mode is turned
on either with the C<devel> method, or using :devel in any of the 
pragma arguments. For example, this would load CGI.pm immediately.

    use Class::Autouse qw{:devel CGI};

While developer mode is equivalent to just using a normal use command, for
a large number of modules it lets you use autoloading notation, and just
comment or uncomment a single line to turn developer mode on or off

=head2 Super Loader

Turning on the Class::Autouse super loader allows you to automatically
load ANY class without specifying it first. Thus, the following will work
and is completely legal.

    use Class::Autouse qw{:superloader};

    print CGI->header;

The super loader can be turned on with either the Class::Autouse->superloader
method, or the :superloader pragma argument.

=head2 Class, not Module

The terminology "Class loading" instead of "Module loading" is used
intentionally. Modules will only be loaded if they are acting as a class.
That is, they will only be loaded during a Class->method call. If you try
do use a subroutine directly, say with C<Class::method()>, the class will
not be loaded. This limitation is made to allow more powerfull features in
other areas, because the module can focus on just loading the modules, and
not have to deal with importing.

=head1 METHODS

=head2 autouse( $class )

The autouse method sets the class to be loaded as required.

=head2 load( $class )

The load method loads one or more classes into memory. This is functionally
equivalent to using require to load the class list in, except that load
will detect and remove the autoloading hook from a previously autoused
class, whereas as use effectively ignore the class, and not load it.

=head2 devel

The devel method sets development mode on (argument of 1) or off (argument of 0)

=head2 superloader

The superloader method turns on the super loader. Please note that once you
have turned the superloader on, it cannot be turned off. This is due to
code that might be relying on it being there not being able to autoload it's
classes when another piece of code decides they don't want it any more, and
turns the superloader off.

=head2 class_exists

Handy method when doing to sort of jobs that Class::Autouse does. Given
a class name, it will return 1 if the class can be loaded ( i.e. in @INC ),
0 if the class can't be loaded, and undef if the class name is invalid.

Note that this does not actually load the class, just tests to see if it can
be loaded.

=head1 AUTHORS

 Adam Kennedy, cpan@ali.as
 Rob Napier,   rnapier@employees.org

=head1 SEE ALSO

autoload, autoclass

=cut
