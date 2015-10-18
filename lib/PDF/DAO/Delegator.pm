use v6;

class PDF::DAO::Delegator {

    use PDF::DAO;
    use PDF::DAO::Util :from-ast;

    use PDF::DAO::Array;
    use PDF::DAO::Tie::Array;

    use PDF::DAO::Dict;
    use PDF::DAO::Tie::Hash;

    multi method coerce( $obj, $role where {$obj ~~ $role}) {
	# already does it
	$obj
    }

    multi method coerce( PDF::DAO::Dict $obj, PDF::DAO::Tie::Hash $role) {
	$obj does $role; $obj.?tie-init;
    }

    multi method coerce( PDF::DAO::Array $obj, PDF::DAO::Tie::Array $role) {
	$obj does $role; $obj.?tie-init;
    }

    # adds the DateTime 'object' rw accessor
    use PDF::DAO::DateString;
    multi method coerce( Str $obj is rw, PDF::DAO::DateString $class, |c) {
	$obj = $class.new( $obj, |c );
    }
    multi method coerce( DateTime $obj is rw, DateTime $class where PDF::DAO, |c) {
	$obj = $class.new( $obj, |c );
    }
    use PDF::DAO::TextString;
    multi method coerce( Str $obj is rw, PDF::DAO::TextString $class, |c) {
	$obj = $class.new( :value($obj), |c );
    }

    multi method coerce( $obj, $role) is default {
	warn "unable to coerce object $obj of type {$obj.WHAT.gist} to role {$role.WHAT.gist}"
    }

    method class-paths { <PDF::DAO::Type> }

    our %handler;
    method handler {%handler}

    method install-delegate( Str $subclass, $class-def ) is rw {
        %handler{$subclass} = $class-def;
    }

    multi method find-delegate( Str $subclass! where { %handler{$_}:exists } ) {
        %handler{$subclass}
    }

    multi method find-delegate( Str $subclass!, :$fallback! ) is default {

	my $handler-class = $fallback;

	for self.class-paths -> $class-path {
	    try {
		try { require ::($class-path)::($subclass) };
		$handler-class = ::($class-path)::($subclass);
		last;
	    };
	}

        self.install-delegate( $subclass, $handler-class );
    }

    multi method delegate( Hash :$dict! where {$dict<Type>:exists}, :$fallback) {
	my $subclass = from-ast($dict<Type>);
	my $subtype = from-ast($dict<Subtype> // $dict<S>);
	$subclass ~= '::' ~ $subtype if $subtype.defined;
	my $delegate = $.find-delegate( $subclass, :$fallback );
	$delegate;
    }

    multi method delegate( :$fallback! ) is default {
	$fallback;
    }
}