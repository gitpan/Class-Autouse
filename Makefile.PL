require 5.000;
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'         => 'Class::Autouse',
	'VERSION_FROM' => 'lib/Class/Autouse.pm',
	'PREREQ_PM'    => {
		Test::Simple
	},	
	($] >= 5.005) ? (
		'AUTHOR'   => 'Adam Kennedy (adam@ali.as)',
		'ABSTRACT' => 'Defer loading of one or more classes.'
	) : (),
);
