/**
 * Version:      0.002(dmd2.060)
 * Date:         2012-Nov-28 15:55:35
 * Authors:      KUMA
 * License:      CC0
*/
/* ファイルを開き、UTF-32で1文字づつ切り出す。
 * 対応している文字コードは sworks.compo.util.sequential_file に依存する。
 */
module sworks.klisp.klisp_file;

import std.algorithm, std.array, std.ascii, std.conv, std.range, std.stdio, std.utf;
import sworks.compo.util.sequential_file;

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
	dchar peek() @property;
	const(dchar)[] peek_cache( size_t );
	dchar chomp(); // キャッシュ先頭の内容を返し、キャッシュを1字進める。括弧が処理される
	dchar discard( size_t s = 1 ); // キャッシュをs字進め、次の1字を返す。括弧が考慮されない。

	// ちょこっとメモしておける。
	void push( dchar dc );
	const(dchar)[] buffer() @property const;
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
	private SequentialFile _file;
	private dchar _peeking_char;

	private Appender!dstring _buffer;
	private Appender!(dchar[]) _nest;

	// UTF-8 文字列を渡した場合はファイル名であると判断する。
	this( string f, ENCODING code = ENCODING.NULL )
	{
		this._file = f.getSequentialFile( code );
	}

	// UTF-32 文字列を渡した場合はファイルの中身であると判断する。
	this( dstring cache ){ this._file = new DstringBuffer( cache ); }

	string filename() @property const{ return _file.filename; }
	bool eof() @property const { return _file.eof; }
	size_t line() @property const { return _file.line; }
	bool newline() @property const { return _file.newline; }
	dchar peek() @property { return _file.peek; }
	const(dchar)[] peek_cache( size_t s ) { return _file.peek_cache( s ); }

	// 括弧の種類の対応、括弧の深度などがチェックされる。
	dchar chomp()
	{
		auto d = _file.peek;
		int i;
		if     ( '\0' == d && 0 < _nest.data.length )
		{
			throw new KLispException( _file.filename, _file.line, ""d
				, "式の途中でファイルが終わりました。閉じカッコ\"" ~ _nest.data.retro.to!dstring
				  ~ "\"が足りません。" );
		}
		else if( 0 <= ( i = BRACKET.countUntil(d) ) )
		{
			if( i & 1 ) // 閉じ括弧
			{
				if( 0 == _nest.data.length )
				{
					throw new KLispException( _file.filename, _file.line, [d], "閉じカッコが多すぎます。"d );
				}

				if( d != _nest.data[ $-1 ] )
				{
					throw new KLispException( _file.filename, _file.line, [d]
					                        , "閉じカッコの種類が合いません。\""d
					                          ~ _nest.data.retro.to!dstring ~ "\"が期待されています。"d );
				}
				_nest.shrinkTo( _nest.data.length - 1 );
			}
			else // 開き括弧
			{
				assert( i+1 < BRACKET.length );
				_nest.put( BRACKET[i+1] );
			}
			d = DEFAULT_BRACKET[ i & 1 ];
		}

		_file.discard;
		return d;
	}

	// カッコの種類/深度は考慮されない。
	// クォートされた文字列内やコメント内でファイルを進める場合はこちら。
	dchar discard( size_t size = 1 ) { return _file.discard( size ); }

	// ちょこっとメモ。
	void push( dchar dc ){ _buffer.put( dc ); }
	const(dchar)[] buffer() @property const { return _buffer.data; }
	void flush() { _buffer.clear; }

	// 0開始の括弧の深度を表わす。
	int nest() @property const { return cast(int)_nest.data.length; }

	void close()
	{
		_buffer.clear;
		_nest.clear;
		_file.close;
		_peeking_char = '\0';
	}
}

