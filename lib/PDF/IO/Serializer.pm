use v6;

class PDF::IO::Serializer {

    use PDF::DAO;
    use PDF::DAO::Stream;
    use PDF::DAO::Util :to-ast;

    has UInt $.size is rw = 1;      #| first free object number
    has Pair  @!objects;            #| renumbered objects
    has Array %!objects-idx{Any};   #| unique objects index
    has UInt %.ref-count{Any};
    has Bool $.renumber is rw = True;
    has Str $!type;                 #| 'FDF', 'PDF', .. others?
    has $.reader;

    method type { $!type //= $.reader.?type // 'PDF' }

    #| Reference count hashes. Could be derivate class of PDF::DAO::Dict or PDF::DAO::Stream.
    multi method analyse(Hash $dict) {
        unless %!ref-count{$dict}++ { # already encountered
            $.analyse($dict{$_}) for $dict.keys.sort
        }
    }

    #| Reference count arrays. Could be derivate class of PDF::DAO::Array
    multi method analyse(Array $array) {
        unless %!ref-count{$array}++ { # already encountered
            $.analyse($array[$_]) for $array.keys
        }
    }

    #| we don't reference count anything else at the moment.
    multi method analyse($) is default { }

    my subset DictIndObj of Pair where {.key eq 'ind-obj'
					    && .value[2] ~~ Pair
					    && .value[2].key eq 'dict'}
    
    #| remove and return the root object (trailer dictionary)
    method !get-root(@objects) {
	my DictIndObj \root-ind-obj = @objects.shift; # first object is trailer dict
	root-ind-obj.value[2]<dict>;
    }

    #| Discard Linearization aka "Fast Web View"
    method !discard-linearization(@objects) {
    	if @objects && @objects[0] ~~ DictIndObj {
	    my \first-ind-obj = @objects[0].value[2];
	    @objects.shift
		if first-ind-obj<dict><Linearized>:exists;
	}
    }

    proto method body(|c --> Array) {*}

    #| rebuild document body from root
    multi method body( PDF::DAO $trailer!, Bool:_ :$*compress, UInt :$!size = 1) {

	temp $trailer.obj-num = 0;
	temp $trailer.gen-num = 0;

        %!ref-count = ();
	@!objects = ();
        $.analyse( $trailer );
        $.freeze( $trailer, :indirect);
	my %dict = self!get-root(@!objects);

        %dict<Size> = :int($.size)
	    unless $.type eq 'FDF';

        [ { :@!objects, :trailer{ :%dict } }, ];
    }

    #| prepare a set of objects for an incremental update. Only return indirect objects:
    #| - objects that have been fetched and updated, and
    #| - the trailer dictionary (returned as first object)
    multi method body( Bool :$updates! where .so, :$*compress ) {
        # only renumber new objects, starting from the highest input number + 1 (size)
        $.size = $.reader.size;
        my \prev = $.reader.prev;

        # disable auto-deref to keep all analysis and freeze stages lazy. if it hasn't been
        # loaded, it hasn't been updated
        temp $.reader.auto-deref = False;

        # preserve existing object numbers. objects need to overwritten using the same
        # object and generation numbers
        temp $.renumber = False;
        %!ref-count = ();
	@!objects = ();
	my \trailer = $.reader.trailer;

	temp trailer.obj-num = 0;
	temp trailer.gen-num = 0;

        my @updated-objects = $.reader.get-updates.list;

        for @updated-objects -> \object {
            # reference count new objects
            $.analyse( object );
        }

	for @updated-objects -> \object {
	    $.freeze( object, :indirect )
	}

	my %dict = self!get-root(@!objects);

        %dict<Prev> = :int(prev);
        %dict<Size> = :int($.size);

        [ { :@!objects, :trailer{ :%dict } }, ]
    }

    #| return objects without renumbering existing objects. requires a PDF reader
    multi method body( Bool:_ :$*compress ) is default {
        my @objects = $.reader.get-objects;

	my %dict = self!get-root(@objects);
	self!discard-linearization(@objects);

        %dict<Prev>:delete;
        %dict<Size> = :int($.reader.size)
            unless $.type eq 'FDF';

        [ { :@objects, :trailer{ :%dict } }, ]
    }

    #| construct a reverse index that unique maps unique $objects,
    #| to an object-number and generation-number. 
    method !index-object( Pair $ind-obj! is rw, :$object!) {
        my Int $obj-num = $object.obj-num 
	    if $object.can('obj-num')
	    && (! $.reader || $object.reader === $.reader);
        my UInt $gen-num;
	constant TrailerObjNum = 0;

        if $obj-num.defined && (($obj-num > 0 && ! $.renumber) || $obj-num == TrailerObjNum) {
            # keep original object number
            $gen-num = $object.gen-num;
        }
        else {
            # renumber
            $obj-num = $!size++;
            $gen-num = 0;
        }

        @!objects.push: (:ind-obj[ $obj-num, $gen-num, $ind-obj]);
        my $ind-ref = [ $obj-num, $gen-num ];
        %!objects-idx{$object} = $ind-ref;
        :$ind-ref;
    }

    method !freeze-dict( Hash \dict) {
        %( dict.keys.sort.map: { $_ => $.freeze( dict{$_} ) } );
    }

    method !freeze-array( Array \array) {
        [ array.keys.map: { $.freeze( array[$_] ) } ];
    }

    #| should this be serialized as an indirect object?
    multi method is-indirect($ --> Bool) {*}

    #| streams always need to be indirect objects
    multi method is-indirect(PDF::DAO::Stream $)                    {True}

    #| multiply referenced objects need to be indirect
    multi method is-indirect($ where %!ref-count{$_} > 1)           {True}

    #| typed objects should be indirect, e.g. << /Type /Catalog .... >>
    multi method is-indirect(Hash $ where {.<Type>:exists})         {True}

    #| presumably sourced as an indirect object, so output as such.
    multi method is-indirect($ where {.can('obj-num') && .obj-num}) {True}

    #| allow anything else to inline
    multi method is-indirect($) is default                          {False}

    #| prepare an object for output.
    #| - if already encountered, return an indirect reference
    #| - produce an AST from the object content
    #| - determine if the object is indirect, if so index it,
    #|   generating or reusing the object-number in the process.
    proto method freeze(|) {*}

    #| handles PDF::DAO::Dict, PDF::DAO::Stream, (plain) Hash
    multi method freeze( Hash $object!, Bool :$indirect) {

        with %!objects-idx{$object} -> $ind-ref {
            # already an indirect object
            :$ind-ref
        }
        else {
            my $stream;
	    if $object.isa(PDF::DAO::Stream) {
	        with $*compress {
		    $_ ?? $object.compress !! $object.uncompress
	        }
	        $stream = $object.encoded;
	    }

            my $ind-obj;
            my $slot;
	    my $dict;

            with $stream {
	        my $encoded = .Str;
                $ind-obj = :stream{
                    :$dict,
                    :$encoded,
                };
                $slot := $ind-obj.value<dict>;
            }
            else {
                $ind-obj = :$dict;
                $slot := $ind-obj.value;
            }

            # register prior to traversing the object. in case there are cyclical references
            my \ret = $indirect || $.is-indirect( $object )
              ?? self!index-object($ind-obj, :$object )
              !! $ind-obj;

            $slot = self!freeze-dict($object);

            ret;
        }
    }

    #| handles PDF::DAO::Array, (plain) Array
    multi method freeze( Array $object!, Bool :$indirect ) {

        with %!objects-idx{$object} -> $ind-ref {
            # already an indirect object
            :$ind-ref
        }
        else {
	    my $array;

            my $ind-obj = :$array;
            my $slot := $ind-obj.value;

            # register prior to traversing the object. in case there are cyclical references
            my \ret = $indirect || $.is-indirect( $object )
                ?? self!index-object($ind-obj, :$object )
                !! $ind-obj;

            $slot = self!freeze-array($object);

            ret;
        }
    }

    #| handles other basic types
    multi method freeze($other) is default {
	to-ast $other
    }

    #| do a full save to the named file
    method ast(
	PDF::DAO $trailer!,
	Numeric :$version=1.3,
	Str     :$!type,     #| e.g. 'PDF', 'FDF;
	Bool    :$compress,
	        :$crypt,
        ) {
	$!type //= $.reader.?type;
	$!type //= (($trailer<Root>:exists) && ($trailer<Root><FDF>:exists)
		    ?? 'FDF'
		    !! 'PDF');
        my Array $body = self.body($trailer, :$compress );
	.crypt-ast('body', $body, :mode<encrypt>)
	    with $crypt;
        :pdf{ :header{ :$!type, :$version }, :$body };
    }
}