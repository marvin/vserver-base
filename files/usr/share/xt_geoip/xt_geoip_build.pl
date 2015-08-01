#!/usr/bin/perl
# http://www.atwillys.de/content/linux/blocking-countries-using-geoip-and-iptables-on-ubuntu/
#   Converter for MaxMind CSV database to binary, for xt_geoip
#   Copyright Â© Jan Engelhardt <jengelh@medozas.de>, 2008-2011
#
#   Use -b argument to create big-endian tables.
#
use Getopt::Long;
use IO::Handle;
use Text::CSV_XS; # or trade for Text::CSV
use strict;
 
my $csv = Text::CSV_XS->new({
    allow_whitespace => 1,
    binary => 1,
    eol => $/,
}); # or Text::CSV
my $target_dir = ".";
 
&Getopt::Long::Configure(qw(bundling));
&GetOptions(
    "D=s" => \$target_dir,
);
 
if (!-d $target_dir) {
    print STDERR "Target directory $target_dir does not exist.\n";
    exit 1;
}
foreach (qw(LE BE)) {
    my $dir = "$target_dir/$_";
    if (!-e $dir && !mkdir($dir)) {
        print STDERR "Could not mkdir $dir: $!\n";
        exit 1;
    }
}
 
&dump(&collect());
 
sub collect
{
    my %country;
 
    while (my $row = $csv->getline(*ARGV)) {
        if (!defined($country{$row->[4]})) {
            $country{$row->[4]} = {
                name => $row->[5],
                pool_v4 => [],
                pool_v6 => [],
            };
        }
        my $c = $country{$row->[4]};
        if ($row->[0] =~ /:/) {
            push(@{$c->{pool_v6}},
                 [&ip6_pack($row->[0]), &ip6_pack($row->[1])]);
        } else {
            push(@{$c->{pool_v4}}, [$row->[2], $row->[3]]);
        }
        if ($. % 4096 == 0) {
            print STDERR "\r\e[2K$. entries";
        }
    }
 
    print STDERR "\r\e[2K$. entries total\n";
    return \%country;
}
 
sub dump
{
    my $country = shift @_;
 
    foreach my $iso_code (sort keys %$country) {
        &dump_one($iso_code, $country->{$iso_code});
    }
}
 
sub dump_one
{
    my($iso_code, $country) = @_;
    my($file, $fh_le, $fh_be);
 
    printf "%5u IPv6 ranges for %s %s\n",
        scalar(@{$country->{pool_v6}}),
        $iso_code, $country->{name};
 
    $file = "$target_dir/LE/".uc($iso_code).".iv6";
    if (!open($fh_le, "> $file")) {
        print STDERR "Error opening $file: $!\n";
        exit 1;
    }
    $file = "$target_dir/BE/".uc($iso_code).".iv6";
    if (!open($fh_be, "> $file")) {
        print STDERR "Error opening $file: $!\n";
        exit 1;
    }
    foreach my $range (@{$country->{pool_v6}}) {
        print $fh_be $range->[0], $range->[1];
        print $fh_le &ip6_swap($range->[0]), &ip6_swap($range->[1]);
    }
    close $fh_le;
    close $fh_be;
 
    printf "%5u IPv4 ranges for %s %s\n",
        scalar(@{$country->{pool_v4}}),
        $iso_code, $country->{name};
 
    $file = "$target_dir/LE/".uc($iso_code).".iv4";
    if (!open($fh_le, "> $file")) {
        print STDERR "Error opening $file: $!\n";
        exit 1;
    }
    $file = "$target_dir/BE/".uc($iso_code).".iv4";
    if (!open($fh_be, "> $file")) {
        print STDERR "Error opening $file: $!\n";
        exit 1;
    }
    foreach my $range (@{$country->{pool_v4}}) {
        print $fh_le pack("VV", $range->[0], $range->[1]);
        print $fh_be pack("NN", $range->[0], $range->[1]);
    }
    close $fh_le;
    close $fh_be;
}
 
sub ip6_pack
{
    my $addr = shift @_;
    $addr =~ s{::}{:!:};
    my @addr = split(/:/, $addr);
    my @e = (0) x 8;
    foreach (@addr) {
        if ($_ eq "!") {
            $_ = join(':', @e[0..(8-scalar(@addr))]);
        }
    }
    @addr = split(/:/, join(':', @addr));
    $_ = hex($_) foreach @addr;
    return pack("n*", @addr);
}
 
sub ip6_swap
{
    return pack("V*", unpack("N*", shift @_));
}

