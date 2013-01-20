/** ファイルを UTF-32 で一字ずつ読み込み。
 * Version:      0.004(dmd2.061)
 * Date:         2013-Jan-21 00:02:00
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.compo.util.sequential_file;

import std.array, std.ascii, std.bitmanip, std.conv, std.stdio, std.utf;
import sworks.compo.util.cached_buffer;
version( Windows ) import sworks.compo.win32.sjis; // std.stdio.File が日本語ファイル名未対応の為

enum ENCODING : ubyte
{
	NULL    = 0x00,
	UTF8    = 0x10,
	UTF16LE = 0x21,
	UTF16BE = 0x22,
	UTF32LE = 0x31,
	UTF32BE = 0x32,
	SJIS    = 0x40, // -version=use_MultiByteToWideChar か -version=use_iconv で対応

	ENDIAN_MASK   = 0x0f,
	STANDARD_MASK = 0xf0,
	NO_ENDIAN     = 0x00,
	LITTLE_ENDIAN = 0x01,
	BIG_ENDIAN    = 0x02,
}

// c の先頭に BOM があればそれを取り除き、その ENCODING を返す。
// BOM がなければ ENCODING.NULL を返す。
ENCODING strip_bom( TICache!ubyte c )
{
	assert( null !is c );
	enum UTF8    = [ ENCODING.UTF8, 0xef, 0xbb, 0xbf ];
	enum UTF16LE = [ ENCODING.UTF16LE, 0xff, 0xfe ];
	enum UTF16BE = [ ENCODING.UTF16BE, 0xfe, 0xff ];
	enum UTF32LE = [ ENCODING.UTF32LE, 0xff, 0xfe, 0x00, 0x00 ];
	enum UTF32BE = [ ENCODING.UTF32BE, 0x00, 0x00, 0xfe, 0xff ];

	ENCODING e = ENCODING.NULL;

	bool _check( alias TYPE )()
	{
		enum E = cast(ENCODING)TYPE[0];
		enum BOM = TYPE[ 1 .. $ ];
		if( BOM == c.peek( BOM.length ) ) { c.popFront( BOM.length ); e = E; return true; }
		else return false;
	}
	_check!UTF8 || _check!UTF16LE || _check!UTF16BE || _check!UTF32LE || _check!UTF32BE;

	return e;
}

// 改行コードの決定。二文字の改行コードの場合は最後の文字を返す。
private dchar decide_line_tail(T)( const(T)[] buf )
{
	for( size_t i = 0 ; i < buf.length ; i++ )
	{
		if     ( '\n' == buf[i] ) return '\n';
		else if( '\r' == buf[i] )
		{
			if( i+1 < buf.length && '\n' == buf[i+1] ) return '\n';
			else return '\r';
		}
	}
	return newline[ $-1 ];
}


// ファイルを一時ずつ UTF32 で読み込み。
// 行番号を保持する。
class SequentialBuffer : TICache!dchar
{
	private const string _filename;
	private TICache!dchar _cache;

	private immutable dchar _line_tail;
	private size_t _line;
	private bool _new_line;


	debug
	{
		debug private Benchmark delegate() _bmark_of_cache1;
		this( string filename, TICache!dchar c, Benchmark delegate() boc1 )
		{
			this( filename, c );
			this._bmark_of_cache1 = boc1;
		}
	}

	this( string filename, TICache!dchar c )
	{
		this._filename = filename;
		this._cache = c;
		this._line = 1;
		this._new_line = true;
		this._line_tail = decide_line_tail( c.peekBetter );
	}

	size_t size() @property const { return _cache.size; }
	dchar front() @property const { return _cache.front; }
	const(dchar)[] peek( size_t s ) { return _cache.peek( s ); }
	const(dchar)[] peekBetter() @property { return _cache.peekBetter; }
	dchar[] getBinary( dchar[] buf ){ return _cache.getBinary( buf ); }
	bool eof() @property const { return _cache.eof; }
	void close() @property { _cache.close; _line = 1; _new_line = true; }
	const(dchar)[] stack() @property const { return _cache.stack; }
	void flush() { return _cache.flush; }
	
	string filename() @property const { return _filename; }
	size_t line() @property const { return _line; }
	bool isNewLine() @property const { return _new_line; }

	dchar popFront( size_t s = 1 )
	{
		for( size_t i = 0 ; i < s ; i++ )
		{
			_new_line = ( _line_tail == _cache.front );
			if( _new_line ) _line++;
			_cache.popFront;
		}
		return _cache.front;
	}

	dchar push( size_t s = 1 )
	{
		for( size_t i = 0 ; i < s ; i++ )
		{
			_new_line = ( _line_tail == _cache.front );
			if( _new_line ) _line++;
			_cache.push;
		}
		return _cache.front;
	}

	dchar push( dchar c )
	{
		_new_line = ( _line_tail == c );
		if( _new_line ) _line++;
		return _cache.push( c );
	}

	debug Benchmark getBenchmark() @property const { return _cache.getBenchmark; }
	debug Benchmark getBenchmark1() @property const { return _bmark_of_cache1(); }
}

alias TWholeCache!dchar UTF32Buffer;
alias TICache!ubyte ICache1;
alias TCachedBuffer!ubyte Cache1;
alias TCachedBuffer!dchar UTF32File;

/*
 * ファイルを開き、BOM を読み込んで適当な SequentialFile のインスタンスを返す。
 * BOM が見つからなかった場合は引数 code に従うが、code が ENCODING.NULL の場合は UTF-8 と見なす。
 * 引数で指定した code と見つかった BOM とが一致しない場合は例外が投げられる。
 */
SequentialBuffer getSequentialBuffer( string filename, ENCODING def_enc = ENCODING.NULL
                                    , size_t cache_size = 1024 )
{
	File* f;
	version(Windows) f = new File( filename.toMBS.c, "rb" );
	else f = new File( filename, "rb" );

	auto cache1 = new Cache1( buf=>f.rawRead(buf).length, s=>f.seek( s, SEEK_CUR )
	                        , ()=>f.close, cache_size );
	auto enc = cache1.strip_bom;
	if     ( ENCODING.NULL == def_enc ) { if( ENCODING.NULL == enc ) enc = ENCODING.UTF8; }
	else if( ENCODING.NULL == enc ) enc = def_enc;
	else if( enc != def_enc )
		throw new Exception( def_enc.to!string ~ " モードが要求さましたが、ファイル \""
		                   ~ filename ~ "\" には、" ~ enc.to!string ~ " のBOMが見つかりました。" );

	UTF32File c2;
	void setC2( alias F, TYPE )()
	{
		c2 = new UTF32File( b=>F(cache1,b), null, ()=>cache1.close, cache_size >> (TYPE.sizeof>>1) );
	}
	if     ( ENCODING.UTF8 == enc ) setC2!( readUTF8, char);
	else if( ENCODING.UTF16LE == enc ) setC2!( readUTF16LE, wchar );
	else if( ENCODING.UTF16BE == enc ) setC2!( readUTF16BE, wchar );
	else if( ENCODING.UTF32LE == enc ) setC2!( readUTF32LE, dchar );
	else if( ENCODING.UTF32BE == enc ) setC2!( readUTF32BE, dchar );
	else if( ENCODING.SJIS == enc )
	{
		version     ( use_MultiByteToWideChar ) setC2!( readSJIS, jchar );
		else version( use_iconv )
		{
			auto toSJIS = new readSJIS;
			c2 = new UTF32File( b=>toSJIS(cache1,b), null, (){ cache1.close; toSJIS.close; }
			                  , cache_size );
		}
		else throw new Exception( "SHIFT-JIS のサポートには -version=use_MultiByteToWideChar か "
		                          "-version=use_iconv でコンパイルして下さい。" );
	}
	if( null is c2 ) throw new Exception( enc.to!string ~ " はサポートされていない文字コードです。" );

	debug return new SequentialBuffer( filename, c2, &cache1.getBenchmark );
	else return new SequentialBuffer( filename, c2 );
}

SequentialBuffer getSequentialBuffer( const(dchar)[] buf )
{
	return new SequentialBuffer( "DSTRING", new UTF32Buffer( buf ) );
}

SequentialBuffer getSequentialBuffer( string filename, const(dchar)[] buf )
{
	return new SequentialBuffer( filename, new UTF32Buffer( buf ) );
}

size_t readUTFx( ENCODING CODE, TCHAR)( ICache1 cache, dchar[] buf )
{
	auto buf1 = cache.peekBetter();
	if( buf.length * TCHAR.sizeof < buf1.length ) buf1 = buf1[ 0 .. buf.length * TCHAR.sizeof ];
	auto buf2 = cast(TCHAR[])buf1[ 0 .. buf1.length>>(TCHAR.sizeof>>1)<<(TCHAR.sizeof>>1) ];
	if( 0 == buf2.length ) return 0;

	version     ( LittleEndian )
		static if( CODE & ENCODING.BIG_ENDIAN ) foreach( ref o ; buf2 ) o = swapEndian( o );
	else version( BigEndian )
		static if( CODE & ENCODING.LITTLE_ENDIAN ) foreach( ref o ; buf2 ) o = swapEndian( o );
	else static assert( 0 );

	auto sb = buf2.strideBack( buf2.length );
	if( sb != buf2.stride( buf2.length - sb ) ) buf2 = buf2[ 0 .. $ - sb ];

	size_t i = 0, j = 0;
	for( ; i < buf.length && j < buf2.length ; i++ ) buf[i] = buf2.decode( j );
	cache.popFront( j * TCHAR.sizeof );

	return i;
}
alias readUTFx!( ENCODING.UTF8, char ) readUTF8;
alias readUTFx!( ENCODING.UTF16LE, wchar ) readUTF16LE;
alias readUTFx!( ENCODING.UTF16BE, wchar ) readUTF16BE;
alias readUTFx!( ENCODING.UTF32LE, wchar ) readUTF32LE;
alias readUTFx!( ENCODING.UTF32BE, wchar ) readUTF32BE;

// SHIFT-JIS の扱いには2ヴァージョンある。
version     ( use_MultiByteToWideChar )
{
	// Windows 上で、MultiByteToWideChar を使う。
	version( Windows ){ import std.c.windows.windows; }
	else static assert( 0, "-version=use_MultiByteToWideChar は Windows専用の"
	                       "ヴァージョンです。それ以外のプラットフォームでは"
	                       "-version=use_iconv を利用して下さい。" );

	size_t readSJIS( ICache1 cache, dchar[] buf )
	{
		auto jstr = cache.peek( buf.length ).j;
		if( 0 < jstr.length && !jstr[$-1].isASCII ) jstr = jstr[ 0 .. $-1 ];
		if( 0 == jstr.length ) return 0;

		auto utf16 = new wchar[ MultiByteToWideChar( 0, 0, jstr.c.ptr, jstr.length, null, 0 ) ];
		if( 0 == utf16.length || utf16.length != MultiByteToWideChar( 0, 0, jstr.c.ptr, jstr.length
		                                                            , utf16.ptr, utf16.length ) )
			throw new Exception( "an error occured in MultiByteToWideChar()" );
		size_t i = 0, j = 0;
		for( ; i < buf.length, j < utf16.length ; i++ ) buf[i] = utf16.decode( j );
		cache.popFront( jstr.length );
		return i;
	}
}
else version( use_iconv )
{
	// iconv を使う場合は実行時に libiconv-2.dll を使います。libiconv-2.lib をリンクして下さい。
	// iconv には終了処理が必要ですので、 readSJIS.close() を必ず実行して下さい。
	alias void* iconv_t;
	extern(C) nothrow iconv_t libiconv_open( const(char)* tocode, const(char)* fromcode );
	extern(C) nothrow size_t libiconv( iconv_t cd, const(void)** inbuf, size_t* inbytesleft
	                                  , const(void)** outbuf, size_t* outbytesleft );
	extern(C) nothrow int libiconv_close( iconv_t cd );

	class readSJIS
	{
		iconv_t cd;
		this()
		{
			version     ( LittleEndian ) cd = libiconv_open( "UTF-32LE", "SHIFT-JIS" );
			else version( BigEndian ) cd = libiconv_open( "UTF-32BE", "SHIFT-JIS" );
			else static assert( 0 );
		}

		size_t opCall( ICache1 cache, dchar[] buf )
		{
			// ありったけ読み込む。
			auto src = cache.peek( buf.length ).j;
			if( 0 == src.length ) return 0;

			// いけるとこまでキャッシュ上に直接書き込む。
			auto srcptr = src.ptr;
			auto srcleft = src.length;
			auto destptr = buf.ptr;
			auto destleft = buf.length << (dchar.sizeof>>1);
			libiconv( cd, cast(const(void)**)&srcptr, &srcleft, cast(const(void)**)&destptr, &destleft );

			// 全然進んでない場合はエラー
			if( src.length == srcleft ) throw new Exception( "an error occured in iconv." );

			// 使った分だけファイルを進める。
			cache.popFront( src.length - srcleft );
			return buf.length - (destleft>>(dchar.sizeof>>1));
		}

		// 終了処理が必須
		void close() { libiconv_close( cd ); }
	}
}


debug(sequential_file)
{
	import sworks.compo.util.output;
	import sworks.compo.util.dump_members;

	void main()
	{
		try
		{
			auto ef = getSequentialBuffer( "../klisp/test.cpp" );
			for( auto d = ef.front ; !ef.eof ; d = ef.popFront ) Output( d );
			Output.ln();
			Output.ln( "cache1" );
			Output.ln( ef.getBenchmark1.dump_members );
			Output.ln( "cache2" );
			Output.ln( ef.getBenchmark.dump_members );
			ef.close;
		}
		catch( Throwable t ) Output.ln( t.toString );
	}
}

debug(ct_sequential_file)
{
	import std.conv;
	import sworks.compo.util.output;
	import sworks.compo.util.dump_members;

	string func1()
	{
		Appender!string result;
		auto ef = getSequentialBuffer( "writeln( \"hello world\" );"d );

		for( auto d = ef.front ; !ef.eof ; d = ef.popFront ) result.put( d.to!string );
		return result.data;
	}

	void main()
	{
		mixin( func1() );
	}

}