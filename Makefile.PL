require 5.000;
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'         => 'Class::Autouse',
	'VERSION_FROM' => 'lib/Class/Autouse.pm',
	'PREREQ_PM'    => {
		'Carp'       => 0,
		'List::Util' => 1.11,
		'Test::More' => 0,
		'File::Spec' => 0.82,
	},
	($] >= 5.005) ? (
		'AUTHOR'   => 'Adam Kennedy (cpan@ali.as)',
		'ABSTRACT' => 'Defer loading of one or more classes',
		'NO_META'  => 1,
	) : (),
);
