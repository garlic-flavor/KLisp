inline int x_A(x,y) { return x + y; }
inline int x_B(x,y) { return x + y*2; }
inline int x_C(x,y) { return x*2 + y; }

inline int y_A(x,y) { return x + y; }
inline int y_B(x,y) { return x + y*4; }
inline int y_C(x,y) { return x*4 + y; }
void function_x_A_y_A()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_A(x,y) * FUNC_y_A(x,y);
		}
}
void function_x_B_y_A()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_B(x,y) * FUNC_y_A(x,y);
		}
}
void function_x_C_y_A()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_C(x,y) * FUNC_y_A(x,y);
		}
}
void function_x_A_y_B()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_A(x,y) * FUNC_y_B(x,y);
		}
}
void function_x_B_y_B()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_B(x,y) * FUNC_y_B(x,y);
		}
}
void function_x_C_y_B()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_C(x,y) * FUNC_y_B(x,y);
		}
}
void function_x_A_y_C()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_A(x,y) * FUNC_y_C(x,y);
		}
}
void function_x_B_y_C()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_B(x,y) * FUNC_y_C(x,y);
		}
}
void function_x_C_y_C()
{
	for(int y = 0; y<10; ++y)
		for(int x = 0; x<10; ++x)
		{
			FUNC_x_C(x,y) * FUNC_y_C(x,y);
		}
}
  n2 = 0;
  bb = BB_BPAWN;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = f_pawn + sq;
    list2[n2]    = e_pawn + Inv(sq);
    score += kkp[sq_bk0][sq_wk0][ kkp_PAWN + sq ];
    nlist += 1;
    n2    += 1;
  }

  bb = BB_WPAWN;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = e_pawn + sq;
    list2[n2]    = f_pawn + Inv(sq);
    score -= kkp[sq_bk1][sq_wk1][ kkp_pawn + Inv(sq) ];
    nlist += 1;
    n2    += 1;
  }
  for ( i = 0; i < n2; i++ ) { list1[nlist-i-1] = list2[i]; }
  n2 = 0;
  bb = BB_BLANCE;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = f_lance + sq;
    list2[n2]    = e_lance + Inv(sq);
    score += kkp[sq_bk0][sq_wk0][ kkp_LANCE + sq ];
    nlist += 1;
    n2    += 1;
  }

  bb = BB_WLANCE;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = e_lance + sq;
    list2[n2]    = f_lance + Inv(sq);
    score -= kkp[sq_bk1][sq_wk1][ kkp_lance + Inv(sq) ];
    nlist += 1;
    n2    += 1;
  }
  for ( i = 0; i < n2; i++ ) { list1[nlist-i-1] = list2[i]; }
  n2 = 0;
  bb = BB_BKNIGHT;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = f_knight + sq;
    list2[n2]    = e_knight + Inv(sq);
    score += kkp[sq_bk0][sq_wk0][ kkp_KNIGHT + sq ];
    nlist += 1;
    n2    += 1;
  }

  bb = BB_WKNIGHT;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = e_knight + sq;
    list2[n2]    = f_knight + Inv(sq);
    score -= kkp[sq_bk1][sq_wk1][ kkp_knight + Inv(sq) ];
    nlist += 1;
    n2    += 1;
  }
  for ( i = 0; i < n2; i++ ) { list1[nlist-i-1] = list2[i]; }
  n2 = 0;
  bb = BB_BSILVER;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = f_silver + sq;
    list2[n2]    = e_silver + Inv(sq);
    score += kkp[sq_bk0][sq_wk0][ kkp_SILVER + sq ];
    nlist += 1;
    n2    += 1;
  }

  bb = BB_WSILVER;
  while ( BBToU(bb) ) {
    sq = FirstOne( bb );
    Xor( sq, bb );

    list0[nlist] = e_silver + sq;
    list2[n2]    = f_silver + Inv(sq);
    score -= kkp[sq_bk1][sq_wk1][ kkp_silver + Inv(sq) ];
    nlist += 1;
    n2    += 1;
  }
  for ( i = 0; i < n2; i++ ) { list1[nlist-i-1] = list2[i]; }
