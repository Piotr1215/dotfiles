#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;
use Time::Piece;
use JSON::PP;

my $t = localtime;
my $project_mappings_file = '/home/decoder/dev/dotfiles/scripts/__project_mappings.conf';
my $xml_script = '/home/decoder/dev/dotfiles/scripts/__format_tasks_xml.pl';

my %project_mappings;
open my $map_fh, '<', $project_mappings_file or die "Could not open '$project_mappings_file': $!";
while (<$map_fh>) {
    $project_mappings{$1} = $2 if /^\s*\[\s*"([^"]+)"\s*\]\s*=\s*"([^"]+)"/;
}
close $map_fh;

my $cutoff_date = $t->epoch - (7 * 86400);
my $cutoff_ymd = localtime($cutoff_date)->strftime('%Y%m%d');

# Structure: {project}{day_sort|day_name} = [tasks]
my %tasks;

# --- Completed tasks from XML ---
my $xml_content = `$xml_script`;
$xml_content =~ s/&(?![A-Za-z0-9#]+;)/&amp;/g;
$xml_content =~ s{(<description>.*?)(<)(.*?</description>)}{$1&lt;$3}g;

my $doc = XML::LibXML->new->load_xml(string => $xml_content);

for my $task ($doc->findnodes('/tasks/task')) {
    my $status = $task->findvalue('status');
    my $end_datetime = $task->findvalue('end');
    my $tags = join ' ', $task->findnodes('tags/tag/text()');

    next unless $tags =~ /\bwork\b/ && $status eq 'completed';
    next if $tags =~ /\bidea\b/;

    my ($task_ymd) = $end_datetime =~ /^(\d{8})/;
    next unless $task_ymd ge $cutoff_ymd;

    my $task_t = Time::Piece->strptime($task_ymd, '%Y%m%d');
    my $day_key = $task_ymd . '|' . $task_t->strftime('%a %d %b');

    my $project = $project_mappings{$task->findvalue('project') || ' '} || 'PRs and Reviews';
    next if $project eq 'Various admin tasks' || $project eq 'PRs and Reviews';

    my $desc = $task->findvalue('description');
    my $anno_text = "";
    my $i = 1;
    for my $anno ($task->findnodes('annotations/annotation')) {
        if ($anno->findvalue('description') =~ /(https:\/\/\S+)/) {
            $anno_text .= " [[${i}]]($1)";
            $i++;
        }
    }

    push @{$tasks{$project}{$day_key}}, "[x] $desc$anno_text";
}

# --- In-progress tasks ---
my $wip_json = `task +work \\( +started or +review \\) export rc.verbose=nothing 2>/dev/null`;
if ($wip_json) {
    my $wip_tasks = eval { decode_json($wip_json) } || [];

    for my $task (@$wip_tasks) {
        next unless $task->{status} eq 'pending';
        my $tags = join(' ', @{$task->{tags} || []});
        next if $tags =~ /\bidea\b/;

        my $project = $project_mappings{$task->{project} || ' '} || 'Other';
        next if $project eq 'Various admin tasks';

        my $linear_id;
        my @linear_urls;
        for my $anno (@{$task->{annotations} || []}) {
            if (($anno->{description} || '') =~ m{linear\.app/[^/]+/issue/([A-Z]+-\d+)}) {
                $linear_id = $1;
                push @linear_urls, $anno->{description};
            }
        }
        next unless $linear_id;

        # Fetch PRs and find most recent date
        my $pr_json = `~/.claude/scripts/__linear_get_prs.sh $linear_id 2>/dev/null`;
        my @prs;
        my $latest_ymd = $cutoff_ymd;
        if ($pr_json) {
            my $pr_data = eval { decode_json($pr_json) };
            if ($pr_data && $pr_data->{prs}) {
                for my $pr (@{$pr_data->{prs}}) {
                    next unless $pr->{createdAt};
                    my ($pr_ymd) = $pr->{createdAt} =~ /^(\d{4}-\d{2}-\d{2})/;
                    $pr_ymd =~ s/-//g;
                    if ($pr_ymd ge $cutoff_ymd) {
                        push @prs, $pr;
                        $latest_ymd = $pr_ymd if $pr_ymd gt $latest_ymd;
                    }
                }
            }
        }
        next unless @prs;

        my $task_t = Time::Piece->strptime($latest_ymd, '%Y%m%d');
        my $day_key = $latest_ymd . '|' . $task_t->strftime('%a %d %b');

        my $pr_links = " | " . join(", ", map { "[$_->{title}]($_->{url})" } @prs);
        my $linear_link = @linear_urls ? " [[Linear]]($linear_urls[0])" : "";

        push @{$tasks{$project}{$day_key}}, "[ ] $task->{description}$linear_link$pr_links";
    }
}

# --- Print: project → day → tasks (completed first, then in-progress) ---
for my $project (sort keys %tasks) {
    print "$project\n\n";
    for my $day_key (sort keys %{$tasks{$project}}) {
        my ($sort, $day) = split /\|/, $day_key;
        print "--- $day ---\n";
        my @sorted = sort { ($a =~ /^\[x\]/ ? 0 : 1) <=> ($b =~ /^\[x\]/ ? 0 : 1) } @{$tasks{$project}{$day_key}};
        print "- $_\n" for @sorted;
        print "\n";
    }
}
