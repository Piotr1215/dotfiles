#!/usr/bin/perl
# PROJECT: standup
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;

# Convert command line arguments into an array of modes
my @modes = map { s/^\+//; $_ } @ARGV;
my $last_week = (@modes == 0) ? 1 : 0;  # Set last_week flag if no modes specified

my $t = localtime;
my $wday = $t->wdayname;
my $days_to_subtract = ($wday eq 'Mon') ? 3 : 1;
my $project_mappings_file = '/home/decoder/dev/dotfiles/scripts/__project_mappings.conf';
my $xml_script = '/home/decoder/dev/dotfiles/scripts/__format_tasks_xml.pl';
my %project_mappings;

open my $map_fh, '<', $project_mappings_file or die "Could not open file '$project_mappings_file': $!";
while (<$map_fh>) {
  if (/^\s*\[\s*"([^"]+)"\s*\]\s*=\s*"([^"]+)"/) {
    $project_mappings{$1} = $2;
  }
}
close $map_fh;

my $xml_content = `$xml_script`;
die "Error running '$xml_script': $!" unless defined $xml_content;
$xml_content =~ s/&(?![A-Za-z0-9#]+;)/&amp;/g;
$xml_content =~ s{(<description>.*?)(<)(.*?</description>)}{$1&lt;$3}g;

my $parser = XML::LibXML->new;
my $doc = $parser->load_xml(string => $xml_content);
my %tasks_by_project;

my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time - $days_to_subtract * 24 * 60 * 60);
my $yesterday = sprintf "%4d%02d%02d", $year + 1900, $mon + 1, $mday;

my $last_week_days_to_subtract = 7;
my ($sec_last, $min_last, $hour_last, $mday_last, $mon_last, $year_last) = localtime(time - $last_week_days_to_subtract * 24 * 60 * 60);
my $last_week_date = sprintf "%4d%02d%02d", $year_last + 1900, $mon_last + 1, $mday_last;

# Special handling for review mode
my $is_review_mode = (@modes == 1 && $modes[0] eq 'review');

for my $task ($doc->findnodes('/tasks/task')) {
  my $status = $task->findvalue('status');
  my $end_date = $task->findvalue('end');
  $end_date =~ s/T.*//;
  my $tags = join ' ', $task->findnodes('tags/tag/text()');
  
  next unless $tags =~ /\bwork\b/;
  next if $tags =~ /\bidea\b/;
  
  # New task filtering logic for multiple modes
  my $include_task = 0;
  if (@modes) {
    # Check if any of the specified modes match the tags
    for my $mode (@modes) {
      if ($mode eq 'pending') {
        $include_task = 1 if $status eq 'pending';
      } else {
        $include_task = 1 if $tags =~ /\b$mode\b/ && $status eq 'pending';
      }
    }
  } else {
    # Original completed tasks logic
    $include_task = 1 if $status eq 'completed' && 
                        ($end_date eq $yesterday || ($last_week && $end_date ge $last_week_date));
  }
  
  next unless $include_task;

  my $project_key = $task->findvalue('project') || ' ';
  # If in review mode, force all tasks into a single category
  my $project = $is_review_mode ? 'PRs and Issues in Review' : ($project_mappings{$project_key} || 'Unknown');
  my $url_index = 1;
  my $description = $task->findvalue('description');
  my $anno_text = "";
  my $checkbox = ($status eq 'pending') ? "[ ]" : "[x]";
  
  # Get priority and map to emoji
  my $priority = $task->findvalue('priority') || '';
  my $priority_emoji = '';
  if ($priority eq 'H') {
    $priority_emoji = '🇭 ';
  } elsif ($priority eq 'M') {
    $priority_emoji = '🇲 ';
  } elsif ($priority eq 'L') {
    $priority_emoji = '🇱 ';
  }
  
  for my $anno ($task->findnodes('annotations/annotation')) {
    if ($anno->findvalue('description') =~ /(https:\/\/\S+)/) {
      $anno_text .= " [[${url_index}]]($1)";
      $url_index++;
    }
  }
  
  push @{$tasks_by_project{$project}}, "$priority_emoji$checkbox $description$anno_text";
}

print "----------------\n" if $last_week;
for my $project (sort keys %tasks_by_project) {
  print "$project\n";
  for my $task (@{$tasks_by_project{$project}}) {
    print "- $task\n";
  }
  print "\n";
}
