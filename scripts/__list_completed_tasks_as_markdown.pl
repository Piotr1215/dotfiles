#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;

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

my %tasks_yesterday;
my %tasks_last_week;

my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time - $days_to_subtract * 24 * 60 * 60);
my $yesterday = sprintf "%4d%02d%02d", $year + 1900, $mon + 1, $mday;

my $last_week_days_to_subtract = 7;
my ($sec_last, $min_last, $hour_last, $mday_last, $mon_last, $year_last) = localtime(time - $last_week_days_to_subtract * 24 * 60 * 60);
my $last_week_date = sprintf "%4d%02d%02d", $year_last + 1900, $mon_last + 1, $mday_last;

for my $task ($doc->findnodes('/tasks/task')) {
    my $status = $task->findvalue('status');
    my $end_date = $task->findvalue('end');
    $end_date =~ s/T.*//;
    my $tags = join ' ', $task->findnodes('tags/tag/text()');

    next unless $tags =~ /\bwork\b/;
    next if $tags =~ /\bidea\b/;
    next unless $status eq 'completed' && ($end_date eq $yesterday || $end_date ge $last_week_date);

    my $project_key = $task->findvalue('project') || ' ';
    my $project = $project_mappings{$project_key} || 'Unknown';
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

    if ($end_date eq $yesterday) {
        push @{$tasks_yesterday{$project}}, "$checkbox $description$anno_text";
    } else {
        push @{$tasks_last_week{$project}}, "$checkbox $description$anno_text";
    }
}

for my $project (sort keys %tasks_yesterday) {
    print "$project\n";
    for my $task (@{$tasks_yesterday{$project}}) {
        print "- $task\n";
    }
    print "\n";
}

print "----Last Week----\n\n";

for my $project (sort keys %tasks_last_week) {
    print "$project\n";
    for my $task (@{$tasks_last_week{$project}}) {
        print "- $task\n";
    }
    print "\n";
}
