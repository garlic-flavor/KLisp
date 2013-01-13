/**
 * Version:      0.003(dmd2.060)
 * Date:         2013-Jan-14 02:44:54
 * Authors:      KUMA
 * License:      CC0
*/
/* ファイルを開き、UTF-32で1文字づつ切り出す。
 * 対応している文字コードは sworks.compo.util.sequential_file に依存する。
 */
module sworks.klisp.klisp_file;

import std.array, std.algorithm, std.ascii, std.conv, std.range, std.stdio, std.utf;
import sworks.compo.util.sequential_file;
debug import sworks.compo.util.cached_buffer;

/**
 * Kara-Lisp の パース／実行中 に使われる例外
 */
class KLispException : Throwable
{
	string msg;
	/*
	 * Params:
	 *   filename = 問題が起きた対象ファイル名。
	 *   line_num = 問題が起きた対象ファイル内での行数。
	 *   cont     = 問題の箇所
	 *   msg      = メッセージ
	 */
	this( string filename, size_t line_num, const(dchar)[] cont, dstring msg
	    , string source_filename = __FILE__, int line = __LINE__ )
	{
		super( "KLispException", source_filename, line );
		this.msg = newline ~ filename ~ " を解析中に問題が発生しました。" ~ newline ~ line_num.to!string
		       ~ " 行目 : 問題の箇所\"" ~ cont.toUTF8 ~ "\"" ~ newline ~ msg.to!string ~ newline;
	}
	string toString() @property { return msg; }
	string stack_trace() @property { return super.toString; }
}

// メッセージにスタックトレースを含めない例外。
// ※ dmd のバグで、含めてると toString 時に(シンボルのデマングル失敗 -> Unicode 外の文字が混じるで)こけるから。
class KLispMessage : Throwable
{
	dstring msg;

	this( dstring msg ) { super( "KLisp Message" ); this.msg = msg; }
	string toString() @property { return msg.to!string; }
	string stack_trace() @property { return super.toString; }
}


// 開きカッコと閉じカッコは複数の種類が使えるが、IKLispFile で読み込んだ場合はこれに変換される。
enum DEFAULT_BRACKET = "()";

interface IKLispFile
{
	string filename() @property const;
	bool eof() @property const;
	size_t line() @property const;
	bool newline() @property const; // 行頭の場合は true
	dchar front() @property;
	const(dchar)[] peek( size_t );

	dchar push(); // キャッシュ先頭の1字を返し、キャッシュを1字進める。括弧が処理される
	dchar discard( size_t s = 1 ); // キャッシュをs字進め、次の1字を返す。括弧が考慮されない。

	// c をスタックに詰み、キャッシュを1字進める。
	dchar push( dchar c );
	const(dchar)[] stack() @property const;
	void flush();

	int nest() @property const; // 0開始で括弧の深度を表す
	void close();
}

/*
 * 有効な KLisp ファイルから一文字ずつ読み込む。
 * 現在の行数と、行頭かどうか、括弧の深度、を保持する。
 * 括弧が足りない場合、多い場合、括弧の種類が合っていない場合は例外が投げられる。
 *
 * 括弧は dchar 1文字で構成され
 * 開き括弧 BRACKET[2n] に対応する閉じ括弧は BRACKET[2n+1] とする。
 */
class _KLispFile( dstring BRACKET ) : IKLispFile
{
	private SequentialBuffer _file;
	private dchar[] _nest;

	// UTF-8 文字列を渡した場合はファイル名であると判断する。
	this( string f, ENCODING code = ENCODING.NULL, size_t cache_size = 1024 )
	{
		this._file = f.getSequentialBuffer( code, cache_size );
	}

	// UTF-32 文字列を渡した場合はファイルの中身であると判断する。
	this( dstring cache ){ this._file = cache.getSequentialBuffer; }

	string filename() @property const{ return _file.filename; }
	bool eof() @property const { return _file.eof; }
	size_t line() @property const { return _file.line; }
	bool newline() @property const { return _file.isNewLine; }
	dchar front() @property const { return _file.front; }
	const(dchar)[] peek( size_t s ) { return _file.peek( s ); }

	// カッコの種類/深度は考慮されない。
	// クォートされた文字列内やコメント内でファイルを進める場合はこちら。
	dchar discard( size_t size = 1 ) { return _file.popFront( size ); }

	// 括弧の種類の対応、括弧の深度などがチェックされる。
	private dchar _check_bracket( dchar d )
	{
		int i;
		if     ( dchar.init == d && 0 < _nest.length )
		{
			throw new KLispException( _file.filename, _file.line, ""d
				, "式の途中でファイルが終わりました。閉じカッコ\"" ~ _nest.retro.to!dstring
				  ~ "\"が足りません。" );
		}
		else if( 0 <= ( i = BRACKET.countUntil(d) ) )
		{
			if( i & 1 ) // 閉じ括弧
			{
				if( 0 == _nest.length )
				{
					throw new KLispException( _file.filename, _file.line, [d], "閉じカッコが多すぎます。"d );
				}

				if( d != _nest[ $-1 ] )
				{
					throw new KLispException( _file.filename, _file.line, [d]
					                        , "閉じカッコの種類が合いません。\""d
					                          ~ _nest.retro.to!dstring ~ "\"が期待されています。"d );
				}
				_nest = _nest[ 0 .. $ - 1 ];
			}
			else // 開き括弧
			{
				assert( i+1 < BRACKET.length );
				_nest ~= BRACKET[ i + 1 ];
			}
			d = DEFAULT_BRACKET[ i & 1 ];
		}
		return d;
	}

	// カーソルを進めて1字スタックに積む
	dchar push()
	{
		auto d = _check_bracket( _file.front );
		_file.push(d);
		return d;
	}
	dchar push( dchar c ) { _file.push( c ); return c; }

	const(dchar)[] stack() @property const { return _file.stack; }
	void flush() { _file.flush; }

	// 0開始の括弧の深度を表わす。
	int nest() @property const { return cast(int)_nest.length; }

	void close()
	{
		_nest = null;
		_file.close;
	}

	debug Benchmark getBenchmark() @property const { return _file.getBenchmark; }
}

debug(klisp_file)
{
	import sworks.compo.util.output;

	void main()
	{
		try
		{
			auto ef = new _KLispFile!"()"( "HELLO WORLD\r\n"d );
			for( auto d = ef.front ; !ef.eof ; d = ef.push ) Output( d );
			ef.close;
		}
		catch( Throwable t ) Output.ln( t.toString );
	}
}

debug( ct_klisp_file )
{
	import sworks.compo.util.output;

	string func1( dstring cont )
	{
		Appender!dstring result;
		auto ef = new _KLispFile!"()"( cont );
		for( ; !ef.eof ; ) result.put( ef.push );
		ef.close;
		return result.data.to!string;
	}

	void main()
	{
		mixin( func1( "Output.ln( \"good-bye heaven\" ); "d ) );
	}
}