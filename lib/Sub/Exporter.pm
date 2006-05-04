package Sub::Exporter;

use strict;
use warnings;

use Carp ();
use Data::OptList ();
use Params::Util ();
use Sub::Install 0.91 ();

=head1 NAME

Sub::Exporter - a sophisticated exporter for custom-built routines

=head1 VERSION

version 0.953

  $Id$

=cut

our $VERSION = '0.953';

=head1 SYNOPSIS

Sub::Exporter must be used in two places.  First, in an exporting module:

  # in the exporting module:
  package Text::Tweaker;
  use Sub::Exporter -setup => {
    exports => [
      qw(squish titlecase) # always works the same way
      reformat => \&build_reformatter, # generator to build exported function
      trim     => \&build_trimmer,
      indent   => \&build_indenter,
    ],
    collectors => [ 'defaults' ],
  };

Then, in an importing module:

  # in the importing module:
  use Text::Tweaker
    'squish',
    indent   => { margin => 5 },
    reformat => { width => 79, justify => 'full', -as => 'prettify_text' },
    defaults => { eol => 'CRLF' };

With this setup, the importing module ends up with three routines: C<squish>,
C<indent>, and C<prettify_text>.  The latter two have been built to the
specifications of the importer -- they are not just copies of the code in the
exporting package.

=head1 DESCRIPTION

B<ACHTUNG!>  If you're not familiar with Exporter or exporting, read
L<Sub::Exporter::Tutorial> first!

=head2 Why Generators?

The biggest benefit of Sub::Exporter over existing exporters (including the
ubiquitous Exporter.pm) is its ability to build new coderefs for export, rather
than to simply export code identical to that found in the exporting package.

If your module's consumers get a routine that works like this:

  use Data::Analyze qw(analyze);
  my $value = analyze($data, $tolerance, $passes);

and they constantly pass only one or two different set of values for the
non-C<$data> arguments, your code can benefit from Sub::Exporter.  By writing a
simple generator, you can let them do this, instead:

  use Data::Analyze
    analyze => { tolerance => 0.10, passes => 10, -as => analyze10 },
    analyze => { tolerance => 0.15, passes => 50, -as => analyze50 };

  my $value = analyze10($data);

The generator for that would look something like this:

  sub build_analyzer {
    my ($class, $name, $arg) = @_;

    return sub {
      my $data      = shift;
      my $tolerance = shift || $arg->{tolerance}; 
      my $passes    = shift || $arg->{passes}; 

      analyze($data, $tolerance, $passes);
    }
  }

Your module's user now has to do less work to benefit from it -- and remember,
you're often your own user!  Investing in customized subroutines is an
investment in future laziness.

This also avoids a common form of ugliness seen in many modules: package-level
configuration.  That is, you might have seen something like the above
implemented like so:

  use Data::Analyze qw(analyze);
  $Data::Analyze::default_tolerance = 0.10;
  $Data::Analyze::default_passes    = 10;

This might save time, until you have multiple modules using Data::Analyze.
Because there is only one global configuration, they step on each other's toes
and your code begins to have mysterious errors.

Generators can also allow you to export class methods to be called as
subroutines:

  package Data::Methodical;
  use Sub::Exporter -setup => { exports => { some_method => \&_curry_class } };

  sub _curry_class {
    my ($class, $name) = @_;
    sub { $class->$name(@_); };
  }

Because of the way that exporters and Sub::Exporter work, any package that
inherits from Data::Methodical can inherit its exporter and override its
C<some_method>.  If a user imports C<some_method> from that package, he'll
receive a subroutine that calls the method on the subclass, rather than on
Data::Methodical itself.

=head2 Other Customizations

Building custom routines with generators isn't the only way that Sub::Exporters
allows the importing code to refine its use of the exported routines.  They may
also be renamed to avoid naming collisions.

Consider the following code:

  # this program determines to which circle of Hell you will be condemned
  use Morality qw(sin virtue); # for calculating viciousness
  use Math::Trig qw(:all);     # for dealing with circles

The programmer has inadvertantly imported two C<sin> routines.  The solution,
in Exporter.pm-based modules, would be to import only one and then call the
other by its fully-qualified name.  Alternately, the importer could write a
routine that did so, or could mess about with typeglobs.

How much easier to write:

  # this program determines to which circle of Hell you will be condemned
  use Morality qw(virtue), sin => { -as => 'offense' };
  use Math::Trig -all => { -prefix => 'trig_' };

and to have at one's disposal C<offense> and C<trig_sin> -- not to mention
C<trig_cos> and C<trig_tan>.

=head1 EXPORTER CONFIGURATION

You can configure an exporter for your package by using Sub::Exporter like so:

  package Tools;
  use Sub::Exporter
    -setup => { exports => [ qw(function1 function2 function3) ] };

This is the simplest way to use the exporter, and is basically equivalent to
this:

  package Tools;
  use base qw(Exporter);
  our @EXPORT_OK = qw(function1 function2 function2);

Any basic use of Sub::Exporter will look like this:

  package Tools;
  use Sub::Exporter -setup => \%config;

The following keys are valid in C<%config>:

  exports - a list of routines to provide for exporting; each routine may be
            followed by generator
  groups  - a list of groups to provide for exporting; each must be followed by
            a list of exports, possibly with arguments for each export
  collectors - a list of names into which values are collected for use in
               routine generation; each name may be followed by a validator

=head2 Export Configuration

The C<exports> list may be provided as an array reference or a hash reference.
The list is processed in such a way that the following are equivalent:

  { exports => [ qw(foo bar baz), quux => \&quux_generator ] }

  { exports =>
    { foo => undef, bar => undef, baz => undef, quux => \&quux_generator } }

Generators are coderefs that return coderefs.  They are called with four
parameters:

  $class - the class whose exporter has been called (the exporting class)
  $name  - the name of the export for which the routine is being build
 \%arg   - the arguments passed for this export
 \%coll  - the collections for this import

Given the configuration in the L</SYNOPSIS>, the following C<use> statement:

  use Text::Tweaker
    reformat => { -as => 'make_narrow', width => 33 },
    defaults => { eol => 'CR' };

would result in the following call to C<&build_reformatter>:

  my $code = build_reformatter(
    'Text::Tweaker',
    'reformat',
    { width => 33 }, # note that -as is not passed in
    { defaults => { eol => 'CR' } },
  );

The returned coderef (C<$code>) would then be installed as C<make_narrow> in the
calling package.

=head2 Group Configuration

The C<groups> list can be passed in the same forms as C<exports>.  Groups must
have values to be meaningful, which may either list exports that make up the
group (optionally with arguments) or may provide a way to build the group.

The simpler case is the first: a group definition is a list of exports.  Here's
the example that could go in exporter in the L</SYNOPSIS>.

  groups  => {
    default    => [ qw(reformat) ],
    shorteners => [ qw(squish trim) ],
    email_safe => [
      'indent',
      reformat => { -as => 'email_format', width => 72 }
    ],
  },

Groups are imported by specifying their name prefixed be either a dash or a
colon.  This line of code would import the C<shorteners> group:

  use Text::Tweaker qw(-shorteners);

Arguments passed to a group when importing are merged into the groups options
and passed to any relevant generators.  Groups can contain other groups, but
looping group structures are ignored.

The other possible value for a group definition, a coderef, allows one
generator to build several exportable routines simultaneously.  This is useful
when many routines must share enclosed lexical variables.  The coderef must
return a hash reference.  The keys will be used as export names and the values
are the subs that will be exported.

This example shows a simple use of the group generator.

  package Data::Crypto;
  use Sub::Exporter -setup => { groups => { cipher => \&build_cipher_group } };

  sub build_cipher_group {
    my ($class, $group, $arg) = @_;
    my ($encode, $decode) = build_codec($arg->{secret});
    return { cipher => $encode, decipher => $decode };
  }

The C<cipher> and C<decipher> routines are built in a group because they are
built together by code which encloses their secret in their environment.

=head3 Default Groups

If a module that uses Sub::Exporter is C<use>d with no arguments, it will try
to export the group named C<default>.  If that group has not been specifically
configured, it will be empty, and nothing will happen.

Another group is also created if not defined: C<all>.  The C<all> group
contains all the exports from the exports list.

=head2 Collector Configuration

The C<collectors> entry in the exporter configuration gives names which, when
found in the import call, have their values collected and passed to every
generator.

For example, the C<build_analyzer> generator that we saw above could be
rewritten as:

 sub build_analyzer {
   my ($class, $name, $arg, $col) = @_;

   return sub {
     my $data      = shift;
     my $tolerance = shift || $arg->{tolerance} || $col->{defaults}{tolerance}; 
     my $passes    = shift || $arg->{passes}    || $col->{defaults}{passes}; 

     analyze($data, $tolerance, $passes);
   }
 }

That would allow the import to specify global defaults for his imports:

  use Data::Analyze
    'analyze',
    analyze  => { tolerance => 0.10, -as => analyze10 },
    analyze  => { tolerance => 0.15, passes => 50, -as => analyze50 },
    defaults => { passes => 10 };

  my $A = analyze10($data);     # equivalent to analyze($data, 0.10, 10);
  my $C = analyze50($data);     # equivalent to analyze($data, 0.15, 10);
  my $B = analyze($data, 0.20); # equivalent to analyze($data, 0.20, 10);

If values are provided in the C<collectors> list during exporter setup, they
must be code references, and are used to validate the importer's values.  The
validator is called when the collection is found, and if it returns false, an
exception is thrown.  We could ensure that no one tries to set a global data
default easily:

  collectors => { defaults => sub { return (exists $_[0]->{data}) ? 0 : 1 } }

Collector coderefs can also be used as hooks to perform arbitrary actions
before anything is exported.  B<Warning!>  This feature is experimental and may
change in the future.

When the coderef is called, it is actually passed these values:

  $value - the value given for the collector in the args to import
  $name  - the name of the collector
 \%config      - the exporter configuration
 \@import_args - the arguments passed to the exporter, sans collections
  $class - the package on which the importer was called
  $into  - the package into which exports will be exported

=head1 CALLING THE EXPORTER

Arguments to the exporter (that is, the arguments after the module name in a
C<use> statement) are parsed as follows:

First, the collectors gather any collections found in the arguments.  Any
reference type may be given as the value for a collector.  For each collection
given in the arguments, its validator (if any) is called.  

Next, groups are expanded.  If the group is implemented by a group generator,
the generator is called.  There are two special arguments which, if given to a
group, have special meaning:

  -prefix - a string to prepend to any export imported from this group
  -suffix - a string to append to any export imported from this group

Finally, individual export generators are called and all subs, generated or
otherwise, are installed in the calling package.  There is only one special
argument for export generators:

  -as     - where to install the exported sub

Normally, C<-as> will contain an alternate name for the routine.  It may,
however, contain a reference to a scalar.  If that is the case, a reference the
generated routine will be placed in the scalar referenced by C<-as>.  It will
not be installed into the calling package.

=head2 Special Exporter Arguments

The generated exporter accept some special options, which may be passed as the
first argument, in a hashref.

These options are:

  into_level - how far up the caller stack to look for a target (default 0)
  into       - an explicit target (package) into which to export routines

Providing both C<into_level> and C<into> will cause an exception to be
thrown.

=cut

# Given a potential import name, this returns the group name -- if it's got a
# group prefix.
sub _group_name {
  my ($name) = @_;

  return if (index '-:', (substr $name, 0, 1)) == -1;
  return substr $name, 1;
}

# \@groups is a canonicalized opt list of exports and groups this returns
# another canonicalized opt list with groups replaced with relevant exports.
# \%seen is groups we've already expanded and can ignore.
# \%merge is merged options from the group we're descending through.
sub _expand_groups {
  my ($class, $config, $groups, $collection, $seen, $merge) = @_;
  $seen  ||= {};
  $merge ||= {};
  my @groups = @$groups;

  for my $i (reverse 0 .. $#groups) {
    if (my $group_name = _group_name($groups[$i][0])) {
      my $seen = { %$seen }; # faux-dynamic scoping

      splice @groups, $i, 1,
        _expand_group($class, $config, $groups[$i], $collection, $seen, $merge);
    } else {
      # there's nothing to munge in this export's args
      next unless my %merge = %$merge;

      # we have things to merge in; do so
      my $prefix = (delete $merge{-prefix}) || '';
      my $suffix = (delete $merge{-suffix}) || '';

      if (Params::Util::_CALLABLE($groups[$i][1])) {
        # this entry was build by a group generator
        $groups[$i][0] = $prefix . $groups[$i][0] . $suffix;
      } else {
        my $as
          = ref $groups[$i][1]{-as} ? $groups[$i][1]{-as}
          :     $groups[$i][1]{-as} ? $prefix . $groups[$i][1]{-as} . $suffix
          :                           $prefix . $groups[$i][0]      . $suffix;

        $groups[$i][1] = { %{ $groups[$i][1] }, %merge, -as => $as };
      }
    }
  }

  return \@groups;
}

# \@group is a name/value pair from an opt list.
sub _expand_group {
  my ($class, $config, $group, $collection, $seen, $merge) = @_;
  $merge ||= {};

  my ($group_name, $group_arg) = @$group;
  $group_name = _group_name($group_name);

  Carp::croak qq(group "$group_name" is not exported by the $class module)
    unless exists $config->{groups}{$group_name};

  return if $seen->{$group_name}++;

  if (ref $group_arg) {
    my $prefix = (delete $merge->{-prefix}||'') . ($group_arg->{-prefix}||'');
    my $suffix = ($group_arg->{-suffix}||'') . (delete $merge->{-suffix}||'');
    $merge = {
      %$merge,
      %$group_arg,
      ($prefix ? (-prefix => $prefix) : ()),
      ($suffix ? (-suffix => $suffix) : ()),
    };
  }

  my $exports = $config->{groups}{$group_name};

  if (Params::Util::_CALLABLE($exports)) {
    my $group = $exports->($class, $group_name, $group_arg, $collection);
    Carp::croak qq(group generator "$group_name" did not return a hashref)
      if ref $group ne 'HASH';
    my $stuff = [ map { [ $_ => $group->{$_} ] } keys %$group ];
    return @{
      _expand_groups($class, $config, $stuff, $collection, $seen, $merge)
    };
  } else {
    $exports
      = Data::OptList::canonicalize_opt_list($exports, "$group_name exports");

    return @{
      _expand_groups($class, $config, $exports, $collection, $seen, $merge)
    };
  }
}

# Given a config and pre-canonicalized importer args, remove collections from
# the args and return them.
sub _collect_collections {
  my ($config, $import_args, $class, $into) = @_;
  my %collection;

  my @collections
    = map  { splice @$import_args, $_, 1 }
      grep { exists $config->{collectors}{ $import_args->[$_][0] } }
      reverse 0 .. $#$import_args;

  my %seen;
  for my $collection (@collections) {
    my ($name, $value) = @$collection;

    Carp::croak "collection $name provided multiple times in import"
      if $seen{ $name }++;

    $collection{ $name } = $value;

    if (ref(my $hook = $config->{collectors}{$name})) {
      my $arg = {
        name        => $name,
        config      => $config,
        import_args => $import_args,
        class       => $class,
        into        => $into,
      };

      Carp::croak "collection $name failed validation"
        unless $hook->($value, $arg);
    }
  }

  return \%collection;
}

=head1 SUBROUTINES

=head2 setup_exporter

This routine builds and installs an C<import> routine.  It is called with one
argument, a hashref containing the exporter configuration.  Using this, it
builds an exporter and installs it into the calling package with the name
"import."  In addition to the normal exporter configuration, a few named
arguments may be passed in the hashref:

  into       - into what package should the exporter be installed
  into_level - into what level up the stack should the exporter be installed
  as         - what name should the installed exporter be given

By default the exporter is installed with the name C<import> into the immediate
caller of C<setup_exporter>.  In other words, if your package calls
C<setup_exporter> without providing any of the three above arguments, it will
have an C<import> routine installed.

Providing both C<into> and C<into_level> will cause an exception to be thrown.

The exporter is built by C<L</build_exporter>>.

=cut

# \%special is for experimental options that may or may not be kept around and,
# probably, moved to \%config.  These are also passed along to build_exporter.

sub setup_exporter {
  my ($config)  = @_;

  Carp::croak q(into and into_level may not both be supplied to exporter)
    if exists $config->{into} and exists $config->{into_level};

  my $as   = delete $config->{as}   || 'import';
  my $into
    = exists $config->{into}       ? delete $config->{into}
    : exists $config->{into_level} ? caller(delete $config->{into_level})
    :                                caller(0);

  my $import = build_exporter($config);

  Sub::Install::reinstall_sub({
    code => $import,
    into => $into,
    as   => $as,
  });
}

=head2 build_exporter

Given a standard exporter configuration, this routine builds and returns an
exporter -- that is, a subroutine that can be installed as a class method to
perform exporting on request.

Usually, this method is called by C<L</setup_exporter>>, which then installs
the exporter as a package's import routine.

=cut

sub _key_intersection {
  my ($x, $y) = @_;
  my %seen = map { $_ => 1 } keys %$x;
  my @names = grep { $seen{$_} } keys %$y;
}

# Given the config passed to setup_exporter, which contains sugary opt list
# data, rewrite the opt lists into hashes, catch a few kinds of invalid
# configurations, and set up defaults.  Since the config is a reference, it's
# rewritten in place.
my %valid_config_key;
BEGIN { %valid_config_key = map {$_=>1} qw(exports exporter groups collectors) }

sub _rewrite_build_config {
  my ($config) = @_;

  if (my @keys = grep { not exists $valid_config_key{$_} } keys %$config) {
    Carp::croak "unknown options (@keys) passed to Sub::Exporter";
  }

  $config->{$_} = Data::OptList::expand_opt_list($config->{$_}, $_, 'CODE')
    for qw(exports collectors);

  if (my @names = _key_intersection(@$config{qw(exports collectors)})) {
    Carp::croak "names (@names) used in both collections and exports";
  }

  $config->{groups}
    = Data::OptList::expand_opt_list(
      $config->{groups}, 'groups', [ 'HASH', 'CODE', 'ARRAY' ]
    );

  # by default, export nothing
  $config->{groups}{default} ||= [];

  # by default, build an all-inclusive 'all' group
  $config->{groups}{all} ||= [ keys %{ $config->{exports} } ];
}

sub build_exporter {
  my ($config) = @_;

  _rewrite_build_config($config);

  my $import = sub {
    my ($class) = shift;

    # XXX: clean this up -- rjbs, 2006-03-16
    my $special = (ref $_[0]) ? shift(@_) : {};
    Carp::croak q(into and into_level may not both be supplied to exporter)
      if exists $special->{into} and exists $special->{into_level};

    my $into
      = defined $special->{into}       ? delete $special->{into}
      : defined $special->{into_level} ? caller(delete $special->{into_level})
      :                                  caller(0);

    my $export = delete $special->{exporter}
              || $config->{exporter}
              || \&default_exporter;

    # this builds a AOA, where the inner arrays are [ name => value_ref ]
    my $import_args = Data::OptList::canonicalize_opt_list([ @_ ]);

    my $collection = _collect_collections($config, $import_args, $class, $into);

    $import_args = [ [ -default => 1 ] ] unless @$import_args;
    my $to_import = _expand_groups($class, $config, $import_args, $collection);

    # now, finally $import_arg is really the "to do" list
    for (@$to_import) {
      _do_import($class, @$_, $collection, $config, $into, $export);
    }
  };

  return $import;
}

sub _do_import {
  my ($class, $name, $arg, $collection, $config, $into, $export) = @_;

  my ($generator, $as);

  if ($arg and Params::Util::_CALLABLE($arg)) {
    # This is the case when a group generator has inserted name/code pairs.
    $generator = sub { $arg };
    $as = $name;
  } else {
    $arg = { $arg ? %$arg : () };

    Carp::croak qq("$name" is not exported by the $class module)
      unless (exists $config->{exports}{$name});

    $generator = $config->{exports}{$name};

    $as = exists $arg->{-as} ? (delete $arg->{-as}) : $name;
  }

  $export->($class, $generator, $name, $arg, $collection, $as, $into);
}

# XXX: Consider implementing a _export_args routine that takes the arguments to
# _export and returns a hash of named params.  This lets other people write
# exporters without tying me down to one set of @_ contents.  Maybe that's
# premature guarantee, though, unless I guarantee that @_ will never get
# /smaller/.

=head2 default_exporter

This is Sub::Exporter's default exporter.  It does what Sub::Exporter promises:
it calls generators with the three normal arguments, then installs the code
into the target package.

B<Warning!>  Its interface isn't really stable yet, so don't rely on it.  It's
only named here so that you can pass it in to the exporter builder.  It will
have a stable interface in the future so that it may be more easily replaced.

=cut

sub default_exporter {
  my ($class, $generator, $name, $arg, $collection, $as, $into) = @_;
  _install(
    _generate($class, $generator, $name, $arg, $collection),
    $into,
    $as,
  );
}

## Cute idea, possibly for future use: also supply an "unimport" for:
## no Module::Whatever qw(arg arg arg);
# sub _unexport {
#   my (undef, undef, undef, undef, undef, $as, $into) = @_;
# 
#   if (ref $as eq 'SCALAR') {
#     undef $$as;
#   } elsif (ref $as) {
#     Carp::croak "invalid reference type for $as: " . ref $as;
#   } else {
#     no strict 'refs';
#     delete &{$into . '::' . $as};
#   }
# }

sub _generate {
  my ($class, $generator, $name, $arg, $collection) = @_;

  my $code = $generator
           ? $generator->($class, $name, $arg, $collection)
           : $class->can($name); 
}

sub _install {
  my ($code, $into, $as) = @_;
  # Allow as isa ARRAY to push onto an array?
  # Allow into isa HASH to install name=>code into hash?

  if (ref $as eq 'SCALAR') {
    $$as = $code;
  } elsif (ref $as) {
    Carp::croak "invalid reference type for $as: " . ref $as;
  } else {
    Sub::Install::reinstall_sub({ code => $code, into => $into, as => $as });
  }
}

=head1 EXPORTS

Sub::Exporter also offers its own exports: the C<setup_exporter> and
C<build_exporter> routines described above.  It also provides a special "setup"
group, which will setup an exporter using the parameters passed to it.

=cut

setup_exporter({
  exports => [
    qw(setup_exporter build_exporter),
    _import => sub { splice @_, 0, 2; build_exporter(@_) },
  ],
  groups  => {
    all   => [ qw(setup_exporter build_export) ],
  },
  collectors => { -setup => \&_setup },
});

sub _setup {
  my ($value, $arg) = @_;

  if (ref $value eq 'HASH') {
    push @{ $arg->{import_args} }, [ _import => { -as => 'import', %$value } ];
    return 1;
  } elsif (ref $value eq 'ARRAY') {
    push @{ $arg->{import_args} },
      [ _import => { -as => 'import', exports => $value } ];
    return 1;
  }
  return;
}

=head1 COMPARISONS

There are a whole mess of exporters on the CPAN.  The features included in
Sub::Exporter set it apart from any existing Exporter.  Here's a summary of
some other exporters and how they compare.

=over

=item * L<Exporter> and co.

This is the standard Perl exporter.  Its interface is a little clunky, but it's
fast and ubiquitous.  It can do some things that Sub::Exporter can't:  it can
export things other than routines, it can import "everything in this group
except this symbol," and some other more esoteric things.  These features seem
to go nearly entirely unused.

It always exports things exactly as they appear in the exporting module; it
can't rename or customize routines.  Its groups ("tags") can't be nested.

L<Exporter::Lite> is a whole lot like Exporter, but it does significantly less:
it supports exporting symbols, but not groups, pattern matching, or negation.

The fact that Sub::Exporter can't export symbols other than subroutines is
a good idea, not a missing feature.

For simple uses, setting up Sub::Exporter is about as easy as Exporter.  For
complex uses, Sub::Exporter makes hard things possible, which would not be
possible with Exporter. 

When using a module that uses Sub::Exporter, users familiar with Exporter will
probably see difference in the basics.  These two lines do about the same thing
in whether the exporting module uses Exporter or Sub::Exporter.

  use Some::Module qw(foo bar baz);
  use Some::Module qw(foo :bar baz);

The definition for exporting in Exporter.pm might look like this:

  package Some::Module;
  use base qw(Exporter);
  our @EXPORT_OK   = qw(foo bar baz quux);
  our %EXPORT_TAGS = (bar => [ qw(bar baz) ]);

Using Sub::Exporter, it would look like this:

  package Some::Module;
  use Sub::Exporter -setup => {
    exports => [ qw(foo bar baz quux) ],
    groups  => { bar => [ qw(bar baz) ]}
  };

Sub::Exporter respects inheritance, so that a package may export inherited
routines, and will export the most inherited version.  Exporting methods
without currying away the invocant is a bad idea, but Sub::Exporter allows you
to do just that -- and anyway, there are other uses for this feature, like
packages of exported subroutines which use inheritance specifically to allow
more specialized, but similar, packages.

L<Exporter::Easy> provides a wrapper around the standard Exporter.  It makes it
simpler to build groups, but doesn't provide any more functionality.  Because
it is a front-end to Exporter, it will store your exporter's configuration in
global package variables.

=item * Attribute-Based Exporters

Some exporters use attributes to mark variables to export.  L<Exporter::Simple>
supports exporting any kind of symbol, and supports groups.  Using a module
like Exporter or Sub::Exporter, it's easy to look at one place and see what is
exported, but it's impossible to look at a variable definition and see whether
it is exported by that alone.  Exporter::Simple makes this trade in reverse:
each variable's declaration includes its export definition, but there is no one
place to look to find a manifest of exports.

More importantly, Exporter::Simple does not add any new features to those of
Exporter.  In fact, like Exporter::Easy, it is just a front-end to Exporter, so
it ends up storing its configuration in global package variables.  (This means
that there is one place to look for your exporter's manifest, actually.  You
can inspect the C<@EXPORT> package variables, and other related package
variables, at runtime.)

L<Perl6::Export> isn't actually attribute based, but looks similar.  Its syntax
is borrowed from Perl 6, and implemented by a source filter.  It is a prototype
of an interface that is still being designed.  It should probably be avoided
for production work.  On the other hand, L<Perl6::Export::Attrs> implements
Perl 6-like exporting, but translates it into Perl 5 by providing attributes.

=item * Other Exporters

L<Exporter::Renaming> wraps the standard Exporter to allow it to export symbols
with changed names.

L<Class::Exporter> performs a special kind of routine generation, giving each
importing package an instance of your class, and then exporting the instance's
methods as normal routines.  (Sub::Exporter, of course, can easily emulate this
behavior, as shown above.)

L<Exporter::Tidy> implements a form of renaming (using its C<_map> argument)
and of prefixing, and implements groups.  It also avoids using package
variables for its configuration.

=back

=head1 TODO

=cut

=over

=item * write a set of longer, more demonstrative examples

=item * solidify the "custom exporter" interface (see C<&default_exporter>)

=item * add an "always" group

=back

=head1 AUTHOR

Ricardo SIGNES, C<< <rjbs@cpan.org> >>

=head1 THANKS

Hans Dieter Pearcey provided helpful advice while I was writing Sub::Exporter.
Ian Langworth and Shawn Sorichetti asked some good questions and hepled me
improve my documentation quite a bit.  Yuval Kogman helped me find a bunch of
little problems.

Thanks, guys! 

=head1 BUGS

Please report any bugs or feature requests to C<bug-sub-exporter@rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org>. I will be notified, and
then you'll automatically be notified of progress on your bug as I make
changes.

=head1 COPYRIGHT

Copyright 2006 Ricardo SIGNES.  This program is free software;  you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

"jn8:32"; # <-- magic true value
