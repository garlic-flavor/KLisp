/** 空のLisp-like言語の実装。
 * Version:      0.003(dmd2.060)
 * Date:         2013-Jan-14 02:44:54
 * Authors:      KUMA
 * License:      CC0
 */
module sworks.klisp.lisp;

import std.array, std.string, std.exception, std.conv, std.file, std.math;
import sworks.compo.util.output;
import sworks.klisp.klisp_file;
private import sworks.klisp.token;
debug import std.stdio;

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
	debug int i = 0;
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

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// address の具体的な中身

//------------------------------------------------------------------------------
// 未定義
class Undef : AddressPart { }

//------------------------------------------------------------------------------
// 真
class T : AddressPart
{
	override dstring toDstring() @property { return "#t"d; }
	override bool toBool() @property { return true; }
	override int toInt() @property { return 1; }
	override double toDouble() @property { return 1.0; }
}

//------------------------------------------------------------------------------
// 偽
class Nil : AddressPart
{
	override dstring toDstring() @property { return "#nil"d; }
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
}

//------------------------------------------------------------------------------
// 浮動小数点数 64bit。
class Double : AddressPart
{
	double value;
	this( double d ) { this.value = d; }
	override dstring toDstring() @property { return to!dstring( value ); }
	override int toInt() @property { return cast(int)value; }
	override bool toBool() @property { return double.nan !is value; }
	override double toDouble() @property { return value; }
}

//------------------------------------------------------------------------------
// UTF-32文字列
class Dstr : AddressPart
{
	dstring value;
	this( dstring dstr ) { this.value = dstr; }
	override dstring toDstring() @property { return value; }
	override int toInt() @property
	{
		int v; collectException( value.to!int, v );
		return v;
	}
	override bool toBool() @property
	{
		return 0 < value.length;
	}
	override double toDouble() @property
	{
		double v; collectException( value.to!double, v );
		return v;
	}
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
}

//------------------------------------------------------------------------------
// シンボル型。SymbolScope.SymbolRoot.getInstance で生成される。
// 中身の本体は生成元の SymbolScope.SymbolRoot が保持している。
class Symbol : AddressPart
{
	string filename; // このシンボルが記述されていたファイル名
	size_t line;     // このシンボルが登場した行数
	dstring name;
	SymbolScope.SymbolRoot root; // 中身

	this( string filename, size_t line, dstring name, SymbolScope.SymbolRoot root )
	{
		assert( root );

		this.filename = filename;
		this.line = line;
		this.name = name;
		this.root = root;
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
}

//------------------------------------------------------------------------------
// D言語側で中身を提供する関数型
private class Func : AddressPart
{
	// 簡易な定義済み関数の中身。
	// この場合、SymbolScope にアクセスできない。そういう用途には FuncBase を継承する形で実装する。
	alias SExp function( EvalInfo ei ) Body;

	dstring name;
	Body _func;

	this( dstring name, Body f )
	{
		assert( f );
		this.name = name;
		this._func = f;
	}

	override SExp eval( EvalInfo ei )
	{
		assert( _func );
		return _func( ei );
	}
	override dstring toDstring() @property { return "#"d ~ name; }
}

//------------------------------------------------------------------------------
// 関数型に共通の機能を提供する。
abstract class FuncBase : AddressPart
{
	dstring name;
	alias SExp delegate(SymbolScope) Parser;

	this( dstring name ) { this.name = name; }

	// パース時に呼ばれる。自分の直後以降のS式にアクセスできる。
	// SymbolScope を切り変えて parser を呼び出すことで、シンボルの解決方法を制御できる。
	SExp filter( SymbolScope parent_ss , Parser parser ) { return SExp(); }

	override dstring toDstring() @property { return "#"d ~ name; }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// シンボル名解決
// シンボル名はパース時に解決しておく。その為、ちょっと可読性下ってるかも。
class SymbolScope
{
	// シンボル本体
	private class SymbolRoot
	{
		private dstring name;
		private SExp value;

		enum MAX_ATTACH = 1024;
		private size_t semaphore; // 参照数をカウントし、循環参照を検出する。

		this( dstring name, SExp v = SExp() )
		{
			this.name = name;
			this.value = v.empty ? S!Undef : v;
			semaphore = 0;
		}

		void attach()
		{
			if( MAX_ATTACH < semaphore++ ) throw new KLispMessage( "シンボル参照の深度が深すぎます。" );
		}
		void detach() { assert( 0 < semaphore ); semaphore--; }

		SExp getInstance( string filename, size_t line )
		{
			return SExp(new Symbol( filename, line, name, this ));
		}
	}

	// シンボルが見つからなかった場合、どこに新しいシンボルを確保するか？
	enum DEFAULT_MODE
	{
		LOCAL,  // ローカルスコープのみ
		GLOBAL, // ローカルスコープとグローバルスコープの両方に同じインスタンスを確保する。
	}

/*	private */ SymbolRoot[dstring] symbols;
	SymbolScope parent;
	DEFAULT_MODE mode;

	this( SymbolScope parent = null, DEFAULT_MODE dm = DEFAULT_MODE.GLOBAL )
	{
		this.parent = parent;
		this.mode = dm;
	}

	// 親スコープまでシンボルを探しにいく。
	SExp opIndex( string filename, size_t line, const(dchar)[] name )
	{
		SymbolScope r;
		SymbolRoot s;
		for( auto ite = this ; null !is ite ; ite = ite.parent )
		{
			s = ite.symbols.get( cast(dstring)name, null );
			if( null !is s ) return s.getInstance( filename, line );
			if( null is r || r.mode == DEFAULT_MODE.GLOBAL ) r = ite;
		}
		auto iname = name.idup;
		s = new SymbolRoot( iname );
		symbols[ iname ] = s;
		if( mode == DEFAULT_MODE.GLOBAL && null !is r ) r.symbols[ iname ] = s;
		return s.getInstance( filename, line );
	}

	void opIndexAssign( SExp se, dstring name )
	{
		SymbolScope r;
		for( auto ite = this ; null !is ite ; ite = ite.parent )
		{
			auto pse = name in ite.symbols;
			if( null !is pse ) { (*pse) = new SymbolRoot( name, se ); return; }
			if( null is r || r.mode == DEFAULT_MODE.GLOBAL ) r = ite;
		}
		auto s = new SymbolRoot( name, se );
		symbols[ name ] = s;
		if( mode == DEFAULT_MODE.GLOBAL && null !is r ) r.symbols[ name ] = s;
	}

	// ローカルのシンボルに対象を限定して探す。
	bool have( dstring name ){ return null !is ( name in symbols ); }
	SExp local( string filename, size_t line, const(dchar)[] name )
	{
		auto pse = name in symbols;
		if( null !is pse ) return pse.getInstance( filename, line );
		auto s = new SymbolRoot( name.idup );
		symbols[ name ] = s;
		return s.getInstance( filename, line );
	}
	void local( dstring name, SExp se ) { symbols[ name ] = new SymbolRoot( name, se ); }

	// スコープのルートを返す。
	SymbolScope global() @property
	{
		for( auto ite = this ; ; ite = ite.parent ) if( null is ite.parent ) return ite;
		return null;
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
			// 意味不なマングル名が混入するため。
			static if     ( !__traits( compiles, __traits(getMember, MODULE, SYMBOL ) ) ) { }
			else static if( is( typeof(&__traits( getMember, MODULE, SYMBOL )) : Func.Body ) )
			{
				entry!(__traits( getMember, MODULE, SYMBOL ))( SYMBOL.to!dstring );
			}
			else static if( IsBaseClassOf!( __traits( getMember, MODULE, SYMBOL ), FuncBase ) )
			{
				entry!(__traits( getMember, MODULE, SYMBOL ))();
			}
			else static if( is( typeof(__traits( getMember, MODULE, SYMBOL )) : AddressPart ) )
			{
				entry!(typeof(__traits( getMember, MODULE, SYMBOL )))( SYMBOL );
			}
		}
	}

	// 個別に追加
	void entry( alias FUNC )( dstring name ) if( is( typeof(&FUNC) : Func.Body ) )
	{
		local( name, S!Func( name, &FUNC ) );
	}

	//
	void entry( alias FUNCTOR )() if( is( FUNCTOR :  FuncBase ) )
	{
		auto f = new FUNCTOR();
		local( f.name, SExp( f ) );
	}

	//
	void entry( alias TYPE )( dstring name ) if( is( TYPE : AddressPart ) )
	{
		local( name, S!TYPE() );
	}

}


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// IKLispFile のパース

/// kt 先頭から一つの式を変換する。その度 kt は縮む。
SExp parse( IKLispToken kt, SymbolScope ss )
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
			for( ; acc.put( kt.parse( ss ) ) ; ){ }
			s = SExp( new List( acc.data ) );
			kt.decNest;
		}
		else if( Token.TYPE.INT == token.type ) s = S!Int( token.value.to!int );
		else if( Token.TYPE.FLOAT == token.type ) s = S!Double( token.value.to!double );
		else if( Token.TYPE.STRING == token.type ) s = S!Dstr( token.value.to!dstring );
		// シンボル名
		else
		{
			s = ss[ kt.filename, token.line, token.value ];
			// FuncBase 型のシンボルだった場合は特殊パーサを呼び出す。
			auto func = cast(FuncBase)(s.car.address);
			if( null !is func )
				s.cdr = new SExp(func.filter( ss, fs=>kt.parse( fs ) ));
		}
	}
	catch( KLispMessage m ) throw new KLispException( kt.filename, token.line, token.value, m.msg );

	return s;
}

// パースし直ちに評価する。
SExp eval( IKLispToken kt, SymbolScope ss )
{
	SExpAppender acc;
	for( ; acc.put( kt.parse( ss ) ); ){ }
	auto ei = new EvalInfo;
	return ei.evalAllChild( acc.data );
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// CTFE
class CTParser( alias TOKEN_FILTER )
{
	
}