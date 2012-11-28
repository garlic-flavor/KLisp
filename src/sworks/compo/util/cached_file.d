module sworks.compo.util.cached_file;

interface ICache
{
	size_t cache_size() @property const;
	bool eof() @property const;
	ubyte peek() @property const;
	ubyte discard( size_t size = 1 );
	const(ubyte)[] peek_cache( size_t s );
	void close();
	ubyte[] get_binary( ubyte[] buf );
}

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
		if( _cache.length < _head + s ) s = _cache.length - _head;
		return _cache[ _head .. _head + s ];
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

class CachedFile : ICache
{
	alias size_t delegate( ubyte[] ) ReadImpl;
	alias void delegate( size_t ) SeekImpl;
	alias void delegate() CloseImpl;

	const size_t CACHE_SIZE;

	private ubyte[] _cache;
	private ubyte[] _use;

	private ReadImpl _read;
	private SeekImpl _seek;
	private CloseImpl _close;

	this( ReadImpl read, SeekImpl seek, CloseImpl closer, size_t cache_size = 1024 )
	{
		this.CACHE_SIZE = cache_size;
		this._cache = new ubyte[ CACHE_SIZE+1 ];
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
		_use = _cache[ 0 .. _use.length + _read( _cache[ _use.length .. $-1 ] ) ];
		_cache[ _use.length ] = '\0';
	}

	size_t cache_size() @property const { return CACHE_SIZE; }
	bool eof() @property const { return 0 == _use.length; }

	ubyte peek() @property const { return *_use.ptr; }

	ubyte discard( size_t size = 1 )
	{
		if( size < _use.length ) _use = _use[ size .. $ ];
		else
		{
			if( _use.length < size ) _seek( size - _use.length );
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
		ubyte[] result;
		if( buf.length <= _use.length )
		{
			buf[] = _use[ 0 .. buf.length ];
			result = buf[ 0 .. $ ];
		}
		else
		{
			buf[ 0 .. _use.length ] = _use;
			result = buf[ 0 .. _use.length + _read( buf[ _use.length .. $ ] ) ];
		}
		discard( result.length );
		return result;
	}

	void close()
	{
		_close();
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
	auto file = File( "src\\sworks\\compo\\util\\cached_file.d", "rb" );
	auto cache = new StraightCache( buf => file.rawRead(buf).length, s => file.seek( s, SEEK_CUR )
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



/+
class CircularCache : ICache
{
	// 引数として渡された ubyte[] をデータで埋め、書き込んだ byte 数を返す。
	alias size_t delegate( ubyte[] ) ReadImpl;
	// 引数として渡された byte 分、現在位置よりファイル内で位置を進める。
	alias void delegate( size_t ) SeekImpl;
	alias void delegate() CloseImpl;

	// キャッシュサイズ。実際には番兵を置くので CACHE_SIZE-1 だけキャッシュする。
	const size_t CACHE_SIZE;

	private ubyte[] _cache; // キャッシュ本体
	private size_t _head, _tail; // キャッシュのどの部分を使っているか。

	private ReadImpl _read;
	private SeekImpl _seek;
	private CloseImpl _close;

	this( ReadImpl read, SeekImpl seek, CloseImpl closer, size_t cache_size = 1024 )
	{
		this.CACHE_SIZE = cache_size;
		this._cache = new ubyte[ CACHE_SIZE ];
		this._read = read;
		this._seek = seek;
		this._close = closer;
		this._head = 0;
		this._tail = 0;
		_refill_cache();
	}

	private size_t _rest() @property const
	{
		if( _head <= _tail ) return _tail - _head;
		else return CACHE_SIZE - _head + _tail;
	}

	private void _refill_cache()
	{
		if( _head == _tail ) _head = _tail = 0;
		auto prev_t = _tail;
		_tail = 0 < _head ? _head - 1 : CACHE_SIZE-1;
		if( prev_t < _tail ) _tail = _read( _cache[ prev_t .. _tail ] ) + prev_t;
		else
		{
			size_t r;
			if( 0 == _head ) r = _read( _cache[ prev_t .. $-1 ] );
			else r = _read( _cache[ prev_t .. $ ] );
			if     ( r < CACHE_SIZE - prev_t ) _tail = prev_t + r;
			else if( 0 < _tail ) _tail = _read( _cache[ 0 .. _tail ] );
		}
		_cache[_tail] = 0;
	}

	size_t cache_size() @property const { return CACHE_SIZE; }
	bool eof() @property const { return 0 == _rest; }

	// 先頭 1byte を返す。
	ubyte peek( ) @property const { return _cache[ _head ]; }

	// 1byte _head を進めて、次の 1byte を返す。
	ubyte discard( size_t size = 1 )
	{
		if( _tail < _head ) _tail += CACHE_SIZE;
		_head += size;

		if     ( _tail < _head )
		{
			_seek( _head - _tail );
			_head = _tail;
			_refill_cache;
		}
		else if( _tail == _head )
		{
			_refill_cache();
		}
		else
		{
			if( CACHE_SIZE <= _tail ) _tail -= CACHE_SIZE;
			if( CACHE_SIZE <= _head ) _head -= CACHE_SIZE;
		}
		return _cache[ _head ];
	}

	// 先頭から s byte 読み取る。
	// キャッシュ内で連続した領域に収まっている場合はキャッシュの中身をそのまま返すので、
	// 戻り値を利用する場合は注意が必要。(キャッシュを一巡すると値が書き替えられるので。)
	const(ubyte)[] peek_cache( size_t s )
	{
		if( _rest < s ) _refill_cache();
		if( _rest < s ) s = _rest; // CACHE_SIZE-1 よりたくさん peek できない。
		if( s <= CACHE_SIZE - _head ) return _cache[ _head .. _head + s ];
		else
		{
			auto result = new ubyte[ s ];
			result[ 0 .. CACHE_SIZE - _head ] = _cache[ _head .. $ ];
			result[ CACHE_SIZE - _head .. $ ] = _cache[ 0 .. s - CACHE_SIZE + _head ];
			return result;
		}
	}

	void close()
	{
		_close();
		_cache = _cache[ 0 .. 1 ];
		_head = _tail = 0;
	}

	ubyte[] get_binary( ubyte[] buf )
	{
		ubyte[] r = buf[ 0 .. $ ];
		for( const(ubyte)[] result ; 0 < _rest && 0 < r.length ; )
		{
			result = peek_cache( r.length );
			r[ 0 .. result.length ] = result;
			r = r[ result.length .. $ ];
			discard( result.length );
		}
		return buf[ 0 .. $ - r.length ];
	}
}
+/

