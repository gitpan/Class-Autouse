package Class::Autouse;

# See POD at end of file for documentation

require 5.005;
use strict;
no strict 'refs';

# Become an exporter so we don't get
# complaints when we act as a pragma.
use base 'Exporter';
use Carp       ();
use File::Spec ();
use List::Util ();

# Globals
use vars qw{$VERSION $DEBUG};
use vars qw{$devel $superloader};
use vars qw{%chased %loaded %special %bad};
use vars qw{*_original_can};
BEGIN {
	$VERSION = '1.0';
	$DEBUG   = 0;

	# Using Class::Autouse in a mod_perl situation can be dangerous, 
	# as it can class badly with autoreloaders such as Apache::Reload.
	# So ALWAYS run in devel mode under mod_perl. Since they should
	# probably be loading modules at startup time ( in the parent 
	# process ) anyway, this is a good thing.
	$devel       = $ENV{MOD_PERL} ? 1 : 0;
	$superloader = 0;

	# Have we tried to autoload a method before.
	# Contains the fully referenced sub name.
	%chased = ();

	# Is a class special, and we should try to do anything with it.
	%special = map { $_ => 1 } qw{main UNIVERSAL CORE ARRAY HASH SCALAR};

	# Define an errata list of classes where bad things happen when we
	# autouse them, so they should specifically always be loaded normally.
	%bad = map { $_ => 1 } qw{IO::File};

	# Has a class been loaded. For convenience, prestock with 
	# all the classes we ourselves use that are commonly inherited from.
	%loaded = map { $_ => 1 } qw{UNIVERSAL Exporter Carp File::Spec};
}





#####################################################################
# Configuration and Setting up

# Developer mode flag.
# Don't let them turn it off if we are under mod_perl.
sub devel {
	_debug(\@_, 1) if $DEBUG;

	$devel = ($_[1] and ! $ENV{MOD_PERL}) ? 1 : 0;
}

# Happy Fun Super Loader!
# The process here is to replace the &UNIVERSAL::AUTOLOAD sub
# ( which is just a dummy by default ) with a flexible class loader.
sub superloader {
	_debug(\@_ ,1) if $DEBUG;

	return 1 if $superloader;

	# Overwrite UNIVERSAL::AUTOLOAD and also catch any
	# DESTROY calls that make it to UNIVERSAL, so they
	# don't trigger an AUTOLOAD call.
	*UNIVERSAL::AUTOLOAD = \&_autoload;
	*UNIVERSAL::DESTROY = \&_destroy;
	$superloader = 1;
}

# The main autouse sub
sub autouse {
	# Remove any reference to ourselves, to allow us to
	# operate as a function, or a method
	shift if $_[0] eq 'Class::Autouse';
	return 1 unless @_;

	_debug(\@_) if $DEBUG;

	my @classes = grep { $_ } @_;
	foreach my $class ( @classes ) {
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

		# Load now if in devel mode, or if it's a bad class
		if ( $devel || $bad{$class} ) {
			Class::Autouse->load( $class );
			next;
		}

		# Get the file name
		my $file = File::Spec->catfile( split( /::/, $class) ) . '.pm';

		# Does the file for the class exist?
		next if exists $INC{$file};
		unless ( _file_exists($file) ) {
			_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
		}

		# Don't actually do anything if the superloader is on
		next if $superloader;

		# Add the AUTOLOAD hook and %INC lock to prevent 'use'ing
		*{"${class}::AUTOLOAD"} = \&_autoload;
		$INC{$file} = 'Class::Autouse';
	}

	1;
}

# Link import to autouse, so we can act as a pragma
BEGIN {
	*import = *autouse;
}





#####################################################################
# Explicit Actions

# Completely load a class ( The class and all it's dependencies ).
sub load {
	_debug(\@_, 1) if $DEBUG;

	my $class = $_[1] or _cry( "No class name specified to load" );
	return 1 if $loaded{$class};

	# Load the entire ISA tree
	my @stack  = ( $class );
	my %seen   = ( 'UNIVERSAL' => 1 );
	my @search = ();
	while ( my $c = shift @stack ) {
		next if $seen{$c}++;

		# Ensure class is loaded
		_load($c) unless $loaded{$c};

		# Add the class to the search list,
		# and add the @ISA to the load stack.
		push @search, $c unless $c eq 'UNIVERSAL';
        	unshift @stack, @{"${c}::ISA"};
        	$loaded{$c} = 1;
	}

	# If called an an array context, return the ISA tree.
	# In scalar context, just return true.
	wantarray ? @search : 1;
}

# Is a particular class installed in out @INC somewhere
# OR is it loaded in our program already
sub class_exists {
	_debug(\@_, 1) if $DEBUG;

	# Is the class loaded already, or can we find it's file
	_namespace_occupied($_[1]) or _file_exists($_[1]);
}

# A more general method to answer the question
# "Can I call a method on this class and expect it to work"
# Returns undef if the class does not exist
# Returns 0 if the class is not loaded ( or autouse'd )
# Returns 1 if the class can be used.
sub can_call_methods {
	_debug(\@_, 1) if $DEBUG;

	# Is it loaded already, or is the file in %INC
	_namespace_occupied( $_[1] ) or exists $INC{ File::Spec->catfile( split( /::/, $_[1]) ) . '.pm' };
}

# Recursive methods currently only work withing the scope of the single @INC
# entry containing the "top" module, and will probably stay this way

# Autouse not only a class, but all others below it.
sub autouse_recursive {
	_debug(\@_, 1) if $DEBUG;

	# Just load if in devel mode
	my $class = $_[1];
	return Class::Autouse->load_recursive( $class ) if $devel;

	# Don't need to do anything if the super loader is on
	return 1 if $superloader;

	# Find all the child classes, and hand them to the autouse method
	Class::Autouse->autouse( $class, _child_classes($class) );
}

# Load not only a class and all others below it
sub load_recursive {
	_debug(\@_, 1) if $DEBUG;

	# Load the parent class, and it's children
	my $class = $_[1];
	foreach ( $class, _child_classes($class) ) {
		Class::Autouse->load($_);
	}

	1;
}





#####################################################################
# Symbol Table Hooks

# These get hooked to various places on the symbol table,
# to enable the autoload functionality

# Get's linked via the symbol table to any AUTOLOADs are required
sub _autoload {
	_debug(\@_, 0, ", AUTOLOAD = '$Class::Autouse::AUTOLOAD'") if $DEBUG;

	# Loop detection ( Just in case )
	my $method = $Class::Autouse::AUTOLOAD or _cry( "Missing method name" );
	_cry( "Undefined subroutine &$method called" ) if ++$chased{ $method } > 10;

	# Don't bother with special classes
	my ($class, $function) = $method =~ m/^(.*)::(.*)$/o;
	_cry( "Undefined subroutine \&$method called" ) if $special{$class};

	# Load the class and it's dependancies
	my @search = Class::Autouse->load($class);

	# Find and go to the named method
	my $found = List::Util::first { defined *{"$_\::$function"}{CODE} } @search;
	goto &{"${found}::$function"} if $found;

	# Check for package AUTOLOADs
	foreach my $c ( @search ) {
        	if ( defined *{ "${c}::AUTOLOAD" }{CODE} ) {
        		# Set the AUTOLOAD variable in the package
        		# we are about to go to, so the AUTOLOAD
        		# sub there will work properly
        		${"${c}::AUTOLOAD"} = $method;

        		goto &{"${c}::AUTOLOAD"};
        	}
	}

	# Can't find the method anywhere. Throw the same error Perl does.
	_cry( "Can't locate object method \"$function\" via package \"$class\"" );
}

# This just handles a call and does nothing
sub _destroy { _debug(\@_) if $DEBUG }

# This is the replacement for UNIVERSAL::can
sub _can {
	my $class = ref $_[0] || $_[0] || return undef;

	# If it doesn't appear to be loaded, have a go at loading it
	unless ( $loaded{$class} or _namespace_occupied($class) ) {
		# Load the class and all it's dependencies.
		# UNIVERSAL::can never dies, so we shouldn't either.
		# Ignore, errors. If something goes wrong, 
		# let the real UNIVERSAL::can have a short at it anyway.
		eval { Class::Autouse->load($class) };
	}

	# Hand off to the real UNIVERSAL::can
	goto &_original_can;	
}





#####################################################################
# Support Functions

# Load a single class
sub _load {
	_debug(\@_, 1) if $DEBUG;

	# Don't attempt to load special classes
	my $class = shift or _cry( "Did not specify a class to load" );
	return 1 if $special{$class};

	# Run some checks
	my $file = File::Spec->catfile( split( /::/, $class) ) . '.pm';
	if ( defined $INC{$file} and $INC{$file} eq 'Class::Autouse' ) {
		# Because we autoused it earlier, we know the file for this
		# class MUST exist.
		# Removing the AUTOLOAD hook and %INC lock is all we have to do
		delete ${"${class}::"}{'AUTOLOAD'};
		delete $INC{ $file };
		
	} elsif ( defined $INC{$file} ) {
		# If the %INC lock is set to any other value, the file is 
		# already loaded. We do not need to do anything.
		return 1;
		
	} elsif ( ! _file_exists($file) ) {
		# File doesn't exist. We might still be OK, if the class was
		# defined in some other module that got loaded a different way.
		return 1 if _namespace_occupied( $class );
	
		# Definately doesn't exist.
		_cry( "Can't locate $file in \@INC (\@INC contains: @INC)" );
	}

	# Load the file
	if ( $DEBUG ) {
		print _call_depth(1) . "  Class::Autouse::load -> Loading in $file\n";
	}
	eval { require $file };
	_cry( $@ ) if $@;
}

# Find all the child classes for a parent class.
# Returns in the list context.
sub _child_classes {
	_debug(\@_) if $DEBUG;

	# Get the classes file name
	my $base_class = shift;
	my $base_file = File::Spec->catfile( split( /::/, $base_class) ) . '.pm';

	# Find where it is in @INC
	my $inc_path = List::Util::first { 
		-f File::Spec->catfile( $_, $base_file ) 
		} @INC or return;

	# Does the file have a subdirectory
	# i.e. Are there child classes
	my $child_path = substr( $base_file, 0, length($base_file) - 3 );
	my $child_path_full = File::Spec->catdir( $inc_path, $child_path );
	unless ( -d $child_path_full and -r $child_path_full ) {
		return 0;
	}

	# Main scan loop
	my ( $dir, @files );
	my @modules = ();
	my @queue = ( $child_path );
	while ( $dir = pop @queue ) {
		my $full_dir = File::Spec->catdir( $inc_path, $dir );

		# Read in the raw file list
		# Skip directories we can't open
		opendir( FILELIST, $full_dir ) or next;
		@files = readdir FILELIST;
		closedir FILELIST;

		# Iterate over them
		@files = map { File::Spec->catfile( $dir, $_ ) } # Full relative path
			grep { ! /^\./ } @files;                 # Ignore hidden files
		foreach my $file ( @files ) {
			my $full_file = File::Spec->catfile( $inc_path, $file );

			# Add to the queue if it's a directory we can descend
			if ( -d $full_file and -r $full_file ) {
				push @queue, $file;
				next;
			}

			# We only want .pm files we can read
			next unless substr( $file, length($file) - 3 ) eq '.pm';
			next unless -f $full_file;

			push @modules, $file;
		}
	}

	# Convert the file names into modules
	return map { join '::', File::Spec->splitdir( $_ ) }
		map { substr( $_, 0, length($_) - 3 ) } @modules;
}





#####################################################################
# Private support methods

# Does a class or file exists somewhere in our include path. For 
# convenience, returns the unresolved file name ( even if passed a class )
sub _file_exists {
	_debug(\@_) if $DEBUG;

	# What are we looking for?
	my $file = shift or return undef;
	return undef if $file =~ m/(?:\012|\015)/o;

	# If provided a class name, convert it
	if ( $file =~ /::/o ) {
		$file = File::Spec->catfile( split( /::/, $file) ) . '.pm';
	}

	# Scan @INC for the file
	foreach ( @INC ) {
		return $file if -f File::Spec->catfile( $_, $file );
	}

	undef;
}

# Is a namespace occupied by anything significant
sub _namespace_occupied {
	_debug(\@_) if $DEBUG;

	# Handle the most likely case
	my $class = shift or return undef;
	return 1 if defined @{"${class}::ISA"};

	# Get the list of glob names
	foreach ( keys %{"${class}::"} ) {
		# Only check for methods, since that's all that's reliable
		return 1 if defined *{"${class}::$_"}{CODE};
	}

	'';
}

# Establish our call depth
sub _call_depth {
	my $spaces = shift;
	if ( $DEBUG and ! $spaces ) { _debug(\@_); }

	# Search up the caller stack to find the first call that isn't us.
	my $level = 0;
	while( $level++ < 1000 ) {
		my @call = caller( $level );
		my ($subclass) = $call[3] =~ m/^(.*)::/o;
		unless ( defined $subclass and $subclass eq 'Class::Autouse' ) {
			# Subtract 1 for this sub's call
			$level -= 1;
			return $spaces ? join( '', (' ') x ($level - 2)) : $level;
		}
	}

	Carp::croak( "Infinite loop trying to find call depth" );
}

# Die gracefully
sub _cry {
	_debug() if $DEBUG;

	local $Carp::CarpLevel;
	$Carp::CarpLevel += _call_depth();
	Carp::croak( $_[0] );
}

# Adaptive debug print generation
sub _debug {
	my $args = shift;
	my $method = !! shift;
	my $message = shift || '';
	my @c = caller(1);
	my $msg = _call_depth(1) . $c[3];
	if ( ref $args ) {
		my @mapped = map { "'$_'" } @$args;
		shift @mapped if $method;
		$msg .= @mapped ? "( " . ( join ', ', @mapped ) . " )" : '()';
	}

	print $msg . $message . "\n";
}





#####################################################################
# Final Initialisation

# Replace the UNIVERSAL::can sub with our own version
BEGIN {
	# We don't need to do this if we are forced into devel mode
	# by the whole mod_perl situation
	unless ( $ENV{MOD_PERL} ) {
		# Copy the current UNIVERSAL::can
		*_original_can = *UNIVERSAL::can{CODE};
	
		# Replace UNIVERSAL::can, using different methods of disabling warnings
		# depending if we have access to the warnings module or not.
		if ( class_exists('warnings') ) {
			no warnings;
			*UNIVERSAL::can = *Class::Autouse::_can{CODE};
		} else {
			local $^W = 0;
			*UNIVERSAL::can = *Class::Autouse::_can{CODE};
		}
	}
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
   Class::Autouse::_child_classes( 'AppCore' )
   Class::Autouse::load( 'AppCore::Export' )
    Class::Autouse::_file_exists( 'AppCore/Export.pm' )
    Class::Autouse::load -> Loading in AppCore/Export.pm
   Class::Autouse::load( 'AppCore::Cache' )
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

=head2 mod_perl

The methods that Class::Autouse uses are not compatible with mod_perl. In
particular with reloader modules like Apache::Reload. Class::Autouse detects
the presence of mod_perl and acts as normal, but will always load all
classes immediately, equivalent to having developer mode enabled.

This is actually beneficial, as under mod_perl classes should be preloaded
in the parent mod_perl process anyway, to prevent them having to be loaded
by the Apache child classes. It also saves HUGE amounts of memory.

=head1 METHODS

=head2 autouse( $class )

The autouse method sets the class to be loaded as required.

=head2 load( $class )

The load method loads one or more classes into memory. This is functionally
equivalent to using require to load the class list in, except that load
will detect and remove the autoloading hook from a previously autoused
class, whereas as use effectively ignore the class, and not load it.

=head2 devel()

The devel method sets development mode on (argument of 1) or off (argument of 0)

=head2 superloader()

The superloader method turns on the super loader. Please note that once you
have turned the superloader on, it cannot be turned off. This is due to
code that might be relying on it being there not being able to autoload it's
classes when another piece of code decides they don't want it any more, and
turns the superloader off.

=head2 class_exists( $class )

Handy method when doing the sort of jobs that Class::Autouse does. Given
a class name, it will return true if the class can be loaded ( i.e. in @INC ),
false if the class can't be loaded, and undef if the class name is invalid.

Note that this does not actually load the class, just tests to see if it can
be loaded. Loading can still fail.

=head2 autouse_recursive( $class )

The same as the C<autouse> method, but autouses recursively

=head2 load_recursive( $class )

The same as the C<load> method, but loads recursively. Great for checking that
a large class tree that might not always be loaded will load correctly.

=head1 SUPPORT

Contact the author

=head1 AUTHORS

        Adam Kennedy ( maintainer )
        cpan@ali.as
        http://ali.as/

        Rob Napier
        rnapier@employees.org

=head1 SEE ALSO

autoload, autoclass

=head1 COPYRIGHT

Copyright (c) 2002 Adam Kennedy. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
