package Class::Autouse;

# See POD for documentation

require 5.004;
use strict;
no strict 'refs';

# Become an exporter so we don't get 
# complaints when we act as a pragma
use base 'Exporter';
use Carp 'croak', 'confess';
use UNIVERSAL;

# Globals
use vars qw{$VERSION $DEBUG};
use vars qw{$devel $superloader %chased %special};
use vars qw{$SLASH};
BEGIN {
	$VERSION = 0.5;
	$devel = 0;
	$superloader = 0;
	%chased = ();
	$DEBUG = 0;
	%special = (
		main      => 1,
		UNIVERSAL => 1,
		CORE      => 1,
		);
	
	# Determine the path seperator.
	# We do this by finding the platform.
	# We do THAT by looking at the newline
	if ( "\n" eq "\012" ) { 
		$SLASH = "/";  # Unix
	} elsif ( "\n" eq "\015" ) {
		$SLASH = ":";  # Mac
	} else {
		$SLASH = "\\"; # Win32
	}	
}

# Developer mode flag
sub devel {
	print _debug(\@_,1) if $DEBUG;
	
	$devel = $_[ 1 ] ? 1 : 0; 
}

# Happy Fun Super Loader!
# The process here is to replace the &UNIVERSAL::AUTOLOAD sub 
# ( which is just a dummy by default ) with a flexible class loader.
sub superloader {
	print _debug(\@_,1) if $DEBUG;
	
	return 1 if $superloader;
	
	# Overwrite UNIVERSAL::AUTOLOAD and also
	# catch destroy calls so they don't trigger AUTOLOAD.
	*UNIVERSAL::AUTOLOAD = \&_autoload;
	*UNIVERSAL::DESTROY = \&_destroy;
	$superloader = 1;
}

# The main autouse sub
sub autouse {
	# Remove any reference to ourselves, to allow us to
	# operate as a function, or a method
	shift if $_[ 0 ] eq 'Class::Autouse';
	return 1 unless scalar @_;

	print _debug(\@_) if $DEBUG;
	
	# Ignore and return if nothing passed
	return 1 unless scalar @_;
	
	my @classes = @_;
	foreach my $class ( @classes ) {
		# Skip accidental empty arguments
		next unless $class;
		
		# Control flag handling
		if ( $class =~ s/^:// ) {
			if ( $class eq 'superloader' ) {
				# Turn on the superloader
				Class::Autouse->superloader();
			} elsif ( $class eq 'devel' ) {
				# Turn on devel mode
				Class::Autouse->devel( 1 ); 
			} elsif ( $class eq 'debug' ) {
				# Turn on debugging
				$DEBUG = 1;
				print _call_depth(1) . "Class::Autouse::autoload -> Debugging Activated.\n";
			}
			next;
		}
		
		# Load now if in devel mode
		if ( $devel ) {
			Class::Autouse->load( $class );
			next;
		}	
		
		# Get the file name
		my $file = _class_file( $class ) or _cry( "'$class' is not a module name" );
				
		# Is the class installed?
		next if exists $INC{ $file };	
		unless ( _file_exists( $file ) ) {
			_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
		}
		
		# Don't actually do anything if the superloader is on
		next if $superloader;
		
		# Add the AUTOLOAD hook and %INC lock to prevent 'use'ing
		*{"$class\::AUTOLOAD"} = \&_autoload;
		$INC{$file} = 'Class::Autouse';
	}
	return 1;
}

# Link import to autouse, so we can act as a pragma
BEGIN { 
	*import = *autouse;
}

# Load a class
sub load {
	print _debug(\@_,1) if $DEBUG;

	my $class = $_[1] or _cry( "Did not specify a class to load" );

	# Is it a special module
	return 1 if $special{$class};
    	
	# Get the file
	my $file = _class_file( $class ) or _cry( "'$class' is not a module name" );

	# Check if the %INC lock exists
	if ( $INC{$file} eq 'Class::Autouse' ) {	
		# Remove the AUTOLOAD hook and %INC lock
		delete ${"$class\::"}{'AUTOLOAD'};
		delete $INC{ $file };
	} elsif ( $INC{$file} ) {
		# Already loaded
		return 1;
	}
	
	# Get the full filename
	my $filename = _file_exists( $file );
	unless ( $filename ) {
		# File doesn't exist.
		# Is it a package in another module
		return 1 if _namespace_occupied( $class );

		# Doesn't exist
		_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
	}			
	
	# Load the file
	if ( $DEBUG ) {
		print _call_depth(1) . "  Class::Autouse::load -> Loading in $file\n";
	}
	eval { require $filename };
	_cry( $@ ) if $@;

	# Mark that the class has been loaded
	$INC{$file} = $filename;
	
	return 1;
}

# Is a particular class installed in out @INC somewhere
# OR is it loaded in our program already
sub class_exists {
	print _debug(\@_,1) if $DEBUG;
	
	# Is it loaded already?
	return 1 if _namespace_occupied( $_[1] );

	# Does the file exist
	my $file = _class_file( $_[1] ) or return undef;
	return _file_exists( $file ) ? 1 : 0;
}

# Recursive methods currently only work withing the scope of the single @INC
# entry containing the "top" module, and will probably stay this way

# Autouse not only a class, but all others below it.
sub autouse_recursive {
	print _debug(\@_,1) if $DEBUG;

	# Hand things over to the main recursive method as needed
	if ( $devel ) {
		return _recursive( $_[1], 'load' );
	} else {
		return 1 if $superloader;
		return _recursive( $_[1], 'autouse' );
	}
}

# Load not only a class and all others below it
sub load_recursive {
	print _debug(\@_,1) if $DEBUG;
	
	# Hand over the the main recursion method.
	return _recursive( $_[1], 'load' );
}





#####################################################################
# Symbol table private methods, and major logical blocks
#
# These get hooked to various places on the symbol table,
# to enable the autoload functionality

# Get's linked via the symbol table to any AUTOLOADs are required
sub _autoload {
	print (_debug(\@_) . ", AUTOLOAD = '$Class::Autouse::AUTOLOAD'\n") if $DEBUG;
	
	my $method = $Class::Autouse::AUTOLOAD or _cry( "Missing method name" );

	# Loop detection ( Just in case )
	_cry( "Undefined subroutine &$method called" ) if ++$chased{ $method } > 10;

	# Check for special classes
	my ($class, $function) = m/^(.*)::(.*)$/o;
	_cry( "Undefined subroutine \&$method called" ) if $special{$class};

	# First, search tree, loading as we go
	my (@search, %searched) = ();
	my @stack = ( $class, 'UNIVERSAL' );
	while ( my $c = shift @stack ) {
		# Skip if duplicate
		next if $searched{$c};
		$searched{$c} = 1;

		# Ensure class is loaded
		Class::Autouse->load($c);
		
		# Check for a matching function
		goto &{"$c\::$function"} if defined *{"$c\::$function"}{CODE};

		# Add the class to the AUTOLOAD search stack,
		# and add the @ISA to the function search stack
		push @search, $c unless $c eq 'UNIVERSAL';
        	unshift @stack, @{"$c\::ISA"};
	}
	
	# Check for package AUTOLOADs
	foreach my $c ( @search ) {
        	if ( defined *{ "$c\::AUTOLOAD" }{CODE} ) {
        		# Set the AUTOLOAD variable in the package
        		# we are about to go to, so the AUTOLOAD
        		# sub there will work properly
        		${"$c\::AUTOLOAD"} = $method;
        		        		
        		# Goto the target method
        		goto &{"$c\::AUTOLOAD"};
        	}
	}

	# Can't find the method anywhere. 
	# Throw the same error Perl does
	_cry( "Can't locate object method \"$function\" via package \"$class\"" );
}

sub _destroy {
	print _debug(\@_) if $DEBUG;
	
	# This just handles a call and does nothing
}

# Perform an action on a class recursively
sub _recursive {
	print _debug(\@_) if $DEBUG;
		
	# Act on the parent class
	my ( $parent, $method ) = @_;
	Class::Autouse->$method( $parent );
	
	# Now get the list of child classes
	my $children = _child_classes( $parent );
	return 1 unless $children;
	
	# Act on each of the children
	foreach ( @$children ) {
		Class::Autouse->$method( $_ );
	}
}

# Find all the child classes for a parent class
sub _child_classes {
	print _debug(\@_) if $DEBUG;

	# Get the classes file name
	my $base_class = shift;
	my $base_file = _class_file( $base_class );
	
	# Find where it is in @INC
	my $inc_path = undef;
	foreach ( @INC ) {
		if ( -f "$_$SLASH$base_file" ) {
			$inc_path = $_;
			last;
		}
	}
	return undef unless defined $inc_path;
	
	# Does the file have a subdirectory
	# i.e. Are there child classes
	my $child_path = substr( $base_file, 0, length($base_file) - 3 );
	my $child_path_full = "$inc_path$SLASH$child_path";
	return 0 unless ( -d $child_path_full and -r $child_path_full );
	
	# Set up the initial scan state
	my @files = ();
	my @queue = ( $child_path );
	
	# Main scan loop
	my ( $file, @buffer );
	while ( $file = pop @queue ) {
		# Read in the raw file list
		next unless opendir( FILELIST, "$inc_path$SLASH$file" );
		@buffer = readdir FILELIST;
		closedir FILELIST;
		
		# Iterate over them
		foreach ( @buffer ) {
			# Filter out the dot files
			next if $_ eq '.' or $_ eq '..';
			$_ = "$file$SLASH$_";
			
			# Add to the queue if it's a directory we can descend
			if ( -d "$inc_path$SLASH$_" and -r "$inc_path$SLASH$_" ) {
				push @queue, $_;
				next;
			}
					
			# Filter
			next unless substr( $_, length($_) - 3 ) eq '.pm';
			next if substr( $_, 0, 1 ) eq '.';
			next unless -f "$inc_path$SLASH$_";
			
			# Add to the file hash
			push @files, $_;
		}
	}
	
	# Convert the file names to modules names
	foreach ( @files ) {
		$_ = substr( $_, 0, length($_) - 3 );
		$_ =~ s/$SLASH/::/g;
	}
		
	# Return the results
	return scalar @files ? \@files : 0;
}





#####################################################################
# Private support methods

# Take a class name and turn it into a file name
sub _class_file {
	print _debug(\@_) if $DEBUG;

	my $class = shift;
	$class =~ s/::/$SLASH/g;
	
	# Format check the result.
	return undef unless $class =~ m{^[\w/]+$}o;
	return $class . '.pm';
}
		
# Does a class with a particular file name
# exist somewhere in our include array
sub _file_exists {
	print _debug(\@_) if $DEBUG;
	
	# Scan @INC for the file
	my $file = shift or return undef;
	return undef if $file =~ m/(?:\012|\015)/o;
	foreach ( @INC ) {
		return "$_$SLASH$file" if -f "$_$SLASH$file";
	}
	return undef;
}

# Is a namespace occupied by anything significant
sub _namespace_occupied {
	print _debug(\@_) if $DEBUG;
	my $class = shift;
	
	# Get the list of glob names
	foreach ( keys %{$class.'::'} ) {
		# Only check for methods, since that's all that's reliable
		return 1 if defined *{"$class\::$_"}{CODE}; 
	}
	return 0;	
}

# Establish our call depth
sub _call_depth {
	my $spaces = shift;
	if ( $DEBUG and ! $spaces ) { print _debug(\@_); }
	
	# Search up the caller stack to find the first call that isn't us.
	my $level = 0;
	while( $level++ < 1000 ) {
		my @call = caller( $level );		
		my ($subclass) = $call[3] =~ m/^(.*)::/o;
		unless ( $subclass eq 'Class::Autouse' ) {
			# Subtract 1 for this sub's call
			$level -= 1;
			return $spaces ? join( '', (' ') x ($level - 2)) : $level;
		}
	}
	croak( "Infinite loop trying to find call depth" );
}
	
# Die gracefully
sub _cry { 
	print _debug() if $DEBUG;
	local $Carp::CarpLevel;
	$Carp::CarpLevel += _call_depth();
	croak( $_[0] );
}

# Adaptive debug print generation
sub _debug {
	my $args = shift;
	my $isaMethod = shift;
	my @c = caller(1);
	my $msg = _call_depth(1);
	$msg .= $c[3];
	if ( ref $args ) {
		my @mapped = map { "'$_'" } @$args;
		shift @mapped if $isaMethod;
		if ( scalar @mapped ) {
			$msg .= "( " . ( join ', ', @mapped ) . " )";
		} else {
			$msg .= "()";
		}
	}
	$msg .= "\n";
	return $msg;
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
  
  # Turn on debugging
  use Class::Autouse qw{:debug};
  
  # Turn on developer mode
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

=head2 The Internal Debugger

Given the C<:debug> pragma argument, Class::Autouse will dump 
detailed internal call information. This can be usefull when an
error has occurred that may be a little difficult to debug, and
some more inforamtion about when the problem has actually 
occurred is required. Debug messages are written to STDOUT, and
will look something like

 Class::Autouse::autouse_recursive( 'AppCore' )
  Class::Autouse::_recursive( 'AppCore', 'load' )
   Class::Autouse::load( 'AppCore' )
    Class::Autouse::_class_file( 'AppCore' )
   Class::Autouse::_child_classes( 'AppCore' )
    Class::Autouse::_class_file( 'AppCore' )
   Class::Autouse::load( 'AppCore::Export' )
    Class::Autouse::_class_file( 'AppCore::Export' )
    Class::Autouse::_file_exists( 'AppCore/Export.pm' )
    Class::Autouse::load -> Loading in AppCore/Export.pm
   Class::Autouse::load( 'AppCore::Cache' )
    Class::Autouse::_class_file( 'AppCore::Cache' )
    etc...
   
=head2 Developer Mode

Class::Autouse features a developer mode. In developer mode, classes
are loaded immediately, just like they would be with a normal 'use'
statement (although the import sub isn't called). This allows error
checking to be done while developing, at the expense of a larger
memory overhead. Developer mode is turned on either with the
C<devel> method, or using :devel in any of the pragma arguments.
For example, this would load CGI.pm immediately

    use Class::Autouse qw{:devel CGI};

While developer mode is roughly equivalent to just using a normal use
command, for a large number of modules it lets you use autoloading
notation, and just comment or uncomment a single line to turn developer
mode on or off. You can leave it on during development, and turn it
off for speed reasons when deploying.

=head2 Super Loader

Turning on the Class::Autouse super loader allows you to automatically
load ANY class without specifying it first. Thus, the following will work
and is completely legal.

    use Class::Autouse qw{:superloader};

    print CGI->header;

The super loader can be turned on with either the Class::Autouse->superloader
method, or the :superloader pragma argument.

=head2 Recursion

As an alternative to the super loader, the autouse_recursive and
load_recursive methods can be used to autouse or load an entire tree of
classes. For example, the following would give you access to all the URI
related classes installed on the machine.

    Class::Autouse->autouse_recursive( 'URI' );

Please note that the loadings will only occur down a single branch of the
include path, whichever the top class is located in.

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

Handy method when doing the sort of jobs that Class::Autouse does. Given
a class name, it will return 1 if the class can be loaded ( i.e. in @INC ),
0 if the class can't be loaded, and undef if the class name is invalid.

Note that this does not actually load the class, just tests to see if it can
be loaded. Loading can still fail.

=head2 autouse_recursive

The same as the C<autouse> method, but autouses recursively

=head2 load_recursive

The same as the C<load> method, but loads recursively. Great for checking that
a large class tree that might not always be loaded will load correctly.

=head1 AUTHORS

 Adam Kennedy, cpan@ali.as ( maintainer )          
 Rob Napier,   rnapier@employees.org 

=head1 SEE ALSO

autoload, autoclass

=cut
