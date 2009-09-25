#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use ok 'IO::Handle::Prototype::Fallback';

sub check_write_fh {
    my ( $fh, $buf ) = @_;

    isa_ok( $fh, "IO::Handle::Prototype::Fallback" );
    isa_ok( $fh, "IO::Handle::Prototype" );
    isa_ok( $fh, "IO::Handle" );

    can_ok( $fh, qw(getline read print write) );

    eval { $fh->getline };
    like( $@, qr/getline/, "dies on missing callback" );

    eval { $fh->getc };
    like( $@, qr/getc/, "dies on missing callback" );

    eval { $fh->read };
    like( $@, qr/read/, "dies on missing callback" );

    eval { $fh->print("foo") };
    is( $@, '', "no error" );
    is( $$buf, "foo", "print worked" );

    local $\ = "\n";
    local $, = " ";

    eval { $fh->print("foo", "bar") };
    is( $@, '', "no error" );
    is( $$buf, "foofoo bar\n", "print worked" );

    eval { $fh->write("foo") };
    is( $@, '', "no error" );
    is( $$buf, "foofoo bar\nfoo", "write worked" );

    eval { $fh->syswrite("foo", 1, 1) };
    is( $@, '', "no error" );
    is( $$buf, "foofoo bar\nfooo", "write worked" );

    eval { $fh->printf("%d hens", 5) };
    is( $@, '', "no error" );
    is( $$buf, "foofoo bar\nfooo5 hens\n", "printf worked" );

    $\ = "%%";

    eval { $fh->print("foo") };
    is( $@, '', "no error" );
    is( $$buf, "foofoo bar\nfooo5 hens\nfoo%%", "print worked" );

    eval { $fh->say("Hello, World!") };
    is( $@, '', "no error" );
    is( $$buf, "foofoo bar\nfooo5 hens\nfoo%%Hello, World!\n", "say worked" );
}

{
    my $buf = '';

    my $fh = IO::Handle::Prototype::Fallback->new(
        print => sub {
            my ( $self, @stuff ) = @_;
            no warnings 'uninitialized';
            $buf .= join($,, @stuff) . $\;
        },
    );

    check_write_fh($fh, \$buf);
}

foreach my $write (qw(write syswrite)) {
    my $buf = '';

    my $fh = IO::Handle::Prototype::Fallback->new(
        $write => sub {
            my ( $self, $str, $length, $offset ) = @_;
            $buf .= substr($str, $offset || 0, $length || length($str));
        },
    );

    check_write_fh($fh, \$buf);
}

{
    my $buf = '';

    my $fh = IO::Handle::Prototype::Fallback->new(
        __write => sub { $buf .= $_[1] },
    );
}

done_testing;

# ex: set sw=4 et:
