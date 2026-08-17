#! /usr/bin/perl
use strict;
use warnings;

# JSON::PP is core, so unlike the non-core JSON this cannot go missing under a
# perl upgrade. The guard that used to sit here caught exactly that and then
# reported it as "install the JSON module", which reads as a packaging problem
# rather than a dependency choice, so it is gone with the dependency.
use JSON::PP;

# decode_json hands back character strings, not the byte strings the old
# non-core from_json produced, so STDOUT has to be told to encode them. Without
# this every task carrying a non-ASCII character prints a "Wide character"
# warning into the pane while still emitting correct bytes, which is noise that
# looks like breakage.
binmode(STDOUT, ':encoding(UTF-8)');

# Task descriptions and annotations are free text: they hold shell snippets with
# <redirects>, ampersands, and the odd control character pasted in from a
# terminal. Emitting them raw produced XML that libxml refused to parse
# ("PCDATA invalid Char value 8", "Opening and ending tag mismatch"), which the
# consumers tried to paper over with fix-up regexes that only caught the first
# offender per description. Escaping at the point of generation is the layer
# that can actually be complete.
#
# The character filter is the XML 1.0 production for Char: tab, newline,
# carriage return, then #x20 and up. Anything below that has no representation
# in XML at all, not even as an entity, so it can only be dropped.
sub xml_escape
{
  my ($text) = @_;
  return '' unless defined $text;

  $text =~ s/[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
  $text =~ s/&/&amp;/g;
  $text =~ s/</&lt;/g;
  $text =~ s/>/&gt;/g;

  return $text;
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
  my $data = decode_json ($task);

  print "  <task>\n";
  for my $key (keys %$data)
  {
    if ($key eq 'annotations')
    {
      print "    <annotations>\n";
      for my $anno (@{$data->{$key}})
      {
        print "      <annotation>\n";
        print "        <$_>" . xml_escape ($anno->{$_}) . "</$_>\n" for keys %$anno;
        print "      </annotation>\n";
      }
      print "    </annotations>\n";
    }
    elsif ($key eq 'tags')
    {
      print "    <tags>\n";
      print "      <tag>" . xml_escape ($_) . "</tag>\n" for @{$data->{'tags'}};
      print "    </tags>\n";
    }
    else
    {
      print "    <$key>" . xml_escape ($data->{$key}) . "</$key>\n";
    }
  }
  print "  </task>\n";
}

print "</tasks>\n";
exit 0;
