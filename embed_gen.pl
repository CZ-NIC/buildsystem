#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $output_path;
my $input_path;
my $dep_path;

GetOptions
	'output=s'	=> \$output_path,
	'input=s'	=> \$input_path,
	'deps=s'	=> \$dep_path
or die "Bad arguments\n";

$output_path = abs_path $output_path;

open my $input, '<', $input_path or die "Couldn't read input $input_path: $!\n";
open my $output, '>', $output_path or die "Couldn't write output $output_path: $!\n";
$SIG{__DIE__} = sub {
	unlink $output_path;
};
open my $deps, '>', $dep_path or die "Couldn't write deps $dep_path: $!\n";

print $output <<'ENDHEAD';
// This file is auto-generated. Do not edit.
#include <stdint.h>
ENDHEAD

sub dep($) {
	my ($dep) = @_;
	$dep = abs_path $dep;
	print $deps "$output_path: $dep\n";
}

dep $input_path;

# The paths in the input might be relative. Resolve them relative to that file.
chdir dirname $input_path;

my %idx;

while (<$input>) {
	chomp;
	if (my ($idx, $type) = /^idx\s+(\w+)\s+(\w+)/) {
		# Please generate an index into variable and type given
		print $output "struct $type $idx\[\] = {\n";
		print $output "	{ \"$_\", $_, $idx{$_} },\n" for sort keys %idx;
		print $output "	{ NULL, 0 }\n";
		print $output "};\n";
		# And reset the index, so we can generate more than one.
		%idx = ();
	} elsif (my ($passthrough) = /^\|(.*)/) {
		# Include a line
		print $output "$passthrough\n";
	} elsif (my ($name, $path) = /^(\w+)\s+(\S+)\s*$/) {
		# Embed a file as an array
		dep $path;
		open my $f, '<', $path or die "Couldn't read file '$path': $!\n";
		print $output "static uint8_t $name\[\] = {\n";
		my $chunk;
		my $len;
		my $total = 0;
		while ($len = read $f, $chunk, 16) {
			# Read chunks of max 16 bytes, like hexdump does
			# Convert each to hex
			printf $output '0x%02X, ', ord($_) for split '', $chunk;
			print $output "\n";
			$total += $len;
		}
		# Terminates with 0 on EOF and undef on error.
		die "Error reading from file '$path': $!" unless defined $chunk;
		print $output "0};\n";
		$idx{$name} = $total;
	} else {
		# Allow comments and empty lines, but nothing else
		die "I don't understand line $_" unless /^\s*(|#.*)$/;
	}
}

close $output;
