#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use ok 'IO::Handle::Iterator';
use ok 'IO::Handle::Util' => qw(io_from_array);

my $fh = &io_from_array([qw(foo bar gorch baz quxx la la dong)]);

isa_ok( $fh, "IO::Handle::Iterator" );
isa_ok( $fh, "IO::Handle" );

ok( !$fh->eof, "not eof" );

is( $fh->getline, "foo", "getline" );

ok( !$fh->eof, "not eof" );

is( $fh->read(my $buf, 2), 2, "read" );
is( $buf, "ba", "read buffer" );

ok( !$fh->eof, "not eof" );

is( $fh->read($buf, 2), 2, "read" );
is( $buf, "rg", "read buffer" );

ok( !$fh->eof, "not eof" );

is( $fh->getline, "orch", "getline" );
is( $fh->getline, "baz", "getline" );

ok( !$fh->eof, "not eof" );

is( $fh->read($buf, 7), 7, "read" );
is( $buf, "quxxlal", "read buffer" );

ok( !$fh->eof, "not eof" );

is( $fh->read($buf, 7), 5, "read" );
is( $buf, "adong", "read buffer" );

ok( $fh->eof, "eof" );

done_testing;
