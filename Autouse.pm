package Class::Autouse;

use strict;
no strict 'refs';

# Become an exporter so we don't get 
# complaints when we act as a pragma
use base 'Exporter';
use Carp 'croak';

# Globals
use vars qw{$VERSION $DEBUG};
use vars qw{$this_package $devel $superloader %chased};
BEGIN {
	$VERSION = 0.2;
	$this_package = 'Class::Autouse';
	$devel = 0;
	$superloader = 0;
	%chased = ();
	$DEBUG = 0;
}

# Developer mode flag
sub devel {
	print "$this_package\::devel\n" if $DEBUG;
	
	$devel = $_[ 0 ] ? 1 : 0; 
	return $devel;
}

# The main autouse sub
sub autouse(@) {
	print "$this_package\::autouse\n" if $DEBUG;
	
	# Remove any reference to ourselves, to allow us to
	# operate as a function, or a method
	shift if $_[ 0 ] eq $this_package;
	
	# Ignore and return if nothing passed
	return 1 unless @_;
	
	my @classes = @_;
	foreach my $class ( @classes ) {
		# Control flag handling
		if ( $class eq ':superloader' ) {
			&superloader; next;
		} elsif ( $class eq ':devel' ) {
			&devel; next;
		}
		
		# Load load if in devel mode
		if ( $devel ) {
			load( $class ); next;
		}	
		
		# Get the file name
		my $file = _class2file( $class );
		_cry( "'$class' is not a module name" ) unless $file;
		
		# Has the module been loaded
		next if exists $INC{ $file };	
		
		# Make sure we will be able to 
		# load the module when we need to
		unless ( _class_exists( $file ) ) {
			# Note: Same error as Perl itself
			_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
		}
		
		# Define the AUTOLOAD sub
		*{"${class}::AUTOLOAD"} = sub { goto &{ _chase( ${"${this_package}::AUTOLOAD"} ) } };
		
		# Put an %INC lock on the module to stop it being use'd
		$INC{$file} = $this_package;
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
	print "$this_package\::superloader\n" if $DEBUG;
	
	return 1 if $superloader;
	
	# Overwrite UNIVERSAL::AUTOLOAD
	*UNIVERSAL::AUTOLOAD = sub { goto &{ _chase( ${"${this_package}::AUTOLOAD"} ) } };
	
	# Attach a dummy sub to the DESTROY method of UNIVERSAL,
	# so that destroy calls don't make it to UNIVERSAL::AUTOLOAD
	# Now I THINK that this will be good enough
	# I'm assuming that nobody would be STUPID enough 
	# to handle a DESTROY call inside an AUTOLOAD... right...?
	# The other solution would be to handle it after the _chase call
	# but this is much more elegant
	*UNIVERSAL::DESTROY = sub {};
	
	$superloader = 1;
}





#####################################################################
# Main functional blocks

# Load can handle normal loading, loading from hooks,
# and skipping loading for things already loaded
sub load {
	print "$this_package\::load( '$_[0]' )\n" if $DEBUG;

	my $class = shift;
	_cry( "Did not specify a class to load" ) unless $class;

	# Is it a special module
	return 1 if _special( $class );
    	
	# Get the file
	my $file = _class2file( $class );
	_cry( "'$class' is not a module name" ) unless $file;
	
	if ( $INC{ $file } eq $this_package ) {	
		# One of ours. Remove the loader hook and %INC lock
		delete ${"${class}::"}{'AUTOLOAD'};
		delete $INC{ $file };

	} elsif ( $INC{ $file } ) {
		# Already loaded
		return 1;
	}
	
	print "$this_package\::load -> require $file\n" if $DEBUG;
	
	eval { require ${file} };
	if ( $@ ) {
		if ( $@ =~ /^Can't\slocate/ ) {
			_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
		} else {
			_cry( $@ . "Error loading class" );
		}
	}
}

# Given a method name, do everything nescesary to 
# call the appropriate method for it, following
# @ISA, and loading modules as required
sub _chase {
	print "$this_package\::_chase( '$_[0]' )\n" if $DEBUG;
	
	my $method = shift;
	_cry( "You were missing a method name" ) unless $method;

	# Loop detection ( Just in case )
	_cry( "Undefined subroutine &$method called" ) if $chased{ $method } > 10;
	$chased{ $method }++;

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
		load( $class );
		
		# Check for a matching function
		if ( defined *{"${class}::${function}"}{CODE} ) {
			return "${class}::${function}";
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
        		${ "${class}::AUTOLOAD" } = $method;
        		        		
        		# Return the autoload method name to the goto
        		return "${class}::AUTOLOAD";
        	}
	}

	# Can't find the method anywhere. 
	# Throw the same error Perl does
	_cry( "Can't locate object method \"${function}\" via package \"${original_class}\"" );
}






#####################################################################
# Support subs

# Take a class name and turn it into a file name
sub _class2file {
	print "$this_package\::_class2file( '$_[0]' )\n" if $DEBUG;

	my $class = shift;
	$class =~ s!::!/!g;
	
	# Format check the result.
	return undef unless $class =~ /^[\w\/]+$/;
	return $class . '.pm';
}
		
# Does a class with a particular file name
# exist somewhere in our include array
sub _class_exists {
	print "$this_package\::_class_exists( '$_[0]' )\n" if $DEBUG;
	
	# Scan @INC for the file
	my $file = shift;
	foreach ( @INC ) { 
		return 1 if -f "$_/$file";
	}
	return undef;
}

# Is this a special class or function
sub _special {
	print "$this_package\::_special( '$_[0]' )\n" if $DEBUG;
	
	return 1 if $_[0] eq 'main';
	return 0;
}

# Split a fully resolved sub into it's package and sub name
sub _split_sub($) {
	print "$this_package\::_split_sub( '$_[0]' )\n" if $DEBUG;
	
	my $full = shift;
	my $colons = rindex( $full, '::' );
	return ( 
		substr( $full, 0, $colons ),
		substr( $full, $colons + 2 ) 
		);
}

# Establish our call depth
sub _call_depth {
	print "$this_package\::_carp_depth\n" if $DEBUG;
	
	# Search up the caller stack to find the first call that isn't us.
	my $level = 0;
	while( $level++ < 1000 ) {
		my @call = caller( $level );		
		my ( $subclass ) = _split_sub( $call[3] );
		unless ( $this_package eq $subclass ) {
			# Subtract 1 for this sub's call
			return $level - 1;
		}
	}
	croak( "Infinite loop trying to find call depth" );
}
	
# Die gracefully
sub _cry { 
	print "$this_package\::_cry\n" if $DEBUG;

	local $Carp::CarpLevel;
	$Carp::CarpLevel += _call_depth();
	croak( $_[0] );
}

1;
__END__

=pod

=head1 NAME

Class::Autouse - Defer loading of a class or arbitrary classes until one of 
                 it's methods is invoked.

=head1 SYNOPSIS

  # Load a class on demand
  use Class::Autouse;
  Class::Autouse->autouse( 'CGI' );
  print CGI->header();

  # Use as a pragma
  use Class::Autouse qw{CGI};
  
  # Turn on developer mode
  use Class::Autouse qw{:devel};
  
  # Turn on the super loader
  use Class::Autouse qw{:superloader};

=head1 DESCRIPTION

Class::Autouse allows you to specify a class the will only load when a 
method of the class is called. For large classes that might not be used
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
pragma arguments. For example, this would load CGI.pm immediately

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
method, or the :superloader pragma argument

=head2 Class, not Module

The terminology "Class loading" instead of "Module loading" is used
intentionally. Modules will only be loaded if they are acting as a class.
That is, they will only be loaded during a Class->method call. If you try
do use a subroutine directory, say with C<Class::method()>, the class will
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
class, whereas as use effectively ignore the class, and not load it

=head2 devel

The devel method sets development mode on (argument of 1) or off (argument of 0)

=head2 superloader

The superloader method turns on the super loader. Please note that once you
have turned the superloader on, it cannot be turned off. This is due to
code that might be relying on it being there not being able to load it's
classes when another piece of code decides they don't want it any more.

=head1 AUTHORS

 Adam Kennedy, cpan@ali.as
 Rob Napier,   rnapier@employees.org

=head1 SEE ALSO

autoload, autoclass

=cut
