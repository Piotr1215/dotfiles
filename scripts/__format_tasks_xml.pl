#! /usr/bin/perl
use strict;
use warnings;

# Give a nice error if the (non-standard) JSON module is not installed.
eval "use JSON";
if ($@)
{
  print "Error: You need to install the JSON Perl module.\n";
  exit 1;
}

# Use the taskwarrior 2.0+ export command to filter and return JSON
my $command = join (' ', ("env PATH=$ENV{PATH} task rc.verbose=nothing rc.json.array=no export", @ARGV));
if ($command =~ /No matches/)
{
  printf STDERR $command;
  exit 1;
}

# Generate output.
print "<tasks>\n";
for my $task (split "\n", qx{$command})
{
  my $data = from_json ($task);

  print "  <task>\n";
  for my $key (keys %$data)
  {
    if ($key eq 'annotations')
    {
      print "    <annotations>\n";
      for my $anno (@{$data->{$key}})
      {
        print "      <annotation>\n";
        print "        <$_>$anno->{$_}</$_>\n" for keys %$anno;
        print "      </annotation>\n";
      }
      print "    </annotations>\n";
    }
    elsif ($key eq 'tags')
    {
      print "    <tags>\n";
      print "      <tag>$_</tag>\n" for @{$data->{'tags'}};
      print "    </tags>\n";
    }
    else
    {
      print "    <$key>$data->{$key}</$key>\n";
    }
  }
  print "  </task>\n";
}

print "</tasks>\n";
exit 0;
