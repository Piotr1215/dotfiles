#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;

# Path to the project mappings file
my $project_mappings_file = '__project_mappings.conf';
# Path to the script that generates the XML content
my $xml_script = './__format_tasks_xml.pl';

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
my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time - 24*60*60);
my $yesterday = sprintf "%4d%02d%02d", $year + 1900, $mon + 1, $mday;

# Iterate through the tasks and process them
for my $task ($doc->findnodes('/tasks/task')) {
  my $status = $task->findvalue('status');
  my $end_date = $task->findvalue('end');
  $end_date =~ s/T.*//; # Remove time component

  # Skip if the task is not completed or not completed yesterday
  next unless $status eq 'completed' && $end_date eq $yesterday;

  my $project_key = $task->findvalue('project') || ' ';
  my $project = $project_mappings{$project_key} || 'Unknown';
  my $url_index = 1; # Keep track of the URL index
  my $description = $task->findvalue('description');
  my $anno_text = "";

  # Process annotations and extract links
  for my $anno ($task->findnodes('annotations/annotation')) {
    if ($anno->findvalue('description') =~ /(https:\/\/\S+)/) {
      $anno_text .= " [[${url_index}]($1)]";
      $url_index++; # Increment the URL index
    }
  }

  # Add to the group
  push @{$tasks_by_project{$project}}, "[x] $description$anno_text";
}

# Print the tasks grouped by project
for my $project (sort keys %tasks_by_project) {
  print "$project\n"; # Removed extra newline here
  for my $task (@{$tasks_by_project{$project}}) {
    print "- $task\n";
  }
  print "\n"; # Single newline between groups
}
