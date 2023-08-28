#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;  # Add this line

my $mode = shift @ARGV || '';

# Get yesterday's date in the required format
my $t = localtime;
my $wday = $t->wdayname;  # Current weekday name (Sun, Mon, etc.)

# Adjust for Monday to point to Friday
my $days_to_subtract = ($wday eq 'Mon') ? 3 : 1;

# Path to the project mappings file
my $project_mappings_file = '/home/decoder/dev/dotfiles/scripts/__project_mappings.conf';
# Path to the script that generates the XML content
my $xml_script = '/home/decoder/dev/dotfiles/scripts/__format_tasks_xml.pl';

# Read project mappings
my %project_mappings;
open my $map_fh, '<', $project_mappings_file or die "Could not open file '$project_mappings_file': $!";
while (<$map_fh>) {
  if (/^\s*\[\s*"([^"]+)"\s*\]\s*=\s*"([^"]+)"/) {
    $project_mappings{$1} = $2;
  }
}
close $map_fh;

# Call the XML generating script and capture its output
my $xml_content = `$xml_script`;
die "Error running '$xml_script': $!" unless defined $xml_content;

# Replace unescaped ampersands
$xml_content =~ s/&(?![A-Za-z0-9#]+;)/&amp;/g;

# Create a parser and parse the modified content
my $parser = XML::LibXML->new;
my $doc = $parser->load_xml(string => $xml_content);

# Hash to store tasks grouped by project
my %tasks_by_project;

# Get yesterday's date in the required format
my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time - $days_to_subtract * 24 * 60 * 60);
my $yesterday = sprintf "%4d%02d%02d", $year + 1900, $mon + 1, $mday;

# Iterate through the tasks and process them
for my $task ($doc->findnodes('/tasks/task')) {
  my $status = $task->findvalue('status');
  my $end_date = $task->findvalue('end');
  $end_date =~ s/T.*//; # Remove time component
  my $tags = join ' ', $task->findnodes('tags/tag/text()');
  
  # Skip tasks without the +work tag or with the +idea tag
  next unless $tags =~ /\bwork\b/;
  next if $tags =~ /\bidea\b/;

  # Determine if we should include the task based on the mode
  next unless ($mode eq '+next' && $status eq 'pending' && $tags =~ /\bnext\b/) ||
              ($mode eq '+pending' && $status eq 'pending') ||
              ($mode eq '' && $status eq 'completed' && $end_date eq $yesterday);

  my $project_key = $task->findvalue('project') || ' ';
  my $project = $project_mappings{$project_key} || 'Unknown';
  my $url_index = 1; # Keep track of the URL index
  my $description = $task->findvalue('description');
  my $anno_text = "";
  my $checkbox = ($status eq 'pending') ? "[ ]" : "[x]";

  # Process annotations and extract links
  for my $anno ($task->findnodes('annotations/annotation')) {
    if ($anno->findvalue('description') =~ /(https:\/\/\S+)/) {
      $anno_text .= " [[${url_index}]]($1)"; # Fixed Markdown link format
      $url_index++; # Increment the URL index
    }
  }

  # Add to the group
  push @{$tasks_by_project{$project}}, "$checkbox $description$anno_text";
}

# Print the tasks grouped by project
for my $project (sort keys %tasks_by_project) {
  print "$project\n";
  for my $task (@{$tasks_by_project{$project}}) {
    print "- $task\n";
  }
  print "\n"; # Single newline between groups
}
