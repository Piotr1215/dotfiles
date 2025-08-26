#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;
use File::Basename;
use File::Path qw(make_path);

my $t = localtime;
my $wday = $t->wdayname;

# Store timestamp file for tracking when standup was last run
my $timestamp_dir = "$ENV{HOME}/.local/state/standup";
make_path($timestamp_dir) unless -d $timestamp_dir;
my $timestamp_file = "$timestamp_dir/last_standup_timestamp";
my $current_timestamp = time();

# Read the last standup timestamp
my $last_standup_timestamp;
if (-f $timestamp_file) {
    open my $fh, '<', $timestamp_file or die "Cannot read timestamp file: $!";
    $last_standup_timestamp = <$fh>;
    chomp $last_standup_timestamp if $last_standup_timestamp;
    close $fh;
}

# Write current timestamp for next run
open my $fh, '>', $timestamp_file or die "Cannot write timestamp file: $!";
print $fh $current_timestamp;
close $fh;
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

# Determine the cutoff timestamp for tasks
my $cutoff_timestamp;
my $github_date_range;

if ($last_standup_timestamp) {
    # We have a previous standup timestamp, use it as the cutoff
    $cutoff_timestamp = $last_standup_timestamp;
    
    # Format dates for GitHub PR search
    my $last_t = localtime($last_standup_timestamp);
    $github_date_range = sprintf "%4d-%02d-%02d..%4d-%02d-%02d",
        $last_t->year, $last_t->mon, $last_t->mday, $t->year, $t->mon, $t->mday;
} else {
    # No previous standup timestamp, use day-based logic as fallback
    if ($wday eq 'Mon') {
        # Monday: Show tasks since Friday morning
        $cutoff_timestamp = time() - 3 * 24 * 60 * 60;
    } elsif ($wday eq 'Wed') {
        # Wednesday: Show tasks since Monday morning  
        $cutoff_timestamp = time() - 2 * 24 * 60 * 60;
    } elsif ($wday eq 'Fri') {
        # Friday: Show tasks since Wednesday morning
        $cutoff_timestamp = time() - 2 * 24 * 60 * 60;
    } else {
        # Default: Show tasks since yesterday
        $cutoff_timestamp = time() - 24 * 60 * 60;
    }
    
    my $cutoff_t = localtime($cutoff_timestamp);
    $github_date_range = sprintf "%4d-%02d-%02d..%4d-%02d-%02d",
        $cutoff_t->year, $cutoff_t->mon, $cutoff_t->mday, $t->year, $t->mon, $t->mday;
}

# Convert cutoff timestamp to ISO format for comparison
my $cutoff_t = localtime($cutoff_timestamp);
my $cutoff_iso = $cutoff_t->strftime('%Y%m%dT%H%M%S');

# Print header and debug info
print "**Auto-generated status update**\n";

# Debug mode - show timestamp info if DEBUG env var is set
if ($ENV{DEBUG}) {
    if ($last_standup_timestamp) {
        my $last_date = localtime($last_standup_timestamp)->strftime('%Y-%m-%d %H:%M:%S');
        print "# DEBUG: Last standup was at $last_date\n";
    } else {
        print "# DEBUG: No previous standup timestamp found\n";
    }
    my $cutoff_date = $cutoff_t->strftime('%Y-%m-%d %H:%M:%S');
    print "# DEBUG: Showing tasks completed after $cutoff_date\n";
    print "# DEBUG: GitHub date range: $github_date_range\n";
}

print "\n";

my $last_week_days_to_subtract = 7;
my ($sec_last, $min_last, $hour_last, $mday_last, $mon_last, $year_last) = 
    localtime(time - $last_week_days_to_subtract * 24 * 60 * 60);
my $last_week_date = sprintf "%4d%02d%02d", $year_last + 1900, $mon_last + 1, $mday_last;

for my $task ($doc->findnodes('/tasks/task')) {
    my $status = $task->findvalue('status');
    my $end_datetime = $task->findvalue('end');
    my $tags = join ' ', $task->findnodes('tags/tag/text()');
    
    next unless $tags =~ /\bwork\b/;
    next if $tags =~ /\bidea\b/;
    next unless $status eq 'completed';
    
    # Parse the task completion timestamp
    # TaskWarrior format is like: 20240826T141523Z
    my $task_iso = $end_datetime;
    $task_iso =~ s/Z$//;  # Remove Z suffix for comparison
    
    # Check if task was completed after last standup
    my $in_current_period = $task_iso ge $cutoff_iso;
    
    # For last week section, check if it's older than cutoff but within last 7 days
    my $end_date = $end_datetime;
    $end_date =~ s/T.*//;
    my $in_last_week = !$in_current_period && $end_date ge $last_week_date;
    
    next unless $in_current_period || $in_last_week;

    my $project_key = $task->findvalue('project') || ' ';
    my $project = $project_mappings{$project_key} || 'PRs and Reviews';
    
    # Skip admin project tasks
    next if $project eq 'Various admin tasks';
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
    if ($in_current_period) {
        $period = 'current';
    } else {
        $period = 'last_week';
    }

    push @{$tasks_by_project_by_period{$period}{$project}}, "$checkbox $description$anno_text";
}

# Get all projects from current period to ensure consistent categories
my %all_projects;
if (exists $tasks_by_project_by_period{current}) {
    for my $project (keys %{$tasks_by_project_by_period{current}}) {
        $all_projects{$project} = 1;
    }
}

my $any_tasks_printed = 0;

# Print tasks by project for current period
# First print all projects except PRs and Reviews
for my $project (sort keys %all_projects) {
    next if $project eq 'PRs and Reviews';  # Skip PRs and Reviews for now
    
    my @tasks;
    
    # Add current period tasks if any
    if (exists $tasks_by_project_by_period{current}{$project}) {
        push @tasks, @{$tasks_by_project_by_period{current}{$project}};
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

# Now print PRs and Reviews at the bottom
my @pr_tasks;

# Skip taskwarrior PR tasks - we'll get them from GitHub directly

# Get merged PRs I authored
my $authored_prs_json = `gh search prs --author "\@me" --owner "loft-sh" --merged --merged-at "$github_date_range" --limit 50 --json url,title,number 2>/dev/null`;
if ($authored_prs_json) {
    my @authored_lines = `echo '$authored_prs_json' | jq -r '.[] | "[x] " + .title + " (#" + (.number | tostring) + ") [[1]](" + .url + ")"' 2>/dev/null`;
    push @pr_tasks, map { chomp; $_ } @authored_lines;
}

# Get merged PRs I reviewed (excluding my own)
my $reviewed_prs_json = `gh search prs --reviewed-by "\@me" --owner "loft-sh" --merged --merged-at "$github_date_range" --limit 50 --json url,title,number,author 2>/dev/null`;
if ($reviewed_prs_json) {
    my @reviewed_lines = `echo '$reviewed_prs_json' | jq -r '.[] | select(.author.login != "decoder" and .author.login != "\@me") | "[x] " + .title + " (#" + (.number | tostring) + ") [[1]](" + .url + ")"' 2>/dev/null`;
    push @pr_tasks, map { chomp; $_ } @reviewed_lines;
}

# Remove duplicates and print if we have any PR tasks
if (@pr_tasks) {
    my %seen;
    @pr_tasks = grep { !$seen{$_}++ } @pr_tasks;
    
    print "PRs and Reviews\n";
    for my $task (@pr_tasks) {
        print "- $task\n";
    }
    print "\n";
    $any_tasks_printed = 1;
}

# Print a message if no tasks found
if (!$any_tasks_printed) {
    my $date_range_text;
    if ($last_standup_timestamp) {
        my $hours_since = int((time() - $last_standup_timestamp) / 3600);
        my $days_since = int($hours_since / 24);
        if ($days_since > 0) {
            $date_range_text = "the last $days_since day" . ($days_since > 1 ? "s" : "");
        } else {
            $date_range_text = "the last $hours_since hour" . ($hours_since != 1 ? "s" : "");
        }
    } elsif ($wday eq 'Mon') {
        $date_range_text = "Friday or Monday";
    } elsif ($wday eq 'Wed') {
        $date_range_text = "Monday, Tuesday, or Wednesday";
    } elsif ($wday eq 'Fri') {
        $date_range_text = "Wednesday, Thursday, or Friday";
    } else {
        $date_range_text = "yesterday or today";
    }
    print "No completed tasks since $date_range_text.\n\n";
}

print "----Last Week----\n\n";
if (%{$tasks_by_project_by_period{last_week}}) {
    # First print all projects except PRs and Reviews
    for my $project (sort keys %{$tasks_by_project_by_period{last_week}}) {
        next if $project eq 'PRs and Reviews';  # Skip PRs and Reviews for now
        
        print "$project\n";
        for my $task (@{$tasks_by_project_by_period{last_week}{$project}}) {
            print "- $task\n";
        }
        print "\n";
    }
    
    # Now print PRs and Reviews at the bottom
    if (exists $tasks_by_project_by_period{last_week}{'PRs and Reviews'}) {
        print "PRs and Reviews\n";
        for my $task (@{$tasks_by_project_by_period{last_week}{'PRs and Reviews'}}) {
            print "- $task\n";
        }
        print "\n";
    }
} else {
    print "No completed tasks last week.\n\n";
}
