/** キャッシュ付き逐次ファイル読み込み。様々なファイルのパースにも!
 * Version:      0.003(dmd2.060)
 * Date:         2013-Jan-14 02:44:54
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.compo.util.cached_buffer;
import std.array, std.traits;
debug import std.stdio;

interface TICache(T)
{
	// キャッシュサイズ
	size_t size() @property const;
	// 先頭1バイトを得る。カーソルは進めない。
	T front() @property const;
	// size バイト分カーソルを進め、次の1文字を返す。
	T popFront( size_t s = 1 );
	// 先頭から s 文字得る。カーソルは進めない。
	// cache_size よりもたくさん得ることはできない。
	const(T)[] peek( size_t s );
	const(T)[] peekBetter() @property;
	// bufをデータで埋める。カーソルはその分進む。戻り値は書き込んだ分を表す buf のスライス
	Unqual!T[] getBinary( Unqual!T[] buf );
	// ファイル終端に達したかどうか。
	bool eof() @property const;
	// ファイルを(閉じられる場合は)閉じる。
	void close();

	// 先頭 s 文字をスタックに詰む。カーソルを進め、次の1文字をpeekする。
	T push( size_t s = 1 );
	// 先頭1字の代りに c をスタックに詰む。カーソルを進め、次の1文字をpeekする。
	T push( T c );
	// スタックの内容を得る。
	const(T)[] stack() @property const;
	// スタックの内容をクリアする。
	void flush();

	debug Benchmark getBenchmark() @property const;
}

struct Benchmark
{
	size_t refill_times = 0;
	float use_max = 0.0;
	float use_average = 0.0;
	size_t rest_max_time = 0;
	float rest_max = 0.0;
	float rest_average = 0.0;
}

// メモリのコピーに。
void _array_copy_to(T)( in T[] src, T[] dest )
{
	assert( src.length <= dest.length );

	if     ( 0 == src.length || src.ptr == dest.ptr ) { }
	else if( dest.ptr + src.length <= src.ptr || src.ptr + src.length <= dest.ptr )
	{
		dest[ 0 .. src.length ] = src;
	}
	else if( dest.ptr < src.ptr )
	{
		for( size_t i = 0 ; i < src.length ; i++ ) dest[i] = src[i];
	}
	else if( src.ptr < dest.ptr )
	{
		for( size_t i = 0 ; i < src.length ; i++ ) dest[src.length-i-1] = src[$-i-1];
	}
}

// スライスの操作に
class SliceMaker(T)
{
	public T[] _payload;
	alias _payload this;

	this( T[] v ){ this._payload = v; }

	Slice slice( size_t i = 0, size_t j = 0 )
	{
		assert( i <= j );
		assert( j <= _payload.length );
		return new Slice( i, j );
	}
	Slice sliceAll() @property { return new Slice( 0, _payload.length ); }

	class Slice
	{
		private size_t _head, _tail;

		this( size_t h, size_t t ) { _head = h; _tail = t; }

		T* ptr() @property { return _payload.ptr + _head; }
		const(T)* ptr() @property const { return _payload.ptr + _head; }
		size_t length() @property const { return _tail - _head; }
		size_t head() @property const { return _head; }
		size_t tail() @property const { return _tail; }
		T* tailPtr() @property { return _payload.ptr + _tail; }
		const(T)* tailPtr() @property const { return _payload.ptr + _tail; }
		T[] payload() @property { return _payload; }
		void set( size_t h, size_t t )
		{
			assert( t <= _payload.length );
			assert( h <= t );
			_head = h; _tail = t;
		}
		bool empty() @property const { return _tail <= _head; }
		void clear( size_t pos = 0 )
		{
			assert( pos <= _payload.length );
			_head = _tail = pos;
		}
		T front() @property const { return _head < _tail ? _payload[ _head ] : T.init; }
		T popFront( size_t n = 1 )
		{
			if( _head + n < _tail ) { _head += n; return _payload[ _head ]; }
			else { _head = _tail; return T.init; }
		}

		T opIndex( size_t i ) const
		{
			assert( _head + i < _tail );
			return _payload[ _head + i ];
		}
		static if( !is( T == const ) && !is( T == immutable ) )
		{
			void opIndexAssign( T value, size_t i )
			{
				assert( _head + i < _tail );
				_payload[ _head + i ] = value;
			}
		}
		T[] opSlice() { return _payload[ _head .. _tail ]; }
		T[] opSlice( size_t i, size_t j )
		{
			assert( i <= j );
			assert( _head + j <= _tail );
			return _payload[ _head + i .. _head + j ];
		}
		const(T)[] opSlice() const { return _payload[ _head .. _tail ]; }
		const(T)[] opSlice( size_t i, size_t j ) const
		{
			assert( i <= j );
			assert( _head + j <= _tail );
			return _payload[ _head + i .. _head + j ];
		}

		void growBack( size_t n = 1 )
		{
			if( _tail + n < _payload.length ) _tail += n;
			else _tail = _payload.length;
		}
		static if( !is( T == const ) && !is( T == immutable ) )
		{
			void pushBack( in T[] src ... )
			{
				assert( _tail + src.length <= _payload.length );
				_array_copy_to( src, _payload[ _tail .. _tail + src.length ] );
				_tail = _tail + src.length;
			}
		}
	}
}


// sugar
void copyTo(T)( SliceMaker!T.Slice src, T[] dest ) { _array_copy_to( src[], dest ); }
void copyTo(T)( SliceMaker!T.Slice src, SliceMaker!T.Slice dest ) { _array_copy_to( src[], dest[] ); }
void moveTo(T)( SliceMaker!T.Slice src, size_t dest )
{
	_array_copy_to( src[], src.payload[ dest .. $ ] );
	src.set( dest, dest + src.length );
}

// CTFE 時とか、まるっとキャッシュしておける場合に。
class TWholeCache(T) : TICache!T
{
	private const(T)[] _cache;
	private const(T)[] _rest;
//	private Appender!(T[]) _stack;
	private T[] _stack;

	this( const(T)[] c )
	{
		this._cache = c;
		this._rest = this._cache[];
	}

	size_t size() @property const { return _cache.length; }
	bool eof() @property const { return 0 == _rest.length; }
	T front() @property const { return 0 < _rest.length ? _rest[0] : T.init; }
	T popFront( size_t s )
	{
		if( s < _rest.length ) _rest = _rest[ s .. $ ];
		else _rest = _rest[ $ .. $ ];
		return front;
	}
	const(T)[] peek( size_t s )
	{
		if( _rest.length < s ) s = _rest.length;
		return _rest[ 0 .. s ];
	}
	const(T)[] peekBetter() @property { return _rest[]; }
	void close(){ _cache = null; _stack = null; _rest = null; }
	Unqual!T[] getBinary( Unqual!T[] buf )
	{
		auto result = buf[ 0 .. $ ];
		if( _rest.length < result.length ) result = result[ 0 .. _rest.length ];
		result[] = _rest[ 0 .. result.length ];
		_rest = _rest[ result.length .. $ ];
		return result;
	}

	T push( size_t s = 1 )
	{
		if( _rest.length < s ) s = _rest.length;
		_stack ~= _rest[ 0 .. s ];
		_rest = _rest[ s .. $ ];
		return front;
	}
	T push( T c )
	{
		_stack ~= c;
		if( 0 < _rest.length ) _rest = _rest[ 1 .. $ ];
		return front;
	}
	const(T)[] stack() @property const { return _stack[];}
	void flush() { _stack = null; }

	debug Benchmark getBenchmark() @property const { return Benchmark(); }
}

/*
 * ファイルへの入出力の実装を外部へ公開しているので汎用的!
 * キャッシュを利用してファイルへのアクセス回数をなるべく減らしつつ、
 * 巨大なファイルでも使用メモリが増えないように。
 */
class TCachedBuffer(T) : TICache!T
{
	// 引数として渡された buf を値で埋める。
	// 実際に読み込むことができた配列長を返す。
	alias size_t delegate( T[] buf ) ReadImpl;
	// 現在位置から s 文字数分ファイルを進める。後戻りすることはない。
	alias void delegate( size_t s ) SeekImpl;
	// ファイルを閉じる。
	alias void delegate() CloseImpl;

	const size_t CACHE_SIZE;

	private SliceMaker!T _cache;
	private SliceMaker!T.Slice _rest;
	private SliceMaker!T.Slice _stack; // push の量が少ない場合は _cache を使う。
	private Appender!(T[]) _buffer; // CACHE_SIZE / 2 よりたくさん push した時に使われる。

	private ReadImpl _read;
	private SeekImpl _seek;
	private CloseImpl _close;

	this( ReadImpl read, SeekImpl seek = null, CloseImpl closer = null, size_t cache_size = 1024 )
	{
		this.CACHE_SIZE = cache_size;
		this._cache = new SliceMaker!T( new T[ CACHE_SIZE + /*番兵*/ 1 ] );
		this._read = read;
		this._seek = seek;
		this._close = closer;
		this._rest = _cache.slice;
		this._stack = _cache.slice;
		_refill_cache;
	}

	private void _refill_cache()
	{
		debug { with( _bmark ) {
			use_average *= refill_times;
			rest_average *= refill_times;

			refill_times++;
			float r = _stack.length + _rest.length;
			if( rest_max < r )
			{
				rest_max = r;
				rest_max_time = refill_times;
			}
			rest_average = ( rest_average + r ) / refill_times;
		} }

		_stack.moveTo(0);
		_rest.moveTo( _stack.tail );
		if( _rest.tail < CACHE_SIZE )
			_rest.set( _rest.head, _rest.tail + _read( _cache[ _rest.tail .. CACHE_SIZE ] ) );
		_cache[ _rest.tail ] = T.init;

		debug { with(_bmark ) {
			float u = cast(float)_rest.length;
			use_max = use_max < u ? u : use_max;
			use_average = ( use_average + u ) / refill_times;
		} }
	}

	size_t size() @property const { return CACHE_SIZE; }
	bool eof() @property const { return _rest.empty; }

	T front() @property const { return *_rest.ptr; }

	T popFront( size_t s = 1 )
	{
	top:
		if     ( s < _rest.length ) _rest.popFront( s );
		else if( null !is _seek )
		{
			if( _rest.length < s ) _seek( s - _rest.length );
			_rest.clear( _stack.tail );
			_refill_cache;
		}
		else
		{
			s -= _rest.length;
			_rest.clear( _stack.tail );
			_refill_cache;
			if( !_rest.empty ) goto top;
		}
		return *_rest.ptr;
	}

	const(T)[] peek( size_t s )
	{
		if( _rest.length < s ) _refill_cache;
		if( _rest.length < s ) s = _rest.length;
		return _rest[ 0 .. s ];
	}
	const(T)[] peekBetter() @property
	{
		if( _rest.length < (CACHE_SIZE>>1) ) _refill_cache;
		return _rest[];
	}

	T[] getBinary( T[] buf )
	{
		T[] result = buf[ 0 .. $ ];
		if( result.length <= _rest.length )
		{	
			result[] = _rest[ 0 .. result.length ];
			_rest.popFront( result.length );
		}
		else
		{
			result[ 0 .. _rest.length ] = _rest[];
			result = result[ 0 .. _rest.length + _read( result[ _rest.length .. $ ] ) ];
			_rest.clear( _stack.tail );
		}
		if( _rest.empty ) _refill_cache;
		return result;
	}

	void close()
	{
		if( null !is _close ) _close();
		_cache = _cache[ 0 .. 1 ];
		_cache[0] = T.init;
		_rest.clear;
		_stack.clear;
		_buffer.clear;
	}

	T push( size_t s = 1 )
	{
		if     ( (CACHE_SIZE>>1) < _stack.length )
		{
			_buffer.put( _stack[] );
			_stack.clear( _rest.head );
		}
		else if( _stack.empty ) _stack.clear( _rest.head );

		if( _rest.length < s ) _refill_cache;
		if( _rest.length < s ) s = _rest.length;

		_stack.pushBack( _rest[ 0 .. s ] );
		_rest.popFront( s );
		if( _rest.empty ) _refill_cache;
		return *(_rest.ptr);
	}
	T push( T c )
	{
		if     ( (CACHE_SIZE>>1) < _stack.length )
		{
			_buffer.put( _stack[] );
			_stack.clear( 0 );
		}
		else if( _stack.empty ) _stack.clear( 0 );

		if( _rest.length < 1 ) _refill_cache;
		if( 0 == _rest.length ) return T.init;

		_stack.pushBack( c );
		_rest.popFront;
		if( _rest.empty ) _refill_cache;
		return *(_rest.ptr);
	}

	const(T)[] stack() @property const
	{
		return 0 < _buffer.data.length ? _buffer.data[] ~ _stack[] : _stack[];
	}

	void flush() { _buffer.clear; _stack.clear( _rest.head ); }


	debug
	{
		private Benchmark _bmark;
		Benchmark getBenchmark() @property const { return _bmark; }
	}
}

debug(cached_buffer):
import std.stdio, std.ascii, std.utf;
import sworks.compo.util.output;
import sworks.compo.util.dump_members;

void main()
{
	alias TCachedBuffer!ubyte CachedBuffer;
	alias TWholeCache!(const(char)) WholeCache;
	auto file = File( "src\\sworks\\compo\\util\\cached_buffer.d", "rb" );
//*
	auto cache = new CachedBuffer( buf => file.rawRead(buf).length, s => file.seek( s, SEEK_CUR )
	                             , ()=> file.close(), 128 );
/*/
	auto cache = new WholeCache( import( "cached_buffer.d" ) );
//*/
	for( ubyte i, b = cache.front ; !cache.eof  ; b = cache.front, i++ )
	{
		size_t l = ((cast(char*)&b)[0 .. 1]).stride(0);
		size_t r = 0;
		try{
			auto d = (cast(char[])cache.peek( l )).decode(r);
			Output( d );
		}
		catch( Throwable t ){ Output.ln( "\nERROR : ", cache._rest.length ); }
		cache.popFront(l);
	}
	Output.ln( cache.getBenchmark.dump_members );
}
