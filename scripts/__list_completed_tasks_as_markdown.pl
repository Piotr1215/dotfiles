#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;
use File::Basename;
use File::Path qw(make_path);
use JSON::PP;

my $t = localtime;
my $wday_num = $t->wday;  # 0=Sun, 1=Mon, ..., 6=Sat
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

# Group by day, then by project within each day
my %tasks_by_day_project;  # {day_name}{project} = [tasks]

# Simple: last 7 days for everything
my $cutoff_date = $t->epoch - (7 * 86400);
my $cutoff_t = localtime($cutoff_date);
my $cutoff_ymd = $cutoff_t->strftime('%Y%m%d');

# Print header and debug info
print "**Auto-generated status update**\n";

if ($ENV{DEBUG}) {
    print "# DEBUG: Cutoff: " . $cutoff_t->strftime('%Y-%m-%d %H:%M') . "\n";
}

print "\n";

for my $task ($doc->findnodes('/tasks/task')) {
    my $status = $task->findvalue('status');
    my $end_datetime = $task->findvalue('end');
    my $tags = join ' ', $task->findnodes('tags/tag/text()');

    next unless $tags =~ /\bwork\b/;
    next if $tags =~ /\bidea\b/;
    next unless $status eq 'completed';

    # Parse the task completion timestamp
    # Simple: include if completed within last 7 days
    my ($task_ymd) = $end_datetime =~ /^(\d{8})/;
    next unless $task_ymd ge $cutoff_ymd;

    # Get day name from completion date
    my $task_t = Time::Piece->strptime($task_ymd, '%Y%m%d');
    my $day_name = $task_t->strftime('%A');  # Monday, Tuesday, etc.
    my $day_sort = $task_ymd;  # For sorting days chronologically

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

    push @{$tasks_by_day_project{"$day_sort|$day_name"}{$project}}, "$checkbox $description$anno_text";
}

my $any_tasks_printed = 0;

# Print completed tasks grouped by day, then by project
for my $day_key (sort keys %tasks_by_day_project) {
    my ($day_sort, $day_name) = split /\|/, $day_key;

    # Collect non-PR projects for this day
    my @day_projects;
    for my $project (sort keys %{$tasks_by_day_project{$day_key}}) {
        next if $project eq 'PRs and Reviews';
        push @day_projects, $project;
    }

    # Skip day header if no non-PR tasks
    next unless @day_projects;

    print "-- $day_name --\n";
    for my $project (@day_projects) {
        print "$project\n";
        print "- $_\n" for @{$tasks_by_day_project{$day_key}{$project}};
        print "\n";
        $any_tasks_printed = 1;
    }
}

# Work in Progress section - tasks with started/review tags and their PRs
my $wip_printed = 0;

# Get tasks with started or review tags (in progress work)
my $wip_json = `task +work \\( +started or +review \\) export rc.verbose=nothing 2>/dev/null`;

if ($wip_json) {
    my $wip_tasks = eval { decode_json($wip_json) } || [];

    # Group by project for cleaner output
    my %wip_by_project;

    for my $task (@$wip_tasks) {
        next unless $task->{status} eq 'pending';
        my $tags = join(' ', @{$task->{tags} || []});
        next if $tags =~ /\bidea\b/;

        my $project_key = $task->{project} || ' ';
        my $project = $project_mappings{$project_key} || 'Other';

        # Skip admin
        next if $project eq 'Various admin tasks';

        my $desc = $task->{description};
        my @linear_urls;
        my @pr_urls;

        # Extract URLs from annotations
        my $linear_id;
        for my $anno (@{$task->{annotations} || []}) {
            my $anno_desc = $anno->{description} || '';
            if ($anno_desc =~ m{linear\.app/[^/]+/issue/([A-Z]+-\d+)}) {
                $linear_id = $1;
                push @linear_urls, $anno_desc;
            } elsif ($anno_desc =~ m{(https://github\.com/\S+/pull/\d+)}) {
                push @pr_urls, $1;
            }
        }

        # Skip tasks without Linear URL - no context to report
        next unless $linear_id;

        # Fetch PRs from Linear
        my @prs;  # array of {url, title, createdAt}
        if ($linear_id) {
            my $pr_json = `~/.claude/scripts/__linear_get_prs.sh $linear_id 2>/dev/null`;
            if ($pr_json) {
                my $pr_data = eval { decode_json($pr_json) };
                if ($pr_data && $pr_data->{prs}) {
                    # Filter PRs by cutoff date (last 7 days)
                    for my $pr (@{$pr_data->{prs}}) {
                        next unless $pr->{createdAt};
                        my ($pr_ymd) = $pr->{createdAt} =~ /^(\d{4}-\d{2}-\d{2})/;
                        $pr_ymd =~ s/-//g;  # 20260102
                        push @prs, $pr if $pr_ymd ge $cutoff_ymd;
                    }
                }
            }
        }

        # Skip tasks with no recent PRs - no progress to report
        next unless @prs;

        # Build inline PR links
        my $pr_links = '';
        if (@prs) {
            my @links = map { "[$_->{title}]($_->{url})" } @prs;
            $pr_links = " | " . join(", ", @links);
        }

        # Build the task line with inline PRs
        my $linear_link = @linear_urls ? " [[Linear]]($linear_urls[0])" : "";
        my $task_line = "[ ] $desc$linear_link$pr_links";

        push @{$wip_by_project{$project}}, $task_line;
    }

    # Print WIP tasks grouped by project
    for my $project (sort keys %wip_by_project) {
        print "$project\n";
        print "- $_\n" for @{$wip_by_project{$project}};
        print "\n";
        $wip_printed = 1;
    }
}

if (!$wip_printed) {
    print "No tasks currently in progress.\n\n";
}

# Print a message if no tasks found
if (!$any_tasks_printed) {
    print "No completed tasks in the last 7 days.\n\n";
}
