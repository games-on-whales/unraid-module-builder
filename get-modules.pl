#!/usr/bin/env perl

use strict;
use warnings;

use v5.30;

use File::Find::Rule;
use File::Basename;
use File::Spec;

# the first arg is the kernel source dir
# the second arg is the kernel version string
# the rest of the args are the various CONFIG_* items we're interested in
my $src_dir = shift;
my $kernel_ver = shift;
my @config_items = @ARGV;

my $modules_path = "/lib/modules/$kernel_ver";

my $cfg_re = join('|', @config_items);
my @makefiles = File::Find::Rule->name('Makefile')->in($src_dir);

my %mods = ();

# go through each makefile looking for the modules created by the given
# CONFIG_* items
for my $makefile (@makefiles) {
    open my $in, '<', $makefile;
    while (my $line = <$in>) {
        # if the line definitely isn't for one of the items we care about, skip it
        # this might allow a few lines that still aren't relevant, but we'll
        # catch them later.
        next if $line !~ /(?:$cfg_re)/;

        # some items span more than one line; join consecutive lines together
        # in that case
        while ($line =~ /(.*)\\\s*$/) {
            $line = $1 . <$in>;
        }

        # now let's make sure this really is one we care about
        next if $line !~ /^obj-\$\((?:$cfg_re)\)\s+[:+]=\s*(.*)\s*$/;

        for my $mod (split /\s+/, $1) {
            next if $mod !~ /\.o$/;

            my $file = basename $mod, '.o';
            my @foundmods = File::Find::Rule->name($file.'.ko.xz')->in($modules_path);

            next if scalar @foundmods <= 0;
            if (scalar @foundmods > 1) {
                warn qq(There were more modules found for "$file" than expected; taking the first one);
            }

            my $modfile = File::Spec->abs2rel(shift @foundmods, $modules_path);
            $mods{$modfile} = 1;
        }
    }
    close $in;
}

say join("\n", keys %mods);
