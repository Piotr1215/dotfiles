#!/usr/bin/perl

use strict;
use warnings;

# Temporary output file path
my $output_file = "/tmp/help_manual.md";

# Open the output file
open my $out_fh, '>', $output_file or die "Could not open $output_file: $!";

# Add title
print $out_fh "# Dotfiles Scripts Manual\n\n";

# List all .sh files and process them
my @files = grep { /\.sh$/ } split "\n", `/usr/bin/ls`;

foreach my $file (@files) {
    # Create header from file name
    my $header = $file;
    $header =~ s/__/ /g;
    $header =~ s/\.sh//;
    print $out_fh "## $header\n\n";

    # Check for help functions
    if (open my $in_fh, '<', $file) {
        my $inside_help_function = 0;
        while (<$in_fh>) {
            if (/help_function\(\) \{/) {
                $inside_help_function = 1;
                next;
            }
            if ($inside_help_function && /^\}/) {
                $inside_help_function = 0;
                last;
            }
            if ($inside_help_function) {
                s/^[\s]*echo\s*"(.*)"/$1/;
                s/\\n/  \n/g; # Convert newline characters
                print $out_fh "$_\n";
                if (/\"$/) {
                    print $out_fh "```\n";
                }
            }
        }
        close $in_fh;
        if (!$inside_help_function) {
            print $out_fh "Please add help\n\n";
        }
    } else {
        print $out_fh "Please add help\n\n";
    }
}

close $out_fh;

# Convert to troff format using pandoc
system("pandoc -s $output_file -o /home/decoder/.local/share/man/man1/scripts.1");

# Remove temporary Markdown file
unlink $output_file;

print "Man file generated at /home/decoder/.local/share/man/man1/scripts.1 🎉\n";
