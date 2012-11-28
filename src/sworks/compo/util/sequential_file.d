/** ファイルを UTF-32 で一字ずつ読み込み。
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-28 15:55:35
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.compo.util.sequential_file;

import std.array, std.ascii, std.bitmanip, std.conv, std.stdio, std.utf;
import sworks.compo.util.cached_buffer;
version( Windows ) import sworks.compo.win32.sjis; // std.stdio.File が日本語ファイル名未対応の為

enum ENCODING
{
	NULL    = 0x00,
	UTF8    = 0x10,
	UTF16LE = 0x21,
	UTF16BE = 0x22,
	UTF32LE = 0x31,
	UTF32BE = 0x32,
	SJIS    = 0x40, // -version=use_MultiByteToWideChar か -version=use_iconv で対応

	ENDIAN_MASK   = 0x0f,
	NO_ENDIAN     = 0x00,
	LITTLE_ENDIAN = 0x01,
	BIG_ENDIAN    = 0x02,
}

// ICache の先頭に BOM があればそれを取り除き、その ENCODING を返す。
// BOM がなければ ENCODING.NULL を返す。
ENCODING strip_bom( ICache c )
{
	enum UTF8    = [ 0xef, 0xbb, 0xbf ];
	enum UTF16LE = [ 0xff, 0xfe ];
	enum UTF16BE = [ 0xfe, 0xff ];
	enum UTF32LE = [ 0xff, 0xfe, 0x00, 0x00 ];
	enum UTF32BE = [ 0x00, 0x00, 0xfe, 0xff ];

	ENCODING e = ENCODING.NULL;

	bool _check( alias BOM )()
	{
		if( BOM == c.peek_cache( BOM.length ) ) { c.discard( BOM.length ); return true; }
		else return false;
	}

	if     ( _check!UTF8 ) e = ENCODING.UTF8;
	else if( _check!UTF16LE ) e = ENCODING.UTF16LE;
	else if( _check!UTF16BE ) e = ENCODING.UTF16BE;
	else if( _check!UTF32LE ) e = ENCODING.UTF32LE;
	else if( _check!UTF32BE ) e = ENCODING.UTF32BE;
	return e;
}

/*
 * UTF32 で一字ずつ読み込む。
 * 現在の行数と、行先頭であるかどうかを保持している。
 * 改行コードは半自動判定。分からなければ(1行目がすごい長いとか)環境依存。
 * ファイルからの文字の読み込みにあたる部分を abstract にしてある。
 */
abstract class SequentialFile
{
	private dchar _line_tail;
	private string _filename;
	private size_t _line;
	protected bool _new_line;

	this( string filename )
	{
		this._filename = filename;
		this._line = 1;
		this._new_line = true;
		this._line_tail = .newline[$-1];
	}

	string filename() @property const { return _filename; }
	abstract ENCODING encoding() @property const;
	size_t line() @property const{ return _line; }
	bool newline() @property const{ return _new_line; }
	abstract bool eof() @property const;
	abstract dchar peek() @property;
	dchar discard( size_t s = 1 )
	{
		for( size_t i = 0 ; i < s ; i++ )
		{
			_new_line = ( _line_tail == peek );
			if( _new_line ) _line++;
			discard_cache;
		}
		return peek;
	}

	abstract protected void discard_cache();

	abstract const(dchar)[] peek_cache( size_t size );
	abstract void close();
}

// 改行コードの決定。二文字の改行コードの場合は最後の文字を返す。
private dchar decide_line_tail( const(dchar)[] buf )
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


/// CTFE 時などまるっとキャッシュできる場合に。
class DstringBuffer : SequentialFile
{
	private dstring _cache;
	this( dstring cache )
	{
		super( typeof(this).stringof );
		this._cache = cache;
		_line_tail = decide_line_tail( cache[ 0 .. 1024 < cache.length ? 1024 : cache.length ] );
	}

	override ENCODING encoding() @property const
	{
		version     ( LittleEndian ) return ENCODING.UTF32LE;
		else version( BigEndian ) return ENCODING.UTF32BE;
		else static assert( 0 );
	}
	override bool eof() @property const{ return 0 == _cache.length; }
	override dchar peek() @property { return 0 < _cache.length ? _cache[0] : '\0'; }
	override protected void discard_cache(){ if( 0 < _cache.length ) _cache = _cache[ 1 .. $ ]; }
	override const(dchar)[] peek_cache( size_t size )
	{
		if( _cache.length < size ) size = _cache.length;
		return _cache[ 0 .. size ];
	}
	override void close(){ _cache = null; }
}

/*
 * sworks.compo.util.cached_buffer 依存型
 * ICache の実装が公開されている。
 * 文字コード変換部分を abstract にしてある。
 */
abstract class SequentialFileCode( ENCODING CODE ) : SequentialFile
{
	protected ICache _cache;
	protected Appender!(dchar[]) _peeking_cache;
	protected dchar[] _use;

	this( string filename, ICache cache )
	{
		super( filename );
		this._cache = cache;
		refill_cache;
		_line_tail = decide_line_tail( _use );
	}

	override ENCODING encoding() @property const { return CODE; }
	override bool eof() @property const { return 0 == _use.length && _cache.eof; }
	override dchar peek() @property { return *_use.ptr; }
	abstract protected void refill_cache();
	override protected void discard_cache()
	{
		if( 1 < _use.length ) _use = _use[ 1 .. $ ];
		else { _use = _use[ 0 .. 0 ]; refill_cache; }
	}
	override const(dchar)[] peek_cache( size_t size )
	{
		if( _use.length < size ) refill_cache;
		if( _use.length < size ) size = _use.length;
		return _use[ 0 .. size ];
	}
	override void close()
	{
		_peeking_cache.shrinkTo(1);
		_peeking_cache.data[0] = '\0';
		_use = _peeking_cache.data[ 0 .. 0 ];
		_cache.close();
	}

	protected void shrink()
	{
		for( size_t i = 0 ; i < _use.length ; i++ ) _peeking_cache.data[i] = _use[i];
		_use = _peeking_cache.data[ 0 .. _use.length ];
		_peeking_cache.shrinkTo( _use.length );
		_peeking_cache.put( '\0' ); // 番兵
	}
}

// Unicode 系のファイルの読み込みに。
class SequentialFileCodeUTFx( ENCODING CODE, TCHAR ) : SequentialFileCode!CODE
{
	this( string filename, ICache cache ) { super( filename, cache ); }

	override protected void refill_cache()
	{
		shrink;

		// ありったけ読み込み
		auto buf = _cache.peek_cache( size_t.max );

		// 端数バイトを切り捨て
		auto tbuf = cast(TCHAR[])buf[ 0 .. buf.length>>(TCHAR.sizeof>>1)<<(TCHAR.sizeof>>1) ];

		// エンディアンの交換
		version     ( LittleEndian )
			static if( CODE & ENCODING.BIG_ENDIAN ) foreach( ref one ; tbuf ) one = swapEndian(one);
		else version( BigEndian )
			static if( CODE & ENCODING.LITTLE_ENDIAN ) foreach( ref one ; tbuf ) one = swapEndian(one);
		else static assert(0);
		if( 0 == tbuf.length ) return;

		// 端数文字切り捨て。
		auto sb = tbuf.strideBack( tbuf.length );
		if( sb != tbuf.stride( tbuf.length - sb ) ) tbuf = tbuf[ 0 .. $ - sb ];

		_peeking_cache.shrinkTo( _use.length );
		_peeking_cache.put( tbuf.to!(TCHAR[]) );
		_peeking_cache.put( '\0' ); // 番兵
		_use = _peeking_cache.data[ 0 .. $-1 ];

		// 使った分だけファイルを進める。
		_cache.discard( tbuf.length * TCHAR.sizeof );
	}
}
alias SequentialFileCodeUTFx!(ENCODING.UTF8, char ) SequentialFileCodeUTF8;
alias SequentialFileCodeUTFx!(ENCODING.UTF16LE, wchar ) SequentialFileCodeUTF16LE;
alias SequentialFileCodeUTFx!(ENCODING.UTF16BE, wchar ) SequentialFileCodeUTF16BE;
alias SequentialFileCodeUTFx!(ENCODING.UTF32LE, dchar ) SequentialFileCodeUTF32LE;
alias SequentialFileCodeUTFx!(ENCODING.UTF32BE, dchar ) SequentialFileCodeUTF32BE;

// SHIFT-JIS の扱いには2ヴァージョンある。
version     ( use_MultiByteToWideChar )
{
	// Windows 上で、MultiByteToWideChar を使う。
	version( Windows ){ import std.c.windows.windows; }
	else static assert( 0, "-version=use_MultiByteToWideChar は Windows専用の"
	                       "ヴァージョンです。それ以外のプラットフォームでは"
	                       "-version=use_iconv を利用して下さい。" );

	class SequentialFileCodeSJIS : SequentialFileCode!(ENCODING.SJIS)
	{
		this( string filename, ICache cache ){ super( filename, cache ); }

		override protected void refill_cache()
		{
			shrink;
			// ありったけ読み込む。
			auto src = cast(const(char)[])_cache.peek_cache( size_t.max );

			// 端数バイト切り捨て
			if( 0 < src.length && !src[$-1].isASCII ) src = src[ 0 .. $-1 ];
			if( 0 == src.length ) return;

			// まずは UTF-16 に。
			auto dest = new wchar[ MultiByteToWideChar( 0, 0, src.ptr, src.length, null, 0 ) ];
			if( 0 == dest.length || dest.length != MultiByteToWideChar( 0, 0, src.ptr, src.length
			                                                          , dest.ptr, dest.length ) )
					throw new Exception( "an error occured in MultiByteToWideChar()" );

			// UTF-32 にしてキャッシュに追加
			_peeking_cache.shrinkTo( _use.length );
			_peeking_cache.put( dest.to!(const(dchar)[]) );
			_peeking_cache.put( '\0' ); // 番兵
			_use = _peeking_cache.data[ 0 .. $-1 ];

			// 使った分だけファイルを進める。
			_cache.discard( src.length );
		}
	}
}
else version( use_iconv )
{
	// iconv を使う場合。実行時に libiconv-2.dll を使います。libiconv-2.lib をリンクして下さい。
	// iconv には終了処理が必要ですので、 SequentialFileCodeSJIS.close() を必ず実行して下さい。
	alias void* iconv_t;
	extern(C) nothrow iconv_t libiconv_open( const(char)* tocode, const(char)* fromcode );
	extern(C) nothrow size_t libiconv( iconv_t cd, const(void)** inbuf, size_t* inbytesleft
	                                  , const(void)** outbuf, size_t* outbytesleft );
	extern(C) nothrow int libiconv_close( iconv_t cd );

	class SequentialFileCodeSJIS : SequentialFileCode!(ENCODING.SJIS)
	{
		iconv_t cd;
		this( string filename, ICache cache )
		{
			_peeking_cache.put( new dchar[ cache.cache_size ] );
			_use = _peeking_cache.data[ 0 .. 0 ];
			version     ( LittleEndian ) cd = libiconv_open( "UTF-32LE", "SHIFT-JIS" );
			else version( BigEndian ) cd = libiconv_open( "UTF-32BE", "SHIFT-JIS" );
			else static assert( 0 );
			super( filename, cache );
		}

		override protected void refill_cache()
		{
			// iconv 版では _peeking_cache のサイズを替えないので shrink を使わない。
			for( size_t i = 0 ; i < _use.length ; i++ ) _peeking_cache.data[i] = _use[i];
			_use = _peeking_cache.data[ 0 .. _use.length ];

			// ありったけ読み込む。
			auto src = cast(const(char)[])_cache.peek_cache( size_t.max );
			if( 0 == src.length ) return;

			// いけるとこまでキャッシュ上に直接書き込む。
			auto srcptr = src.ptr;
			auto srcleft = src.length;
			auto dest = _peeking_cache.data[ _use.length .. $-1 ];
			auto destptr = dest.ptr;
			auto destleft = dest.length << (dchar.sizeof>>1);
			libiconv( cd, cast(const(void)**)&srcptr, &srcleft, cast(const(void)**)&destptr, &destleft );

			// 全然進んでない場合はエラー
			if( src.length == srcleft ) throw new Exception( "an error occured in iconv." );

			_use = _peeking_cache.data[ 0 .. _use.length + dest.length - (destleft>>(dchar.sizeof>>1)) ];
			_peeking_cache.data[ _use.length ] = '\0'; // 番兵

			// 使った分だけファイルを進める。
			_cache.discard( src.length - srcleft );
		}

		// 終了処理が必須
		override void close()
		{
			super.close;
			libiconv_close( cd );
		}
	}
}

/*
 * ファイルを開き、BOM を読み込んで適当な SequentialFile のインスタンスを返す。
 * BOM が見つからなかった場合は引数 code に従うが、code が ENCODING.NULL の場合は UTF-8 と見なす。
 * 引数で指定した code と見つかった BOM とが一致しない場合は例外が投げられる。
 */
SequentialFile getSequentialFile( string filename, ENCODING code = ENCODING.NULL, size_t cs = 1024 )
{
	File* f = (new File[1]).ptr; // クロージャでスコープ外に持ちだすので。
	version(Windows) (*f) = File( filename.toMBS.c, "rb" ); // 日本語ファイル名に対応する為
	else (*f) = File( filename, "rb" );

	auto cache = new CachedBuffer( r=>f.rawRead(r).length, s=>f.seek( s, SEEK_CUR )
	                             , ()=>f.close, cs );

	ENCODING e = cache.strip_bom;
	if( ENCODING.NULL == code )
	{
		if( ENCODING.NULL == e ) e = ENCODING.UTF8;
	}
	else if( ENCODING.NULL == e ) e = code;
	else if( e != code )
	{
		throw new Exception( code.to!string ~ " モードが要求されましたが、ファイル \""
		                   ~ filename ~ "\" には " ~ e.to!string ~ " のBOMが見つかりました。" );
	}

	if     ( ENCODING.UTF8 == e ) return new SequentialFileCodeUTF8( filename, cache );
	else if( ENCODING.UTF16LE == e ) return new SequentialFileCodeUTF16LE( filename, cache );
	else if( ENCODING.UTF16BE == e ) return new SequentialFileCodeUTF16BE( filename, cache );
	else if( ENCODING.UTF32LE == e ) return new SequentialFileCodeUTF32LE( filename, cache );
	else if( ENCODING.UTF32BE == e ) return new SequentialFileCodeUTF32BE( filename, cache );
	else if( ENCODING.SJIS == e )
	{
		version     ( use_MultiByteToWideChar ) return new SequentialFileCodeSJIS( filename, cache );
		else version( use_iconv ) return new SequentialFileCodeSJIS( filename, cache );
	}

	throw new Exception( e.to!string ~ " はサポートされていない文字コードです。" );
}

debug(sequential_file):
import sworks.compo.util.output;

void main()
{
	try
	{
		auto ef = getSequentialFile( "test-sjis.txt", ENCODING.SJIS );
		Output.ln( "ENCODING : ", ef.encoding.to!string );
		for( auto d = ef.peek ; !ef.eof ; d = ef.discard ) Output( d );
		ef.close;
	}
	catch( Throwable t ) Output.ln( t.toString );
}