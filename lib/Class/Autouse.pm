package Class::Autouse;

# See POD at end of file for documentation

### Memory Overhead: 180K

use 5.005;
use strict;
no strict 'refs'; # We do a LOT of bad ref stuff
use UNIVERSAL ();

# Become an exporter so we don't get complaints when we act as a pragma.
# I don't fully understand the reason for this, but it works.
use base 'Exporter';

# Load required modules
use Carp       ();
use File::Spec ();
use List::Util ();

# Globals
use vars qw{$VERSION $DEBUG $DEVEL $SUPERLOAD};    # Load environment
use vars qw{$HOOKS %chased %loaded %special %bad}; # Working data
use vars qw{*_UNIVERSAL_can};                      # Subroutine storage
BEGIN {
	$VERSION = '1.15';
	$DEBUG   = 0;

	# We play with UNIVERSAL::can at times, so save a backup copy
	*_UNIVERSAL_can = *UNIVERSAL::can{CODE};

	# Start with devel mode off.
	$DEVEL = 0;

	# We always start with the superloader off
	$SUPERLOAD = 0;

	# AUTOLOAD hook counter
	$HOOKS = 0;

	# Anti-loop protection. "Have we tried to autoload a method before?"
	# Contains fully referenced sub names.
	%chased = ();

	# ERRATA
	# Special classes are internal and should be left alone.
	# Loaded modules are those already loaded by us.
	# Bad classes are those that are incompatible with us.
	%special = map { $_ => 1 } qw{CORE main ARRAY HASH SCALAR REF UNIVERSAL};
	%loaded  = map { $_ => 1 } qw{UNIVERSAL Exporter Carp File::Spec};
	%bad     = map { $_ => 1 } qw{IO::File};
}

# Define prototypes
sub _cry($);





#####################################################################
# Configuration and Setting up

# Developer mode flag.
# Cannot be turned off once turned on.
sub devel {
	_debug(\@_, 1) if $DEBUG;

	# Enable if not already
	return 1 if $DEVEL;
	$DEVEL = 1;

	# Load any unloaded modules.
	# Most of the time there should be nothing here.
	foreach my $class ( grep { $INC{$_} eq 'Class::Autouse' } keys %INC ) {
		$class =~ s/\//::/;
		$class =~ s/\.pm$//i;
		Class::Autouse->load($class);
	}
}

# Happy Fun Super Loader!
# The process here is to replace the &UNIVERSAL::AUTOLOAD sub
# ( which is just a dummy by default ) with a flexible class loader.
sub superloader {
	_debug(\@_, 1) if $DEBUG;

	unless ( $SUPERLOAD ) {
		# Overwrite UNIVERSAL::AUTOLOAD and catch any
		# UNIVERSAL::DESTROY calls so they don't trigger
		# UNIVERSAL::AUTOLOAD. Anyone handling DESTROY calls
		# via an AUTOLOAD should be summarily shot.
		*UNIVERSAL::AUTOLOAD = \&_AUTOLOAD;
		*UNIVERSAL::DESTROY  = \&_DESTROY;

		# Because this will never go away, we increment $HOOKS such
		# that it will never be decremented, and this the
		# UNIVERSAL::can hijack will never be removed.
		_UPDATE_CAN() unless $HOOKS++;
	}

	$SUPERLOAD = 1;
}

# The main autouse sub
sub autouse {
	# Operate as a function or a method
	shift if $_[0] eq 'Class::Autouse';

	# Ignore calls with no arguments
	return 1 unless @_;

	_debug(\@_) if $DEBUG;

	foreach my $class ( grep { $_ } @_ ) {
		# Control flag handling
		if ( substr($class, 0, 1) eq ':' ) {
			if ( $class eq ':superloader' ) {
				# Turn on the superloader
				Class::Autouse->superloader;
			} elsif ( $class eq ':devel' ) {
				# Turn on devel mode
				Class::Autouse->devel(1);
			} elsif ( $class eq ':debug' ) {
				# Turn on debugging
				$DEBUG = 1;
				print _call_depth(1) . "Class::Autouse::autoload -> Debugging Activated.\n";
			}
			next;
		}

		# Load now if in devel mode, or if its a bad class
		if ( $DEVEL || $bad{$class} ) {
			Class::Autouse->load( $class );
			next;
		}

		# Does the file for the class exist?
		my $file = _class_file($class);
		next if exists $INC{$file};
		unless ( _file_exists($file) ) {
			my $inc = join ', ', @INC;
			_cry "Can't locate $file in \@INC (\@INC contains: $inc)";
		}

		# Don't actually do anything if the superloader is on.
		# It will catch all AUTOLOAD calls.
		next if $SUPERLOAD;

		# Add the AUTOLOAD hook and %INC lock to prevent 'use'ing
		*{"${class}::AUTOLOAD"} = \&_AUTOLOAD;
		$INC{$file} = 'Class::Autouse';

		# When we add the first hook, hijack UNIVERSAL::can
		_UPDATE_CAN() unless $HOOKS++;
	}

	1;
}

# Import behaves the same as autouse
sub import { shift->autouse(@_) }





#####################################################################
# Explicit Actions

# Completely load a class ( The class and all its dependencies ).
sub load {
	_debug(\@_, 1) if $DEBUG;

	my $class = $_[1] or _cry 'No class name specified to load';
	return 1 if $loaded{$class};

	# Load the entire ISA tree
	my @stack  = ( $class );
	my %seen   = ( UNIVERSAL => 1 );
	my @search = ();
	while ( my $c = shift @stack ) {
		next if $seen{$c}++;

		# Ensure class is loaded
		_load($c) unless $loaded{$c};

		# Add the class to the search list,
		# and add the @ISA to the load stack.
		push @search, $c;
        	unshift @stack, @{"${c}::ISA"};
	}

	# If called an an array context, return the ISA tree.
	# In scalar context, just return true.
	wantarray ? @search : 1;
}

# Is a particular class installed in out @INC somewhere
# OR is it loaded in our program already
sub class_exists {
	_debug(\@_, 1) if $DEBUG;
	_namespace_occupied($_[1]) or _file_exists($_[1]);
}

# A more general method to answer the question
# "Can I call a method on this class and expect it to work"
# Returns undef if the class does not exist
# Returns 0 if the class is not loaded ( or autouse'd )
# Returns 1 if the class can be used.
sub can_call_methods {
	_debug(\@_, 1) if $DEBUG;
	_namespace_occupied($_[1]) or exists $INC{_class_file($_[1])};
}

# Recursive methods currently only work withing the scope of the single @INC
# entry containing the "top" module, and will probably stay this way

# Autouse not only a class, but all others below it.
sub autouse_recursive {
	_debug(\@_, 1) if $DEBUG;

	# Just load if in devel mode
	return Class::Autouse->load_recursive($_[1]) if $DEVEL;

	# Don't need to do anything if the super loader is on
	return 1 if $SUPERLOAD;

	# Find all the child classes, and hand them to the autouse method
	Class::Autouse->autouse( $_[1], _child_classes($_[1]) );
}

# Load not only a class and all others below it
sub load_recursive {
	_debug(\@_, 1) if $DEBUG;

	# Load the parent class, and its children
	foreach ( $_[1], _child_classes($_[1]) ) {
		Class::Autouse->load($_);
	}

	1;
}





#####################################################################
# Symbol Table Hooks

# These get hooked to various places on the symbol table,
# to enable the autoload functionality

# Get's linked via the symbol table to any AUTOLOADs are required
sub _AUTOLOAD {
	_debug(\@_, 0, ", AUTOLOAD = '$Class::Autouse::AUTOLOAD'") if $DEBUG;

	# Loop detection ( Just in case )
	my $method = $Class::Autouse::AUTOLOAD or _cry 'Missing method name';
	_cry "Undefined subroutine &$method called" if ++$chased{ $method } > 10;

	# Don't bother with special classes
	my ($class, $function) = $method =~ m/^(.*)::(.*)$/s;
	_cry "Undefined subroutine &$method called" if $special{$class};

	# Load the class and it's dependancies, and get the search path
	my @search = Class::Autouse->load($class);

	# Find and go to the named method
	my $found = List::Util::first { defined *{"${_}::$function"}{CODE} } @search;
	goto &{"${found}::$function"} if $found;

	# Check for package AUTOLOADs
	foreach my $c ( @search ) {
        	if ( defined *{"${c}::AUTOLOAD"}{CODE} ) {
			# Simulate a normal autoload call
        		${"${c}::AUTOLOAD"} = $method;
        		goto &{"${c}::AUTOLOAD"};
        	}
	}

	# Can't find the method anywhere. Throw the same error Perl does.
	_cry "Can't locate object method \"$function\" via package \"$class\"";
}

# This just handles the call and does nothing
sub _DESTROY { _debug(\@_) if $DEBUG }

# This is the replacement for UNIVERSAL::can
sub _can {
	my $class = ref $_[0] || $_[0] || return undef;

	# Shortcut for the most likely cases
	goto &_UNIVERSAL_can if $loaded{$class} or defined @{"${class}::ISA"};

	# Does it look like a package?
	$class =~ /^[^\W\d]\w*(?:(?:'|::)[^\W\d]\w*)*$/o or return undef;

	# Do we try to load the class
	my $load = 0;
	my $file = _class_file($class);
	if ( defined $INC{$file} and $INC{$file} eq 'Class::Autouse' ) {
		# It's an autoused class
		$load = 1;
	} elsif ( ! $SUPERLOAD ) {
		# Superloader isn't on, don't load
		$load = 0;
	} elsif ( _namespace_occupied($class) ) {
		# Superloader is on, but there is something already in the class
		# This can't be the autouse loader, because we would have caught
		# that case already
		$load = 0;
	} else {
		# The rules of the superloader say we assume loaded unless we can
		# tell otherwise. Thus, we have to have a go at loading.
		$load = 1;
	}

	# If needed, load the class and all its dependencies.
	# UNIVERSAL::can never dies, so we shouldn't either.
	# Ignore, errors. If something goes wrong,
	# let the real UNIVERSAL::can have a short at it anyway.
	eval { Class::Autouse->load($class) } if $load;

	# Hand off to the real UNIVERSAL::can
	goto &_UNIVERSAL_can;
}





#####################################################################
# Support Functions

# Load a single class
sub _load ($) {
	_debug(\@_) if $DEBUG;

	# Don't attempt to load special classes
	my $class = shift or _cry 'Did not specify a class to load';
	return 1 if $special{$class};

	# Run some checks
	my $file = _class_file($class);
	if ( defined $INC{$file} ) {
		# If the %INC lock is set to any other value, the file is
		# already loaded. We do not need to do anything.
		return $loaded{$class} = 1 if $INC{$file} ne 'Class::Autouse';

		# Because we autoused it earlier, we know the file for this
		# class MUST exist.
		# Removing the AUTOLOAD hook and %INC lock is all we have to do
		delete ${"${class}::"}{'AUTOLOAD'};
		delete $INC{$file};

	} elsif ( ! _file_exists($file) ) {
		# File doesn't exist. We might still be OK, if the class was
		# defined in some other module that got loaded a different way.
		return $loaded{$class} = 1 if _namespace_occupied($class);
		my $inc = join ', ', @INC;
		_cry "Can't locate $file in \@INC (\@INC contains: $inc)";
	}

	# Load the file
	print _call_depth(1) . "  Class::Autouse::load -> Loading in $file\n" if $DEBUG;
	eval { CORE::require $file }; _cry $@ if $@;

	# Give back UNIVERSAL::can if there are no other hooks
	--$HOOKS or _UPDATE_CAN();

	$loaded{$class} = 1;
}

# Find all the child classes for a parent class.
# Returns in the list context.
sub _child_classes ($) {
	_debug(\@_) if $DEBUG;

	# Find where it is in @INC
	my $base_file = _class_file(shift);
	my $inc_path  = List::Util::first {
		-f File::Spec->catfile($_, $base_file)
		} @INC or return;

	# Does the file have a subdirectory
	# i.e. Are there child classes
	my $child_path      = substr( $base_file, 0, length($base_file) - 3 );
	my $child_path_full = File::Spec->catdir( $inc_path, $child_path );
	return 0 unless -d $child_path_full and -r _;

	# Main scan loop
	local *FILELIST;
	my ($dir, @files, @modules) = ();
	my @queue = ( $child_path );
	while ( $dir = pop @queue ) {
		my $full_dir = File::Spec->catdir($inc_path, $dir);

		# Read in the raw file list
		# Skip directories we can't open
		opendir( FILELIST, $full_dir ) or next;
		@files = readdir FILELIST;
		closedir FILELIST;

		# Iterate over them
		@files = map { File::Spec->catfile($dir, $_) } # Full relative path
			grep { ! /^\./ } @files;                 # Ignore hidden files
		foreach my $file ( @files ) {
			my $full_file = File::Spec->catfile($inc_path, $file);

			# Add to the queue if its a directory we can descend
			if ( -d $full_file and -r _ ) {
				push @queue, $file;
				next;
			}

			# We only want .pm files we can read
			next unless substr( $file, length($file) - 3 ) eq '.pm';
			next unless -f _;

			push @modules, $file;
		}
	}

	# Convert the file names into modules
	map { join '::', File::Spec->splitdir($_) }
		map { substr($_, 0, length($_) - 3) } @modules;
}





#####################################################################
# Private support methods

# Does a class or file exists somewhere in our include path. For
# convenience, returns the unresolved file name ( even if passed a class )
sub _file_exists ($) {
	_debug(\@_) if $DEBUG;

	# What are we looking for?
	my $file = shift or return undef;
	return undef if $file =~ m/(?:\012|\015)/o;

	# If provided a class name, convert it
	$file = _class_file($file) if $file =~ /::/o;

	# Scan @INC for the file
	foreach ( @INC ) {
		return $file if -f File::Spec->catfile($_, $file);
	}

	undef;
}

# Is a namespace occupied by anything significant
sub _namespace_occupied ($) {
	_debug(\@_) if $DEBUG;

	# Handle the most likely case
	my $class = shift or return undef;
	return 1 if defined @{"${class}::ISA"};

	# Get the list of glob names, ignoring namespaces
	foreach ( keys %{"${class}::"} ) {
		next if /::$/;

		# Only check for methods, since that's all that's reliable
		return 1 if defined *{"${class}::$_"}{CODE};
	}

	'';
}

# For a given class, get the file name
sub _class_file ($) { join( '/', split /(?:\'|::)/, shift ) . '.pm' }

# Establish our call depth
sub _call_depth {
	my $spaces = shift;
	if ( $DEBUG and ! $spaces ) { _debug(\@_); }

	# Search up the caller stack to find the first call that isn't us.
	my $level = 0;
	while( $level++ < 1000 ) {
		my @call = caller($level);
		my ($subclass) = $call[3] =~ m/^(.*)::/so;
		unless ( defined $subclass and $subclass eq 'Class::Autouse' ) {
			# Subtract 1 for this sub's call
			$level -= 1;
			return $spaces ? join( '', (' ') x ($level - 2)) : $level;
		}
	}

	Carp::croak( "Infinite loop trying to find call depth" );
}

# Die gracefully
sub _cry ($) {
	_debug() if $DEBUG;

	local $Carp::CarpLevel;
	$Carp::CarpLevel += _call_depth();
	Carp::croak( $_[0] );
}

# Adaptive debug print generation
sub _debug {
	my $args    = shift;
	my $method  = !! shift;
	my $message = shift || '';
	my @c       = caller(1);
	my $msg     = _call_depth(1) . $c[3];
	if ( ref $args ) {
		my @mapped = map { "'$_'" } @$args;
		shift @mapped if $method;
		$msg .= @mapped ? '( ' . ( join ', ', @mapped ) . ' )' : '()';
	}

	print "$msg$message\n";
}





#####################################################################
# Final Initialisation

# The _UPDATE_CAN function is intended to turn our hijacking of UNIVERSAL::can
# on or off, depending on whether we have any live hooks. The idea being, if we
# don't have any live hooks, why bother intercepting UNIVERSAL::can calls?
BEGIN { eval( $] >= 5.006 ? <<'END_NEW_PERL' : <<'END_OLD_PERL'); die $@ if $@ }
sub _UPDATE_CAN () {
	no warnings;
	*UNIVERSAL::can = $HOOKS ? *_can{CODE} : *_UNIVERSAL_can{CODE};
}
END_NEW_PERL
sub _UPDATE_CAN () {
	local $^W = 0;
	*UNIVERSAL::can = $HOOKS ? *_can{CODE} : *_UNIVERSAL_can{CODE};
}
END_OLD_PERL

BEGIN {
	# Optional integration with prefork.pm (if installed)
	eval { require prefork };
	if ( $@ ) {
		# prefork is not installed.
		# Do manual detection of mod_perl
		$DEVEL = 1 if $ENV{MOD_PERL};
	} else {
		# Go into devel mode when prefork is enabled
		$loaded{prefork} = 1;
		eval "prefork::notify( sub { Class::Autouse->devel(1) } )";
		die $@ if $@;
	}
}

1;

__END__

=pod

=head1 NAME

Class::Autouse - Run-time class loading on first method call

=head1 SYNOPSIS

  # Load a class on method call
  use Class::Autouse;
  Class::Autouse->autouse( 'CGI' );
  print CGI->b('Wow!');

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

 Class::Autouse::autouse_recursive( 'Foo' )
  Class::Autouse::_recursive( 'Foo', 'load' )
   Class::Autouse::load( 'Foo' )
   Class::Autouse::_child_classes( 'Foo' )
   Class::Autouse::load( 'Foo::Bar' )
    Class::Autouse::_file_exists( 'Foo/Bar.pm' )
    Class::Autouse::load -> Loading in Foo/Bar.pm
   Class::Autouse::load( 'Foo::More' )
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

    print CGI->b('Wow!');

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

=head2 autouse $class

The autouse method sets the class to be loaded as required.

=head2 load $class

The load method loads one or more classes into memory. This is functionally
equivalent to using require to load the class list in, except that load
will detect and remove the autoloading hook from a previously autoused
class, whereas as use effectively ignore the class, and not load it.

=head2 devel

The devel method sets development mode on (argument of 1) or off (argument of 0)

=head2 superloader

The superloader method turns on the super loader. Please note that once you
have turned the superloader on, it cannot be turned off. This is due to
code that might be relying on it being there not being able to autoload its
classes when another piece of code decides they don't want it any more, and
turns the superloader off.

=head2 class_exists $class

Handy method when doing the sort of jobs that Class::Autouse does. Given
a class name, it will return true if the class can be loaded ( i.e. in @INC ),
false if the class can't be loaded, and undef if the class name is invalid.

Note that this does not actually load the class, just tests to see if it can
be loaded. Loading can still fail.

=head2 autouse_recursive $class

The same as the C<autouse> method, but autouses recursively

=head2 load_recursive $class

The same as the C<load> method, but loads recursively. Great for checking that
a large class tree that might not always be loaded will load correctly.

=head1 SUPPORT

Bugs should be always be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-Autouse>

For other issues, or commercial enhancement or support, contact the author.

=head1 AUTHORS

Adam Kennedy (Maintainer), L<http://ali.as/>, cpan@ali.as

Rob Napier (No longer involved), rnapier@employees.org

=head1 SEE ALSO

L<autoload>, L<autoclass>

=head1 COPYRIGHT

Copyright (c) 2002 - 2005 Adam Kennedy. All rights reserved.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
