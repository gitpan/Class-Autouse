use inc::Module::Install;

name          ( 'Class-Autouse'             );
abstract      ( 'Run-time loading of classes on first method call' );
author        ( 'Adam Kennedy<cpan@ali.as>' );
version_from  ( 'lib/Class/Autouse.pm'      );
license       ( 'perl'                      );

requires      ( 'perl'           => '5.005' );
requires      ( 'Carp'           => '0'     );
requires      ( 'File::Spec'     => '0.82'  );
requires      ( 'List::Util'     => '1.11'  );
requires      ( 'prefork'        => '0.03'  );

build_requires( 'Test::More'     => '0.47'  );

auto_install();

&WriteAll;
