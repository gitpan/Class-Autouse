package Class::Autouse;

use vars qw{$VERSION @ISA};

# Declare standard stuff
$VERSION = '0.1';
@ISA = qw{Exporter};

# Set the code
my $code = q~
return 1 if defined %Class::;
package Class;
sub AUTOLOAD {
	my $c = shift || 'Class';
	my ($m) = $AUTOLOAD =\~ /.*::(\w+)$/;
	undef *Class::AUTOLOAD;  # Remove our existance
	require Class;           # Load the class 
	return $c->$m(@_);       # Try the method again
}
return 1;
~;

# The main autouse subroutien
sub autouse(@) {
	# Check the arguments
	shift if $_[0] eq 'Class::Autouse';
	die "No class specified to autouse" unless $_[0];
	
	# Get the Class name
	my $name = shift;
	
	# Build the code fragment
	my $string = $code;
	$string =~ s/Class/$name/g;
	
	# Eval and return
	my $rv = eval $string;
	die $@ unless $rv == 1;
	return 1;
}

1;
__END__

=head1 NAME

Class::Autouse - Defer loading ( 'use'ing ) of a class until run time 

=head1 SYNOPSIS

  use Class::Autouse;
  
  Class::Autouse->autouse( 'CGI' );
  
  print CGI->header();

=head1 DESCRIPTION

Class::Autouse allows you to specify a class the will only load when a 
method of the class is called. For large classes that might not be used
during the running of a program, such as Date::Manip, this can save
you large amounts of memory, and decrease the script load time.

=head1 AUTHOR

Adam Kennedy, cpan@ali.as

=head1 SEE ALSO

autoload

=cut

