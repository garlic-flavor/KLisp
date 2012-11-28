/** キャッシュ付き逐次ファイル読み込み。様々なファイルのパースにも!
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-28 15:55:35
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.compo.util.cached_file;

interface ICache
{
	size_t cache_size() @property const;
	ubyte peek() @property const;
	ubyte discard( size_t size = 1 );
	const(ubyte)[] peek_cache( size_t s );
	ubyte[] get_binary( ubyte[] buf );
	bool eof() @property const;
	void close();
}

// CTFE 時とか、まるっとキャッシュしておける場合に。
class WholeCache : ICache
{
	private const(ubyte)[] _cache;
	private size_t _head;

	this( const(ubyte)[] c ) { this._cache = c; }

	size_t cache_size() @property const { return _cache.length; }
	bool eof() @property const { return _cache.length <= _head; }
	ubyte peek() @property const { return _head < _cache.length ? _cache[_head] : 0; }
	ubyte discard( size_t size = 1 ){ _head += size; return peek; }
	const(ubyte)[] peek_cache( size_t s )
	{
		if( _cache.length < _head ) _head = _cache.length;
		s += _head;
		if( _cache.length < s ) s = _cache.length;
		return _cache[ _head .. s ];
	}
	void close(){ _cache = null; _head = 0; }
	ubyte[] get_binary( ubyte[] buf )
	{
		auto result = buf[ 0 .. $ ];
		if( _cache.length - _head < result.length ) result = result[ 0 .. _cache.length - _head ];
		result[] = _cache[ _head .. _head + result.length ];
		return result;
	}
}

/*
 * ファイルへの入出力の実装を外部へ公開しているので汎用的!
 * キャッシュを利用してファイルへのアクセス回数をなるべく減らしつつ、
 * 巨大なファイルでも使用メモリが増えないように。
 */
class CachedBuffer : ICache
{
	// 引数として渡された ubyte[] を値で埋める。
	// 実際に読み込むことができたバイト数を返す。
	alias size_t delegate( ubyte[] ) ReadImpl;
	// 現在位置からファイルを進める。後戻りすることはない。
	alias void delegate( size_t ) SeekImpl;
	// ファイルを閉じる。
	alias void delegate() CloseImpl;

	const size_t CACHE_SIZE;

	private ubyte[] _cache;
	private ubyte[] _use;

	private ReadImpl _read;
	private SeekImpl _seek;
	private CloseImpl _close;

	this( ReadImpl read, SeekImpl seek = null, CloseImpl closer = null, size_t cache_size = 1024 )
	{
		this.CACHE_SIZE = cache_size;
		this._cache = new ubyte[ CACHE_SIZE + /*番兵*/ 1 ];
		this._read = read;
		this._seek = seek;
		this._close = closer;
		this._use = this._cache[ 0 .. 0 ];
		_refill_cache;
	}

	private void _refill_cache()
	{
		if( 0 < _use.ptr - _cache.ptr )
		{
			for( size_t i = 0 ; i < _use.length ; i++ ) _cache[i] = _use[i];
		}
		_use = _cache[ 0 .. _use.length + _read( _cache[ _use.length .. CACHE_SIZE ] ) ];
		_cache[ _use.length ] = '\0';
	}

	size_t cache_size() @property const { return _cache.length - 1; }
	bool eof() @property const { return 0 == _use.length; }

	ubyte peek() @property const { return *_use.ptr; }

	ubyte discard( size_t size = 1 )
	{
		if( size < _use.length ) _use = _use[ size .. $ ];
		else
		{
			if( _use.length < size )
			{
				if( null !is _seek ) _seek( size - _use.length );
				else _read( new ubyte[size] );
			}
			_use = _cache[ 0 .. 0 ];
			_refill_cache;
		}
		return peek;
	}

	const(ubyte)[] peek_cache( size_t s )
	{
		if( CACHE_SIZE < s ) s = CACHE_SIZE;
		if( _use.length < s ) _refill_cache;
		if( _use.length < s ) s = _use.length;
		return _use[ 0 .. s ];
	}

	ubyte[] get_binary( ubyte[] buf )
	{
		ubyte[] result = buf[ 0 .. $ ];
		if( result.length <= _use.length )
		{	
			result[] = _use[ 0 .. result.length ];
			_use = _use[ result.length .. $ ];
		}
		else
		{
			result[ 0 .. _use.length ] = _use;
			result = result[ 0 .. _use.length + _read( result[ _use.length .. $ ] ) ];
			_use = _use[ 0 .. 0 ];
		}
		if( 0 == _use.length ) _refill_cache;
		return result;
	}

	void close()
	{
		if( null !is _close ) _close();
		_cache = _cache[ 0 .. 1 ];
		_cache[0] = '\0';
		_use = _cache[ 0 .. 0 ];
	}
}

debug(cached_file):
import std.stdio, std.ascii, std.utf;
import sworks.compo.util.output;

void main()
{
	auto file = File( "src\\sworks\\compo\\util\\cached_buffer.d", "rb" );
	auto cache = new CachedBuffer( buf => file.rawRead(buf).length, s => file.seek( s, SEEK_CUR )
	                             , ()=> file.close(), 10 );

	for( ubyte i, b = cache.peek ; '\0' != b  ; b = cache.peek, i++ )
	{
		size_t l = ((cast(char*)&b)[0 .. 1]).stride(0);
		size_t r = 0;
		try{
			auto d = (cast(char[])cache.peek_cache( l )).decode(r);
			Output( d );
		}
		catch( Throwable t ){ Output.ln( "\nERROR : ", cache._use.length ); }
		cache.discard(l);
	}

}
