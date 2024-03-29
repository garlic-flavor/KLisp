//% (set outfile 'testout.cpp')
//% (del outfile)
//% (write
inline int x_A(x,y) { return x + y; }
inline int x_B(x,y) { return x + y*2; }
inline int x_C(x,y) { return x*2 + y; }

inline int y_A(x,y) { return x + y; }
inline int y_B(x,y) { return x + y*4; }
inline int y_C(x,y) { return x*4 + y; }
//% )
//% (let list 'x_A' 'x_B' 'x_C')
//% (let list2 'y_A' 'y_B' 'y_C')
//% (foreach e2 list2
//%  (foreach e list ( write
//%   (replace (replace
void function_XXX_YYY()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_XXX(x,y) * FUNC_YYY(x,y);
		}
}
//% 'XXX' e)
//% 'YYY' e2)
//% )))
//
//	Bonanzaの評価関数を書いてみる。
//
//% (let koma 'PAWN' 'LANCE' 'KNIGHT' 'SILVER')
//% (foreach E koma ( (tolower e E) (write (replace ( replace
  n2 = 0;
  bb = BB_BXXXX;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = f_YYYY + sq;
    list2[n2]    = e_YYYY + Inv(sq);
    score += kkp[sq_bk0][sq_wk0][ kkp_XXXX + sq ];
    nlist += 1;
    n2    += 1;
  }

  bb = BB_WXXXX;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = e_YYYY + sq;
    list2[n2]    = f_YYYY + Inv(sq);
    score -= kkp[sq_bk1][sq_wk1][ kkp_YYYY + Inv(sq) ];
    nlist += 1;
    n2    += 1;
  }
  for ( i = 0; i < n2; i++ ) { list1[nlist-i-1] = list2[i]; }
//% 'XXXX' E ) 'YYYY' e ))))

// 最後に評価された式がコンソールに表示されるので、なんぞ入れておく。
//% (get '..done')
