はじめにお読み下さい。 - KLISP -
========================================
これは、独自の Lisp like 言語の実装を容易にするためのライブラリです。


謝辞
------------------------------
- [D言語]( http://www.kmonos.net/alang/d/ "D PROGRAMMING LANGUAGE" ) で書かれています。
- [YaneLisp]( http://labs.yaneu.com/20090905/ "YaneLisp" ) を参考にしています。


仕様
------------------------------
Kara-Lisp は言語の基礎機能のみを提供します。それ以外は全て拡張の形で実装します。

- lisp ソースコードは UTF-8、UTF-16、UTF-32 で書かれているものとします。
- 内部で文字列は UTF-32 で扱われます。
- 文字列内では、`"\t"`、`"\r"`、`"\n"` のエスケープシーケンスが使えます。それ以外のエスケープ文字はそのまま出力されます。
- およそ、整数に見える表記は 32bit signed int として扱われます。
- 浮動小数点数に見える表記は 64bit float として扱われます。
- それ以外は全て変数名と見なされます。日本語も使えます。

拡張は、sworks.klisp.lisp.Func.Body 型の関数を定義するか、sworks.klisp.lisp.FuncBase クラスを
継承したクラスを定義することで行います。
詳細は sworks.klisp.lisp.d、sworks.klisp.core_kl.d を参照して下さい。


src/sworks/klisp/yane_kl.d
------------------------------
[YaneLisp]( http://labs.yaneu.com/20090905/ "YaneLisp" ) の仕様への準拠を目指しています。
一応、unittest は通るものの、若干の仕様の違いが確認されています。

- func 関数で定義する関数の引数は @0 〜 @9 までしか使えません。
  @params に全引数のリストが格納されるので、@10 以降はこちらを使って下さい。



ライセンス
------------------------------
[CC0]( http://creativecommons.org/publicdomain/zero/1.0/legalcode "Creative Commons 0 License" )


更新履歴
------------------------------
- 2013/01/13 ver. 0.003

	なんちゃって CTFE。

- 2012/11/28 ver. 0.002

	全面書き直し。github デビュー。YaneLispなんちゃって準拠

- 2011/08/30 ver. 0.001

  first release
