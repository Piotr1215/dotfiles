#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;

print "**Auto-generated status update**\n\n";

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

# Use combined collection for all time periods
my %tasks_by_project_by_period;

my $today = sprintf "%4d%02d%02d", $t->year, $t->mon, $t->mday;
my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time - $days_to_subtract * 24 * 60 * 60);
my $yesterday = sprintf "%4d%02d%02d", $year + 1900, $mon + 1, $mday;

my $last_week_days_to_subtract = 7;
my ($sec_last, $min_last, $hour_last, $mday_last, $mon_last, $year_last) = 
    localtime(time - $last_week_days_to_subtract * 24 * 60 * 60);
my $last_week_date = sprintf "%4d%02d%02d", $year_last + 1900, $mon_last + 1, $mday_last;

for my $task ($doc->findnodes('/tasks/task')) {
    my $status = $task->findvalue('status');
    my $end_date = $task->findvalue('end');
    $end_date =~ s/T.*//;
    my $tags = join ' ', $task->findnodes('tags/tag/text()');
    
    next unless $tags =~ /\bwork\b/;
    next if $tags =~ /\bidea\b/;
    next unless $status eq 'completed' && 
        ($end_date eq $today || $end_date eq $yesterday || $end_date ge $last_week_date);

    my $project_key = $task->findvalue('project') || ' ';
    my $project = $project_mappings{$project_key} || 'PRs and Reviews';
    my $url_index = 1;
    my $description = $task->findvalue('description');
    my $anno_text = "";
    my $checkbox = "[x]";

    for my $anno ($task->findnodes('annotations/annotation')) {
        if ($anno->findvalue('description') =~ /(https:\/\/\S+)/) {
            $anno_text .= " [[${url_index}]]($1)";
            $url_index++;
        }
    }

    my $period;
    if ($end_date eq $today) {
        $period = 'today';
    } elsif ($end_date eq $yesterday) {
        $period = 'yesterday';
    } else {
        $period = 'last_week';
    }

    push @{$tasks_by_project_by_period{$period}{$project}}, "$checkbox $description$anno_text";
}

# Merge today and yesterday tasks

# Get all projects from both today and yesterday to ensure consistent categories
my %all_projects;
for my $period ('today', 'yesterday') {
    if (exists $tasks_by_project_by_period{$period}) {
        for my $project (keys %{$tasks_by_project_by_period{$period}}) {
            $all_projects{$project} = 1;
        }
    }
}

my $any_tasks_printed = 0;

# Print tasks by project merging today and yesterday
for my $project (sort keys %all_projects) {
    my @tasks;
    
    # Add today's tasks if any
    if (exists $tasks_by_project_by_period{today}{$project}) {
        push @tasks, @{$tasks_by_project_by_period{today}{$project}};
    }
    
    # Add yesterday's tasks if any
    if (exists $tasks_by_project_by_period{yesterday}{$project}) {
        push @tasks, @{$tasks_by_project_by_period{yesterday}{$project}};
    }
    
    # Print project and tasks if we have any
    if (@tasks) {
        print "$project\n";
        for my $task (@tasks) {
            print "- $task\n";
        }
        print "\n";
        $any_tasks_printed = 1;
    }
}

# Print a message if no tasks found
if (!$any_tasks_printed) {
    print "No completed tasks today or yesterday.\n\n";
}

print "----Last Week----\n\n";
if (%{$tasks_by_project_by_period{last_week}}) {
    for my $project (sort keys %{$tasks_by_project_by_period{last_week}}) {
        print "$project\n";
        for my $task (@{$tasks_by_project_by_period{last_week}{$project}}) {
            print "- $task\n";
        }
        print "\n";
    }
} else {
    print "No completed tasks last week.\n\n";
}
