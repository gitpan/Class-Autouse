use inc::Module::Install;

name          ( 'Class-Autouse'             );
abstract      ( 'Run-time class loading on first method call' );
author        ( 'Adam Kennedy<cpan@ali.as>' );
version_from  ( 'lib/Class/Autouse.pm'      );
license       ( 'perl'                      );

requires      ( 'perl'         => '5.005'   );
requires      ( 'Carp'         => '0'       );
requires      ( 'File::Spec'   => '0.82'    );
requires      ( 'List::Util'   => '1.11'    );

build_requires( 'Test::More'   => '0.47'    );

# Out test directories contain valid looking modules.
# Make sure they don't get indexed.
no_index      ( directory      => 'modules' );

auto_install();

&WriteAll;
