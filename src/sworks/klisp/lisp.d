/** 空のLisp-like言語の実装。
 * Version:      0.004(dmd2.061)
 * Date:         2013-Jan-21 00:02:00
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.lisp;

import std.algorithm, std.array, std.string, std.exception, std.conv, std.file, std.math;
import sworks.compo.util.output;
import sworks.klisp.klisp_file;
private import sworks.klisp.token;

// 参照 YaneLisp ( http://labs.yaneu.com/20090905/ )

//------------------------------------------------------------------------------
// S式
struct SExp
{
	private AddressPart _ar; // 中身
	SExp* cdr; // 次のん。ポインタ型であることに注意
	
	this( AddressPart ar, SExp* cdr = null ){ this._ar = ar; this.cdr = cdr; }
	this( SExp s ){ this._ar = s._ar; this.cdr = s.cdr; }

	// 自身が空の式かどうか。
	bool empty() @property const { return null is _ar; }

	// 空の式にする。
	void clear() { this._ar = null; this.cdr = null; }

	// cdr が有効かどうか。
	bool remain() @property const { return null !is _ar && null !is cdr && !cdr.empty; }

	// 中身へのアクセス
	SExp car() @property { return null is _ar ? SExp() : _ar.contents; }
	void car( SExp s ) @property { if( null !is _ar ) _ar.contents = s; }
	AddressPart address() @property { return _ar; }

	// 中身を評価する。残りの S式は ei.rest にある。
	SExp eval( EvalInfo ei ) { return null is _ar ? SExp() : _ar.eval( ei ); }

	// 中身が null でも失敗しないのだ。
	dstring toDstring() @property { return null is _ar ? "#undef" : _ar.toDstring; }
	bool toBool() @property { return null is _ar ? false : _ar.toBool; }
	int toInt() @property { return null is _ar ? 0 : _ar.toInt; }
	double toDouble() @property { return null is _ar ? double.nan : _ar.toDouble; }

	// CTFE用。初期化関数を文字列で返す。
	dstring toInitializer() @property { return "SExp(" ~ (null is _ar ? "" : _ar.toInitializer) ~ ")"; }
}

//------------------------------------------------------------------------------
// S式の中身
class AddressPart
{
	// 中身。List 型、Symbol 型以外の型では戻り値の中身は自分自身
	SExp contents() @property { return SExp(this); }
	void contents( SExp ) @property{ };

	// 評価する。自身が含まれる括弧深度以下の、自分以降の S式が ei.rest に入っている。
	SExp eval( EvalInfo ei ) { return SExp(this); }

	dstring toDstring() @property { return "#undef"d; }
	bool toBool() @property { return false; }
	int toInt() @property { return 0; }
	double toDouble() @property { return double.nan; }
	dstring toInitializer() @property { return ""; }
}

//------------------------------------------------------------------------------
// 実行時情報を格納する。
class EvalInfo
{
	protected Appender!(SExp[]) _rest; // 評価待ちの S式。括弧の深度により配列に分けて格納されている。
	protected bool _break_flag; // true -> break中
	SExp[dstring] info;
	SExp result; // 直前の評価結果

	// break 中かどうか
	bool breaking() @property const { return _break_flag; }
	void breakOut() { _break_flag = true; if( 0 < _rest.data.length ) _rest.data[$-1].clear; }
	void recover() { _break_flag = false; } // break からの復帰

	// 未評価の式が残っているかどうか。
	bool remain() @property const
	{
		return !_break_flag && 0 < _rest.data.length && !_rest.data[$-1].empty;
	}
	// 残りの式。戻り値の型が ref なのに注意
	ref SExp rest() @property
	{
		static SExp dummy;
		return !_break_flag && 0 < _rest.data.length ? _rest.data[$-1] : dummy;
	}

	// リストの深度を上げる／下げる。
	void push( SExp sexp ) { _rest.put( !_break_flag ? sexp : SExp() ); }
	void pop()
	{
		if( 0 < _rest.data.length ) _rest.shrinkTo( _rest.data.length - 1 );
		if( 0 == _rest.data.length && _break_flag )
			throw new KLispMessage( "break 中にファイル終端に達しました。" );
	}
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// S式がらみの sugar たち

// コンストラクタシュガー
SExp S( T, PARAM  ... )( PARAM param ) { return SExp( new T( param ) ); }
SExp* Sp( T, PARAM ... )( PARAM param ) { return new SExp( new T( param ) ); }

// SExp をどんどん追加していく。
// 循環参照に注意
struct SExpAppender
{
	private SExp _head;
	private SExp* _ite;

	bool put( AddressPart a )
	{
		if     ( null is a ) return false;
		else if( null is _ite ) { _head = SExp( a ); _ite = &_head; }
		else { _ite.cdr = new SExp( a ); _ite = _ite.cdr; }
		return true;
	}

	// se.cdr 以降のリストも複製される。
	bool put( SExp se )
	{
		if( se.empty ) return false;
		if( null is _ite ){ _head = SExp( se.address ); _ite = &_head; }
		else { _ite.cdr = new SExp( se.address ); _ite = _ite.cdr; }

		for( auto i = se.cdr ; null !is i && !i.empty ; i = i.cdr )
		{
			_ite.cdr = new SExp( i.address );
			_ite = _ite.cdr;
		}
		return true;
	}

	SExp data() @property { return _head; }
	void clear() { _head.clear; _ite = null; }
}

// SExp をどんどん上書きする。
struct SExpRewriter
{
	SExp data;

	bool put( SExp s )
	{
		if( s.empty ) return false;
		else data = s;
		return true;
	}
}

// リストの最後まで辿る。
SExp last( SExp se )
{
	version(assert) int i = 0;
	for( ; ; se = *se.cdr )
	{
		if( null is se.cdr || se.cdr.empty ) return se;
		assert( ++i < 1024 ); // 循環参照チェック
	}
	return se;
}

// SExp を一個進める。
// 戻り値の cdr は null。
SExp popFront( ref SExp se )
{
	auto s = SExp( se.address );
	if( null !is se.cdr ) se = *se.cdr;
	else se.clear;
	return s;
}

// ei に残ってる式の先頭一つを評価する。
SExp popEval( EvalInfo ei )
{
	assert( null !is ei );
	auto r = ei.rest.popFront.eval( ei );
	ei.result = SExp( r.address );
	return r;
}

// 現在の深度の式を全部評価する。
// 戻り値は、全ての評価がリストで帰る。
SExp evalAll( EvalInfo ei )
{
	assert( null !is ei );
	SExpAppender acc;
	for( ; ei.remain ; ) acc.put( ei.popEval );
	return acc.data;
}

// 深度を一つ下げて 引数 rest を全て評価する。
// この関数が帰る時、深度は元に戻っている。
// 戻り値は最後の式の戻り値になる。
SExp evalAllChild( EvalInfo ei, SExp rest )
{
	assert( null !is ei );

	ei.push( rest ); scope(exit) ei.pop;
	SExpRewriter result;
	for( ; ei.remain ; ) result.put( ei.popEval );
	return result.data;
}

// 深度を一つ下げて 引数 rest を全て評価する。
// この関数が帰る時、深度は元に戻っている。
// 戻り値は全ての評価結果のリスト
SExp evalAllChildResult( EvalInfo ei, SExp rest )
{
	assert( null !is ei );

	ei.push( rest ); scope(exit) ei.pop;
	SExpAppender acc;
	for( ; ei.remain ; ) acc.put( ei.popEval );
	return acc.data;;
}

// 全部複製する。引数 cdr に何か渡せば、複製後のリストの最後にくっつける。
// address の中身は dup しない。
SExp dupAll( SExp se, SExp cdr = SExp() )
{
	SExpAppender acc;
	acc.put( se );
	acc.put( cdr );
	return acc.data;
}

// current address の型を調べる。
bool isTypeOf( T )( SExp s ){ return null !is cast(T)s.address; }

// リスト全部を文字列にする。
dstring toDstringAll( SExp s, dstring joiner = "" )
{
	Appender!dstring acc;
	for( ; ; )
	{
		acc.put( s.popFront.toDstring );
		if( s.empty ) break;
		else acc.put( joiner );
	}
	return acc.data;
}

// リスト全部を初期化関数の文字列にする。
dstring toInitializerAll( SExp s )
{
	auto acc = appender( "(){ SExpAppender acc;\n"d );
	for( ; !s.empty ; s.popFront ) acc.put( "acc.put(" ~ s.toInitializer ~");\n" );
	acc.put( "return acc.data;}()" );
	return acc.data;
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// address の具体的な中身

//------------------------------------------------------------------------------
// 未定義
class Undef : AddressPart
{
	override dstring toInitializer() @property { return "new Undef()"; }
}

//------------------------------------------------------------------------------
// 真
class T : AddressPart
{
	override dstring toDstring() @property { return "#t"d; }
	override bool toBool() @property { return true; }
	override int toInt() @property { return 1; }
	override double toDouble() @property { return 1.0; }
	override dstring toInitializer() @property{ return "new T()"; }
}

//------------------------------------------------------------------------------
// 偽
class Nil : AddressPart
{
	override dstring toDstring() @property { return "#nil"d; }
	override dstring toInitializer() @property { return "new Nil()"; }
}

//------------------------------------------------------------------------------
// 整数型 32bit
class Int : AddressPart
{
	int value;
	this( int i ){ this.value = i; }
	override dstring toDstring() @property { return to!dstring(value); }
	override int toInt() @property { return value; }
	override bool toBool() @property { return 0 != value; }
	override double toDouble() @property { return cast(double)value; }
	override dstring toInitializer() @property { return "new Int(" ~ value.to!dstring ~ ")"; }
}

//------------------------------------------------------------------------------
// 浮動小数点数 64bit。
// ※ _source をとっているのは、double.to!dstring が CTFE で通らないから。
class Double : AddressPart
{
	private dstring _source;
	private double _value;
	this( const(dchar)[] val ) { this._source = val.idup; this._value = _source.to!double; }
	this( double v ){ this._value = v; this._source = v.to!dstring; }
	double value() @property { return _value; }
	void value( double v ) @property { _value = v; _source = v.to!dstring; }
	override dstring toDstring() @property { return _source; }
	override int toInt() @property { return cast(int)_value; }
	override bool toBool() @property { return double.nan !is _value; }
	override double toDouble() @property { return _value; }
	override dstring toInitializer() @property { return "new Double(`" ~ _source ~ "`)"; }
}

//------------------------------------------------------------------------------
// UTF-32文字列
class Dstr : AddressPart
{
	dstring value;
	this( dstring dstr ) { this.value = dstr; }
	override dstring toDstring() @property { return value; }
	override int toInt() @property { int v; collectException( value.to!int, v ); return v; }
	override bool toBool() @property { return 0 < value.length; }
	override double toDouble() @property { double v; collectException( value.to!double, v ); return v;}
	override dstring toInitializer() @property { return "new Dstr(`" ~ value ~ "`)"; }
}

//------------------------------------------------------------------------------
// リスト型
class List : AddressPart
{
	SExp value;
	this( SExp sexp ) { this.value = sexp; }
	override SExp contents() @property { return value; }
	override void contents( SExp s ) @property { value = s; }
	override SExp eval( EvalInfo ei ) { return ei.evalAllChild( value ); }
	override dstring toDstring() @property { return value.toDstringAll(" "); }
	override dstring toInitializer() @property { return "new List(" ~ value.toInitializerAll ~ ")"; }
}

//------------------------------------------------------------------------------
// D言語側で中身を提供する関数型
class Func : AddressPart
{
	// 簡易な定義済み関数の中身。
	// この場合、SymbolStore にアクセスできない。そういう用途には FuncBase を継承する形で実装する。
	alias SExp function( EvalInfo ei ) Body;

	dstring name;
	Body _func;

	this( dstring name, Body f ) { assert( f ); this.name = name; this._func = f; }
	override SExp eval( EvalInfo ei ) { assert( _func ); return _func( ei ); }
	override dstring toDstring() @property { return "#"d ~ name; }
	override dstring toInitializer() @property { return "new Func(`"d ~ name ~ "`, &" ~ name ~ ")"; }
}

//------------------------------------------------------------------------------
// 関数型に共通の機能を提供する。
class FuncBase : AddressPart
{
	dstring name;
	dstring class_name;
	alias SExp delegate() Parser;

	this( dstring name ){ this.name = name; }

	// パース時に呼ばれる。自分の直後以降のS式にアクセスできる。
	// SymbolStore.pushPrefix を呼ぶことでシンボル名の解決方法を制御できる。
	SExp filter( SExp prev, SymbolStore ss , Parser parser ) { return SExp(); }

	override dstring toDstring() @property { return "#"d ~ name; }
	override dstring toInitializer() @property { return "new "d ~ class_name ~ "()"d; }
}

//------------------------------------------------------------------------------
// シンボル型。SymbolSeed.getInstance で生成される。
// 中身の本体は生成元の SymbolSeed が保持している。
class Symbol : AddressPart
{
	string filename; // このシンボルが記述されていたファイル名
	size_t line;     // このシンボルが登場した行数
	dstring name;
	SymbolSeed root; // 中身

	this( string filename, size_t line, dstring name, SymbolSeed seed )
	{
		assert( seed );

		this.filename = filename;
		this.line = line;
		this.name = name;
		this.root = seed;
	}

	override SExp contents() @property { assert(null !is root); return root.value; }
	override void contents( SExp sexp ) @property { assert( root ); root.value = sexp; }
	override SExp eval( EvalInfo ei )
	{
		assert( root );
		if( ei.breaking ) return SExp();
		try
		{
			root.attach;
			scope( exit ) root.detach;

			ei.rest = root.value.dupAll( ei.rest );
			return ei.popEval;
		}
		catch( KLispMessage re ) throw new KLispException( filename, line, name, re.msg );
		return SExp();
	}

	override dstring toDstring() @property { return name; }
	override int toInt() @property { assert( root ); return root.value.toInt; }
	override bool toBool() @property { assert( root ); return root.value.toBool; }
	override double toDouble() @property { assert( root ); return root.value.toDouble; }
	override dstring toInitializer() @property
	{
		return root.id ~ ".getInstance(`" ~ filename.to!dstring ~ "`, " ~ line.to!dstring ~ ")";
	}
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// シンボル本体
class SymbolSeed
{
	dstring name;
	dstring id; // CTFE 時に宣言される変数名。

	protected SExp _value;

	enum MAX_ATTACH = 1024;
	private size_t semaphore; // 参照数をカウントし、循環参照を検出する。
	bool instanced;

	this( dstring name, dstring id, SExp v = SExp() )
	{
		this.name = name;
		this.id = id;
		this._value = v.empty ? S!Undef : v;
		semaphore = 0;
		instanced = false;
	}

	SExp value() @property { return _value; }
	void value( SExp s ) @property { _value = s; }

	void attach()
	{
		if( MAX_ATTACH < semaphore++ ) throw new KLispMessage( "シンボル参照の深度が深すぎます。" );
	}
	void detach() { assert( 0 < semaphore ); semaphore--; }

	SExp getInstance( string filename, size_t line )
	{
		instanced = true;
		return SExp(new Symbol( filename, line, name, this ));
	}

	// Lispコード内での参照順と初期化関数の実行順とが一致するとはかぎらないので、中身は後で代入した方がよい。
	dstring toInitializer() @property
	{
		return "new SymbolSeed(`" ~ name ~ "`, `" ~ id ~ "`)";
	}
}

//------------------------------------------------------------------------------
// Inline Mode で使われる。D言語のシンボルを参照する。
// DSymbolSeed!void は CTFE 時に一時的に使われる。
class DSymbolSeed(TYPE)
	if( is( TYPE : int ) || is( TYPE : double ) || is( TYPE : dstring ) || is( TYPE : Func.Body )
	 || is( TYPE : SExp ) || is( TYPE : void ) ) : SymbolSeed
{
	TYPE* _bare; // D言語のシンボルへの参照

	this( dstring name, dstring id, TYPE* v = null){ super( name, id ); this._bare = v; _value.clear; }

	override SExp value() @property
	{
		if( _value.empty )
		{
			static if     ( is( TYPE : int ) ) _value = SExp( new Int( *_bare ) );
			else static if( is( TYPE : double ) ) _value = SExp( new Double( _bare.to!dstring ) );
			else static if( is( TYPE : dstring ) ) _value = SExp( new Dstr( *_bare ) );
			else static if( is( TYPE : SExp ) ) _value = *_bare;
			else static if( is( TYPE : Func.Body ) ) _value = SExp( new Func( name, _bare ) );
		}
		return _value;
	}

	override void value( SExp v ) @property
	{
		if( v.empty ) return;
		assert( null !is _bare );
		_value = v;
		static if     ( is( TYPE : int ) ) (*_bare) = v.toInt;
		else static if( is( TYPE : double ) ) (*_bare) = v.toDouble;
		else static if( is( TYPE : dstring ) ) (*_bare) = v.toDstring;
		else static if( is( TYPE : SExp ) ) (*_bare) = v;
	}

	override dstring toInitializer() @property
	{
		// 初期化関数では、正しい型でインスタンス化する。
		return "new DSymbolSeed!(typeof(" ~ name ~ "))(`" ~ name ~ "`, `" ~ id ~ "`, &" ~ name ~ ")";
	}

}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// シンボル名解決
// シンボル名はパース時に解決しておく。その為、ちょっと可読性下ってるかも。
// _prefix を使って変数にながーい名前をつけることでシンボルのスコープ切り変えを実装している。
class SymbolStore
{
	private SymbolSeed[dstring] symbols; // 本体
	private uint symbol_counter; // CTFE 時に固有のシンボル名を付けるために使う。
	enum SYMBOL_ID_PREFIX = "symbol_"d; // CTFE 時に使う。
	enum PREFIX_DELIMITER = "."d;
	enum LOCAL_MODE_PREFIX = "L"d;
	enum PRIVATE_MODE_PREFIX = "P"d;
	enum GLOBAL_MODE_PREFIX = "G"d;
	dstring _prefix; // Lispコード内の変数名を修飾するながーい名前

	// SCOPE_MODE.INLINE では、symbols にシンボルが見付からなかった場合、
	// 外側の D言語スコープにシンボルが「ある」と仮定してコードを生成する。
	enum SCOPE_MODE{ ISOLATE, INLINE }
	SCOPE_MODE scope_mode;

	this( SCOPE_MODE sm = SCOPE_MODE.ISOLATE ) { this.scope_mode = __ctfe ? sm : SCOPE_MODE.ISOLATE; }

	dstring newSymbolID() { return __ctfe ? SYMBOL_ID_PREFIX ~ (symbol_counter++).to!dstring : ""; }

	// 親スコープまでシンボルを探しにいく。
	SymbolSeed getRoot( dstring name )
	{
		SymbolSeed* psr;
		name = _prefix ~ name;
		for( ; ; )
		{
			psr = name in symbols;
			if     ( null !is psr ) return (*psr);
			else if( !name.findSkip( PREFIX_DELIMITER ) ) break;
		}
		// シンボルがみつからなかった場合、新しくシンボルを確保するが、
		// その際、_prefix の先頭一字が L/P/G のどれかによって挙動が変わる。
		SymbolSeed sr;
		if     ( SCOPE_MODE.INLINE == scope_mode )
		{
			sr = new DSymbolSeed!void( name, newSymbolID() );
			symbols[ name ] = sr;
		}
		else
		{
			sr = new SymbolSeed( name, newSymbolID() );
			if( 0 < _prefix.startsWith( LOCAL_MODE_PREFIX ) ) symbols[ _prefix ~ name ] = sr;
			else
			{
				symbols[ name ] = sr;
				if( 0 < _prefix.length ) symbols[ _prefix ~ name ] = sr;
			}
		}
		return sr;
	}
	SExp opIndex( string filename, size_t line, dstring name )
	{
		if( 0 < _prefix.startsWith( PRIVATE_MODE_PREFIX ) ) return local( filename, line, name );
		else return getRoot(name).getInstance( filename, line );
	}
	void opIndexAssign( SExp se, dstring name )
	{
		if( 0 < _prefix.startsWith( PRIVATE_MODE_PREFIX ) ) local( name, se );
		else getRoot( name ).value = se;
	}

	// ローカルのシンボルに対象を限定して探す。
	bool have( dstring name ) { return null !is ( (_prefix ~ name) in symbols ); }
	SExp local( string filename, size_t line, dstring name )
	{
		name = _prefix ~ name;
		auto pse = name in symbols;
		if( null !is pse ) return pse.getInstance( filename, line );
		auto s = new SymbolSeed( name, newSymbolID() );
		symbols[ name ] = s;
		return s.getInstance( filename, line );
	}
	void local( dstring name, SExp se )
	{
		name = _prefix ~ name;
		auto pse = name in symbols;
		if( null !is pse ) pse.value = se;
		symbols[ name ] = new SymbolSeed( name, newSymbolID(), se );
	}

	dstring prefix() @property { return _prefix; }

	// pushPrefix( "hoge" ); の戻り値は、"Ghoge." となる。
	// 続けて pushPrefix( "fuga", SymbolStore.PRIVATE_MODE_PREFIX ); で呼び出した場合の戻り値は、"Pfuga.Ghoge."となる。
	dstring pushPrefix( dstring pre, dstring scope_prefix = GLOBAL_MODE_PREFIX )
	{
		_prefix = scope_prefix ~ pre ~ PREFIX_DELIMITER ~ _prefix;
		return _prefix;
	}
	dstring popPrefix()
	{
		_prefix.findSkip( PREFIX_DELIMITER );
		return _prefix;
	}

	// T が、 B そのものか、その子クラスである場合は、 true
	// is 式の第一引数として __traits を渡せない為
	private template IsBaseClassOf( alias T, B )
	{
		enum IsBaseClassOf = is( T == class ) && is( T : B );
	}

	// module 単位でシンボルを追加
	void entry( alias MODULE )() if( !is( typeof(&MODULE) == function ) && !is( MODULE : FuncBase ) )
	{
		foreach( SYMBOL ; __traits( allMembers, MODULE ) )
		{
			// 意味不なマングル名の混入を防ぐため。
			static if     ( !__traits( compiles, __traits(getMember, MODULE, SYMBOL ) ) ) { }
			else static if( is( typeof(&__traits( getMember, MODULE, SYMBOL )) : Func.Body ) )
			{
				entry!(__traits( getMember, MODULE, SYMBOL ))( SYMBOL.to!dstring );
			}
			else static if( IsBaseClassOf!( __traits( getMember, MODULE, SYMBOL ), FuncBase ) )
			{
				entry!(__traits( getMember, MODULE, SYMBOL ))( SYMBOL.to!dstring );
			}
			else static if( is( typeof(__traits( getMember, MODULE, SYMBOL )) : AddressPart ) )
			{
				entry!(typeof(__traits( getMember, MODULE, SYMBOL )))( SYMBOL.to!dstring );
			}
		}
	}

	// 個別に追加
	void entry( alias FUNC )( dstring name ) if( is( typeof(&FUNC) : Func.Body ) )
	{
		local( name, S!Func( name, &FUNC ) );
	}
	//
	void entry( alias FUNCTOR )( dstring class_name ) if( is( FUNCTOR :  FuncBase ) )
	{
		auto f = new FUNCTOR();
		f.class_name = class_name;
		local( f.name, SExp( f ) );
	}
	//
	void entry( alias TYPE )( dstring name ) if( is( TYPE : AddressPart ) && !is( TYPE : FuncBase ) )
	{
		local( name, S!TYPE() );
	}

	//--------------------------------------------------------------------
	// mixin用
	// 中身の SymbolSeed を変数として宣言する。
	// Lispコード中の変数名をそのまま使うと D言語的には非合法かもしれないので別途固有名を与える。
	dstring toDefinizer() @property
	{
		if( 0 == symbols.length ) return "";

		Appender!dstring result;
		result.put( "SymbolSeed " );
		bool first = true;
		foreach( one ; symbols )
		{
			if( !one.instanced ) continue;
			if( first ) first = false;
			else result.put( ", " );
			result.put( one.id );
		}
		result.put( ";" );
		return result.data;
	}
	// 初期化関数内で呼び出す用。
	dstring toInitializer() @property
	{
		if( 0 == symbols.length ) return "";

		Appender!dstring result;
		foreach( key, one ; symbols )
		{
			if( !one.instanced ) continue;
			result.put( "/*" );
			result.put( key );
			result.put( "*/" );
			result.put( one.id );
			result.put( " = " );
			result.put( one.toInitializer );
			result.put( ";\n" );
		}
		// SymbolSeed.value は後でまとめて代入する。
		foreach( one ; symbols )
		{
			if( !one.instanced ) continue;
			result.put( one.id );
			result.put( ".value = " );
			result.put( one.value.toInitializerAll );
			result.put( ";\n" );
		}
		return result.data;
	}
}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// パース/実行
class KLispCore
{
	SExp program;

	this( IKLispToken kt, SymbolStore ss )
	{
		SExpAppender acc;
		SExpRewriter prev;

		/// kt 先頭から一つの式を変換する。その度 kt は縮む。
		SExp parse()
		{
			SExp s;
			Token token;
			try
			{
				token = kt.nextToken;

				if     ( Token.TYPE.NULL == token.type || Token.TYPE.EOF == token.type ) { }
				else if( Token.TYPE.CLOSE_BRACKET == token.type ) { }
				else if( Token.TYPE.OPEN_BRACKET == token.type )
				{
					SExpAppender acc;
					kt.incNest;
					for( ; acc.put( parse ) ; ){ }
					s = SExp( new List( acc.data ) );
					kt.decNest;
				}
				else if( Token.TYPE.INT == token.type ) s = S!Int( token.value.to!int );
				else if( Token.TYPE.FLOAT == token.type ) s = S!Double( token.value );
				else if( Token.TYPE.STRING == token.type ) s = S!Dstr( token.value.idup );
				// シンボル名
				else
				{
					s = ss[ kt.filename, token.line, token.value.idup ];
					// FuncBase 型のシンボルだった場合は特殊パーサを呼び出す。
					auto func = cast(FuncBase)(s.car.address);
					if( null !is func )
					{
						auto se = func.filter( prev.data, ss, ()=>parse() );
						// s.cdr = new SExp( se ); // だと CTFE でこける
						if( !se.empty ) s.cdr = new SExp( se.address, se.cdr );
					}
				}
			}
			catch( KLispMessage m ) throw new KLispException( kt.filename, token.line, token.value, m.msg );

			prev.put( s );
			return s;
		}
		for( ; acc.put( parse ) ; ){ }
		program = acc.data;
	}
	
	SExp eval()
	{
		auto ei = new EvalInfo;
		return ei.evalAllChild( program );
	}
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Run time
class RTKLisp( alias FILE_PARSER, alias TOKEN_PARSER, alias ENTRY_CODE )
	if( is( FILE_PARSER : IKLispFile ) && is( TOKEN_PARSER : IKLispToken ) )
{
	KLispCore core;
	this(STRING)( STRING filename )
	{
		auto ss = new SymbolStore;
		ENTRY_CODE( ss );
		auto f = new FILE_PARSER( filename );
		auto t = new TOKEN_PARSER( f );
		core = new KLispCore( t, ss );
	}
	SExp eval(){ return core.eval; }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Compile time
class CTKLisp( string filename, alias FILE_PARSER, alias TOKEN_PARSER, alias ENTRY_CODE )
	if( is( FILE_PARSER : IKLispFile ) && is( TOKEN_PARSER : IKLispToken ) )
{
	SExp program;

	static dstring _mix()
	{
		auto s = new SymbolStore;
		ENTRY_CODE( s );
		auto f = new FILE_PARSER( filename, import(filename).to!dstring );
		auto t = new TOKEN_PARSER( f );
		auto core = new KLispCore( t, s );

		auto result = appender( s.toDefinizer );
		result.put( "\nthis(){\n" );
		result.put( s.toInitializer );
		result.put( "\nprogram = " );
		result.put( core.program.toInitializerAll );
		result.put( ";\n}\n" );
		return result.data;
	}

	mixin( _mix() );

	SExp eval()
	{
		auto ei = new EvalInfo;
		return ei.evalAllChild( program );
	}

	debug static dstring _mix_code = _mix();
	debug static dstring dump(){ return _mix_code; }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Inline Mode
dstring InlineKLisp( alias FILE_PARSER, alias TOKEN_PARSER, alias ENTRY_BLOCK, dstring code )()
{
	auto s = new SymbolStore( SymbolStore.SCOPE_MODE.INLINE );
	ENTRY_BLOCK( s );
	auto f = new FILE_PARSER( code );
	auto t = new TOKEN_PARSER( f );
	auto core = new KLispCore( t, s );

	auto result = appender( "(){"d );
	result.put( s.toDefinizer );
	result.put( s.toInitializer );
	result.put( "\nreturn (new EvalInfo()).evalAllChild(" );
	result.put( core.program.toInitializerAll );
	result.put( ");}();" );
	return result.data;
}