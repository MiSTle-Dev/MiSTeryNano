//
// FX ST Blitter
// Copyright (c) 2019,2021 by Jorge Cwik
//

`timescale 1 ns / 1 ns

// `define BLIT_TEST

typedef struct {
	logic clk;
	logic aRESETn;		// Async neg reset on FPGA reset	
	logic sReset;		// Sync reset on emulated system
	logic extReset;		// Only external	
	logic pwrUp;		// Asserted together with sReset on coldstart
	
	logic enPhi1, enPhi2;	// Clock enables. Next cycle is PHI1 or PHI2
	logic anyPhi;			// Next cycle is either PHI1 or PHI2. Might be always true if clock 2x
	logic phi1, phi2;		// In PHI1 or PHI2 phase
} blt_clks;

localparam REG_00 = 0;
localparam REG_02 = 2/2;
localparam REG_04 = 4/2;
localparam REG_06 = 6/2;
localparam REG_08 = 8/2;
localparam REG_0A = 10/2;
localparam REG_0C = 12/2;
localparam REG_0E = 14/2;
localparam REG_10 = 16/2;
localparam REG_12 = 18/2;
localparam REG_14 = 20/2;
localparam REG_16 = 22/2;
localparam REG_18 = 24/2;
localparam REG_1A = 26/2;
localparam REG_1C = 28/2;

module stBlitter(
`ifdef BLT_CLKS_STRUCT
		  input	       blt_clks Clks,
`else
          input        clk,
          input        aRESETn,
          input        pwrUp,
          
          input        enPhi1,
          input        enPhi2,
`endif
		  input	       ASn, RWn, LDSn, UDSn,
		  input	       FC0, FC1, FC2,
		  input	       BERRn, iDTACKn,
		  output       ctrlOe, dataOe, oASn, oDSn, oRWn, oDTACKn,
		  output       selected, // System selects us as output mux

		  input	       iBRn, BGIn,
		  input	       iBGACKn, // GLUE output, or optionally additional bus masters.
		  output       oBRn, oBGACKn,
		  output       INTn, BGOn,
		  input [15:0] dmaInput, // Separated DMA input might benefit some cores.
			
		  input [23:1] iABUS, output [23:1] oABUS, 
		  input [15:0] iDBUS, output [15:0] oDBUS);

 `ifndef BLT_CLKS_STRUCT
    blt_clks Clks;

    assign Clks.clk = clk;
    assign Clks.aRESETn = aRESETn;
    assign Clks.sReset = (pwrUp | !aRESETn);
    assign Clks.pwrUp = pwrUp;

    assign Clks.enPhi1 = enPhi1;
    assign Clks.enPhi2 = enPhi2;
    assign Clks.anyPhi = enPhi2 | enPhi1;

    assign { Clks.extReset, Clks.phi1, Clks.phi2} = 3'b000;
`endif       
    
	wire blitSpace = { iABUS[23:6], 6'b0} == 24'hFF8A00;				// Space: FF8A00 - FF8A3F
        // FC[2:0] == 101: supervisor data
	assign selected = ({ FC2, FC1, FC0 } == 3'b101) & !ASn & blitSpace;
	wire wrWordSel = selected & !RWn & !LDSn & !UDSn;
	wire ramWrSel = wrWordSel & !iABUS[5];
	wire ramSel = selected & !iABUS[5];
		
	logic [15:0] SEL;
	always_comb begin
		logic [4:1] iSel;
		for( int i = 0; i < 16; i++) begin
			iSel = i;
			SEL[i] = selected & iABUS[5] & (iABUS[4:1] == iSel);
		end
	end	
	
	// DTACK output is originally combinational on CS.
	// CS is any address in range + AS + FC == 3'b101. LDS/UDS don't matter
	assign oDTACKn = !selected;
	
	wire [15:0] ramOut;
	

	logic busOwned;					// DIP We have bus ownership.
	wire extDmaReq;					// Request to yield
	wire enIas;						// Next cycle is S2
	wire negIas;					// Next cycle is trailing edge of internal AS (S7)
	wire enS0, enS5;				// Next cycle is S0, S5
	wire rBltReset;
	wire wantDma;
	wire updSrc, updDst;			// Update source/dest registers
	wire writeCycle, srcCycle, xtraSrcCycle;
	wire nxtLineCycle;				// Last clock cycle this line (current AS trailing edge)
	wire nfsrCycle;					// NFSR active. Perform dummy read and extra shift
	wire busOe;
	assign ctrlOe = busOe;
	
	wire XC1, XC2, XYZ;
	wire Direction, IncSign;
	wire forceDestRd;				// Next cycle has at least one masked bit. Must read destination
	
	wire updCycle = negIas;			// Update most counters here, at S6/S7 edge
	
	// Data bus input latch. Needed for NFSR.
	reg [15:0] dbusLatch;
	always_ff @(posedge Clks.clk) begin
		if( negIas)			dbusLatch <= dmaInput;
	end
	
	reg rBusy;
	reg [3:0] OP;
	reg [1:0] HOP;
	reg [3:0] Skew;
	reg [3:0] LineCtr;				// LINE counter
	reg Fxsr, Nfsr;
	reg Smudge, Hog;
	
	reg [15:1] srcXincr; reg [15:1] srcYincr;
	reg [15:1] dstXincr; reg [15:1] dstYincr;
	reg [15:0] lEndMask;	reg [15:0] cEndMask;	reg [15:0] rEndMask;
		
	logic [23:1] srcAddr;
	logic [23:1] dstAddr;
	logic [15:0] xCounter;
	logic [15:0] yCounter;
		
	wire [15:0] bltOut;
	wire [15:0] skewed;
	
	wire csRdSel = selected & RWn & (!LDSn | !UDSn);

	// I/O Read mux
		
	logic [15:0] ioOut;
	always_comb begin
	case( iABUS[4:1])
	4'h0:		ioOut = { srcXincr, 1'b0};
	4'h1:		ioOut = { srcYincr, 1'b0};
	4'h2:		ioOut = { 8'h0, srcAddr[23:16]};
	4'h3:		ioOut = { srcAddr[15:1], 1'b0};
	4'h4:		ioOut = lEndMask;
	4'h5:		ioOut = cEndMask;
	4'h6:		ioOut = rEndMask;
	4'h7:		ioOut = { dstXincr, 1'b0};
	4'h8:		ioOut = { dstYincr, 1'b0};
	4'h9:		ioOut = { 8'h0, dstAddr[23:16]};
	4'hA:		ioOut = { dstAddr[15:1], 1'b0};
	4'hB:		ioOut = xCounter;
	4'hC:		ioOut = yCounter;
	4'hD:		ioOut = { 4'h0, 2'b00, HOP, 4'h0, OP};
	4'hE:		ioOut = { rBusy, Hog, Smudge, 1'b0, LineCtr,	Fxsr, Nfsr, 2'b00, Skew};
	4'hF:		ioOut = '0;
	endcase
	end
	
	assign oDBUS = csRdSel ? ( iABUS[5] ? ioOut : ramOut)  : bltOut;
	assign dataOe = csRdSel | (busOwned & writeCycle);
	
	// Main registers
	
	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp) begin
			{ srcXincr, srcYincr} <= '0;
			{ dstXincr, dstYincr} <= '0;
			lEndMask <= '0;		cEndMask <= '0;		rEndMask <= '0;
		end
		
		else if( Clks.enPhi1 & wrWordSel) begin
			if( SEL[REG_00])		srcXincr <= iDBUS[15:1];
			if( SEL[REG_02])		srcYincr <= iDBUS[15:1];
			if( SEL[REG_0E])		dstXincr <= iDBUS[15:1];
			if( SEL[REG_10])		dstYincr <= iDBUS[15:1];
			
			if( SEL[REG_08])		lEndMask <= iDBUS;
			if( SEL[REG_0A])		cEndMask <= iDBUS;		
			if( SEL[REG_0C])		rEndMask <= iDBUS;		
		end
	end		
		
	// Update force dest read logic if endmask changed.
	reg maskChanged;
	always_ff @(posedge Clks.clk) begin
		if( Clks.enPhi1)
			maskChanged <= wrWordSel & (SEL[REG_08] | SEL[REG_0A] | SEL[REG_0C]);
	end
	
	//
	// Misc user registers
	//
	wire [3:0] ramIdx;				// Ram index for BLIT OP
	
	// BUSY is always deasserted while being written ! This will even toggle INTn if Blitter still busy
	
	wire ctrlWr = SEL[REG_1C] & !RWn & !UDSn;
	wire busyMask = !ctrlWr;
	wire busy = rBusy & busyMask;
	assign INTn = busy;

	always_ff @(posedge Clks.clk or posedge XYZ) begin
		if( XYZ)					{rBusy, Hog} <= '0;
		else if( Clks.sReset)		{rBusy, Hog} <= '0;
		else if( Clks.enPhi1) begin
			// While writing 
			if( SEL[REG_1C] & !RWn & !UDSn) begin
				rBusy <= iDBUS[15];
				Hog <= iDBUS[14];
			end
		end
	end

	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp)			{ Smudge, LineCtr} <= '0;
		else if( Clks.enPhi1 & ctrlWr) begin
			LineCtr <= iDBUS[11:8];
			Smudge <= iDBUS[13];
		end
		else if( nxtLineCycle)
			LineCtr <= IncSign ? LineCtr - 1'b1 : LineCtr + 1'b1;		
	end	
	assign ramIdx = Smudge ? skewed[ 3:0] : LineCtr;

	reg skewWr;
	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp) begin
			{ HOP, OP, Fxsr, Nfsr, Skew} <= '0;
		end
		else if( Clks.enPhi1 & !RWn) begin
			if( SEL[REG_1A] & !UDSn)		HOP <= iDBUS[9:8];
			if( SEL[REG_1A] & !LDSn)		OP <= iDBUS[3:0];
			
			if( SEL[REG_1C] & !LDSn) begin
				{ Fxsr, Nfsr} <= iDBUS[7:6];
				Skew <= iDBUS[3:0];
			end
		end

		if( Clks.pwrUp)				skewWr <= '0;
		else if( Clks.enPhi1)		skewWr <= SEL[REG_1C] & !LDSn & !RWn;
	end
	

	/* Non HOG DMA cycle counter. Counts 64 bus cycles (any bus cycles).	
	BLITTER Buglet: Starts counting as soon as BUSY is set.
	*/
	reg [6:0] tmoCntr;
	wire timeOut = tmoCntr[6];
	reg prevAs;
	
	always_ff @( posedge Clks.clk) begin
		// Counts falling/leading edges of AS. Originally AS is used directly as clock		
		if( Clks.anyPhi)		prevAs <= ASn;
		
		if( Clks.anyPhi) begin
			if( !busy)					tmoCntr <= '0;
			else if( !ASn & prevAs)		tmoCntr <= tmoCntr + 1'b1;
		end
	end
	
	
	// Buffers
	reg [31:0] skewRegs = '0;			// Source/skew buffer
	reg [15:0] destBuf = '0;			// Dest latch for rm cycle
	
	wire dstLatchCycle;
	always_ff @( posedge Clks.clk) begin
		if( negIas & dstLatchCycle)
			destBuf <= dmaInput;
			
		if( negIas & srcCycle)
			skewRegs <= !Direction ? { skewRegs[ 15:0], dmaInput} : { dmaInput, skewRegs[ 31:16]};
		
		// Perform NFSR shift/skew as soon as possible for the blit core.
		// Worst case is SMUDGE and NFSR. Shifted data is required for addressing half tone ram
		else if( enS0 & nfsrCycle)
			skewRegs <= !Direction ? { skewRegs[ 15:0], dbusLatch} : { dbusLatch, skewRegs[ 31:16]};

		else if( negIas & nfsrCycle)
			skewRegs <= !Direction ? { skewRegs[ 15:0], bltOut} : { bltOut, skewRegs[ 31:16]};			
	end
	assign skewed = skewRegs >> Skew;		// Might need to register for perfomance !
		
	//
	// Modules
	//

	bltControl bltControl( .Clks, .busy, .Hog, .negIas, .enS5, .extDmaReq, .timeOut, .rBltReset,
		.XC2,.XC1, .OP, .HOP, .Smudge, .Nfsr, .Fxsr, .skewWr, .forceDestRd,
		.busOe, .updSrc, .updDst, .srcCycle, .writeCycle, .nxtLineCycle, .xtraSrcCycle, .nfsrCycle, .dstLatchCycle, .wantDma);

	bltBusCtrl bltBusCtrl( .Clks, .busOe, .wantDma, .iBRn, .BGIn,.iBGACKn, .iASn( ASn), .BERRn, .iDTACKn,
		.busOwned, .extDmaReq, .enIas, .negIas, .enS0, .enS5, .writeCycle, .oASn, .oDSn, .oRWn, .oBRn, .oBGACKn, .BGOn);

	bltCounters bltCounters( .Clks, .SEL, .wrWordSel, .busOwned, .updSrc, .updDst, .updCycle, .srcCycle, .xtraSrcCycle, .Nfsr,
		.srcXincr, .srcYincr, .dstXincr, .dstYincr, .srcAddr, .dstAddr, .xCounter, .yCounter,
		.XC1, .XC2, .XYZ, .rBltReset, .Direction, .IncSign, .iDBUS, .oABUS);

	bltScore bltScore( .Clks, .SEL, .iDBUS, .OP, .HOP, .destBuf, .srcbuf( skewed), 
			.rBltReset, .updCycle, .updDst, .busOwned, .enIas, .XC1, .XC2, .wrWordSel, .maskChanged,
			.lEndMask, .cEndMask, .rEndMask,			
			.ramSel, .ramWrSel, .ramSelIdx( iABUS[4:1]), .ramIdx,
			.ramOut,
			.forceDestRd, .bltOut);
			
`ifdef NEVER
	// Debugging stuff
	(* noprune *) reg [15:0] opCounter;					// Count # of blit ops (busy edges)
	(* noprune *) reg [15:0] busCounter;				// Count bus cycles blitting
	reg prevBusy;
	always @( posedge Clks.clk) begin
		if( Clks.sReset) begin
			{ busCounter, opCounter} <= '0;
			prevBusy <= '0;
		end
		else begin
			prevBusy <= rBusy;
			if( rBusy & !prevBusy)		opCounter <= opCounter + 1'b1;
			if( negIas)					busCounter <= busCounter + 1'b1;
		end
	end
`endif
							
endmodule

// DMA & bus interface control
module bltBusCtrl( input blt_clks Clks, input wantDma, busOe,
			input writeCycle,
			input iBRn, iASn, BGIn, iBGACKn, BERRn, iDTACKn,
			output logic oASn, oDSn, oRWn,
			output logic oBRn, oBGACKn, BGOn,
			output logic busOwned, extDmaReq, enIas, negIas, enS0, enS5);
			
	
	//		
	// Bus control output when having bus ownership
	//
	
	enum int unsigned { S0 = 0, S2, S4, S6} busState;
	
	reg rDtack, rBerr;
	always_ff @(posedge Clks.clk) begin
		if( Clks.enPhi2) begin
			rDtack <= iDTACKn;
			rBerr <= BERRn;			
		end
	end	
	wire busEnd = !rBerr | !rDtack | !busOe;
	
	always_ff @(posedge Clks.clk) begin
		if( Clks.sReset)		busState <= S0;
		else if( !busOwned)		busState <= S0;
		else if( Clks.enPhi1)
		case( busState)
		S0:						busState <= S2;
		S2:						busState <= S4;
		S4:		if( busEnd)		busState <= S6;
		S6:						busState <= S0;
		endcase		
	end

	always_ff @(posedge Clks.clk) begin
		if( Clks.sReset | !busOwned)		{oASn, oDSn, oRWn} <= '1;
		else if( Clks.enPhi1) begin
			if( busState == S0)			oASn <= 1'b0;
			
			if( ( (busState == S0) & !writeCycle) | ( busState == S2))
				oDSn <= 1'b0;
				
			if( busState == S0)			oRWn <= !writeCycle;
			else if( busState == S6)	oRWn <= 1'b1;
		end
		else if( Clks.enPhi2) begin
			if( busState == S6)			{oASn, oDSn} <= '1;
		end
	end

	assign enIas = Clks.enPhi1 & (busState == S0);			// Next cycle internal AS is asserted (S2)
	assign negIas = Clks.enPhi2 & (busState == S6);			// Next cycle internal AS is deasserted (S7)
	// One cycle before above
	assign enS5 = Clks.enPhi2 & (busState == S4);			// See note below!
	assign enS0 = Clks.enPhi1 & (busState == S6);			// Next cycle is S0
		
	// Note that enS5 doesn't consider delayed DTACK. Might stay on S4 !
	// That would require using DTACK combinationally, which is not good if it's a true external signal.

	//	
	// Bus arbitrarion
	//
	
	reg yieldState;
	wire rdyGranted = !BGIn & iBGACKn & iASn;
	wire canRequest = wantDma & iBRn & iASn & !yieldState & !rdyGranted;		// Start bus request

//TH TODO 	enum int unsigned { DMAST_IDLE = 0, DMAST_REQ, DMAST_ACTIVE1, DMAST_ACTIVE2} dmaState, next;
	enum bit[1:0] { DMAST_IDLE = 0, DMAST_REQ, DMAST_ACTIVE1, DMAST_ACTIVE2} dmaState, next;

	wire startYield = !iBRn & (dmaState == DMAST_ACTIVE2);		// Start requesting yield
	wire inYield = wantDma & yieldState;						// Requesting yield and still pending
	
	always_comb begin
		case( dmaState)
		DMAST_IDLE:			next = canRequest ? DMAST_REQ : DMAST_IDLE;	
		DMAST_REQ:			next = rdyGranted ? DMAST_ACTIVE1: DMAST_REQ;
		DMAST_ACTIVE1:		next = wantDma ? DMAST_ACTIVE2 : DMAST_IDLE;
		DMAST_ACTIVE2:		next = iBRn ? DMAST_ACTIVE1 : DMAST_IDLE;
		endcase
	end

	always_ff @(posedge Clks.clk) begin
		if( Clks.sReset)			dmaState <= DMAST_IDLE;
		else if( Clks.enPhi1)		dmaState <= next;
		
		if( Clks.sReset)			yieldState <= 1'b0;
		else if( Clks.enPhi1)		yieldState <= inYield | startYield;
	end

	wire dmaActive =	(  dmaState == DMAST_ACTIVE2) | 
						( (dmaState == DMAST_ACTIVE1) & wantDma) |
						( (dmaState == DMAST_REQ) & rdyGranted);
	
	always_ff @(posedge Clks.clk) begin
		if( Clks.sReset) begin
			oBRn <= 1'b1;
			busOwned <= 1'b0;
			BGOn <= 1'b1;
		end
		else if( Clks.enPhi1) begin
			oBRn <= !( (dmaState == DMAST_REQ) | ( (dmaState == DMAST_IDLE) & canRequest) );
			
			BGOn <= !(!BGIn & !yieldState & (dmaState == DMAST_IDLE));

			busOwned <= inYield | dmaActive;
			extDmaReq <= yieldState | startYield;
		end
	end
	assign oBGACKn = !busOwned;
				
endmodule

// Main machine control state
module bltControl( input blt_clks Clks, input busy, Hog, extDmaReq, negIas, enS5, timeOut, rBltReset,
		input XC2,XC1, input [3:0] OP, input [1:0] HOP, input Smudge, Nfsr, Fxsr, skewWr, forceDestRd,
		output busOe, updSrc, updDst, srcCycle, writeCycle, nxtLineCycle, xtraSrcCycle, dstLatchCycle, nfsrCycle, wantDma);

	enum int unsigned { ST_IDLE = 0, ST_FXSR1, ST_RDSRC, ST_RDEST, ST_WDEST} bltState, next, first;
		
	wire stopBlit = (timeOut & !Hog) | extDmaReq | !busy;
			
	wire haveRmDest = forceDestRd | (OP[3] ^ OP[2]) | (OP[1] ^ OP[0]);	// OP modes constant or source only
	
	wire skipNextSrc = XC2 & (bltState == ST_WDEST) & Nfsr;
	
	wire noOpSrc = (OP[2] == OP[0]) & (OP[3] == OP[1]);			// OP modes without source: 0,5,A,F
	wire noHopSrc = !HOP[1] & !Smudge;							// HOP without source and NOT SMUDGE
	wire noSrcRd = skipNextSrc | noOpSrc | noHopSrc;
	

	// This is used also to control bus Output Enable.
	reg bltActive;
	assign busOe = bltActive;

	
	// Process FXSR. Originally done with a couple of latches that override the machine state.
	reg fxsrLatch;
	assign xtraSrcCycle = ( bltState == ST_FXSR1);
	always_ff @(posedge Clks.clk) begin
		if( skewWr)
			fxsrLatch <= Fxsr;
		else if( negIas) begin
			if( bltActive & xtraSrcCycle)
				fxsrLatch <= 1'b0;
		end
		else if( enS5 & updDst & Fxsr & XC1)
			fxsrLatch <= 1'b1;			
	end
		
	
	always_ff @(posedge Clks.clk or negedge busy) begin
		if( !busy)					bltActive <= 1'b0;
		
		else if( Clks.sReset)		bltActive <= 1'b0;
		else if( negIas)			bltActive <= !stopBlit;
	end
	
	assign wantDma = (!stopBlit & busy) | bltActive;
			
	always_comb begin
		// Pre compute first cycle for this word
		if( !noSrcRd)		first = fxsrLatch ? ST_FXSR1 : ST_RDSRC;
		else				first = ( haveRmDest ? ST_RDEST : ST_WDEST);
		
	case( bltState)
	ST_IDLE:
		next = stopBlit ? ST_IDLE : first;
	ST_FXSR1:
		next = bltActive ? ST_RDSRC : ST_FXSR1;
	ST_RDSRC:
		next = bltActive ? ( haveRmDest ? ST_RDEST : ST_WDEST) : ST_RDSRC;
	ST_RDEST:
		next = bltActive ? ST_WDEST : ST_RDEST;
	ST_WDEST:
		next = bltActive ? first : ST_WDEST;
	default:
		next = ST_IDLE;
	endcase
	end
	
	always_ff @(posedge Clks.clk) begin
		if( Clks.sReset)			bltState <= ST_IDLE;
		else if( rBltReset)			bltState <= ST_IDLE;
		else if( negIas)			bltState <= next;
	end

	assign updSrc = bltActive & ( (bltState == ST_RDSRC) | (bltState == ST_FXSR1));
	assign updDst = bltActive & (bltState == ST_WDEST);
	assign srcCycle = bltActive & ((bltState == ST_RDSRC) | (bltState == ST_FXSR1));
	assign nfsrCycle = bltActive & writeCycle & Nfsr & XC1;
	assign dstLatchCycle = bltActive & (bltState == ST_RDEST);
	assign writeCycle = (bltState == ST_WDEST);
	assign nxtLineCycle = writeCycle & bltActive & XC1 & negIas;

endmodule

// Blitter counters and addr registers
module bltCounters( input blt_clks Clks, input [15:0] SEL,
				input wrWordSel,
				input busOwned, updCycle, srcCycle, xtraSrcCycle, updSrc, updDst,
				input Nfsr,
				input [15:1] srcXincr, input [15:1] srcYincr,
				input [15:1] dstXincr, input [15:1] dstYincr,
				output logic [15:0] xCounter, output logic [15:0] yCounter,
				output logic [23:1] srcAddr, output logic [23:1] dstAddr,
				output XC1, XC2,
				output logic XYZ, rBltReset,
				output Direction, IncSign,
				input [15:0] iDBUS, output [23:1] oABUS);
	
	wire yCntWr = SEL[REG_18] & wrWordSel;
	
	//
	// X/Y counters
	//
	// reg [15:0] xCounter, reg [15:0] yCounter;
	reg [15:0] xStart;
	
	wire   YC1 = (yCounter == 16'h0001);
	assign XC1 = (xCounter == 16'h0001);
	assign XC2 = (xCounter == 16'h0002);

	always_ff @(posedge Clks.clk) begin
		if( Clks.sReset)						XYZ <= 1'b0;
		else if( Clks.enPhi1 & rBltReset)		XYZ <= 1'b0;
		else if( updCycle & updDst)				XYZ <= XC1 & YC1;
	end

	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp)				rBltReset <= 1'b0;
		else if( Clks.enPhi1)		rBltReset <= yCntWr;
	end
	
	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp) begin
			xCounter <= '0;			yCounter <= '0;
		end
		else if( busOwned) begin
		
			if( updCycle & updDst) begin
				if( XC1) begin
					yCounter <= yCounter - 1'b1;
					xCounter <= xStart;
				end
				else
					xCounter <= xCounter - 1'b1;
			end
		
		end
		
		else if( Clks.enPhi1) begin
			if( wrWordSel) begin
				if( SEL[REG_16]) begin
					xCounter <= iDBUS[15:0];
					xStart <= iDBUS[15:0];
				end
				if( SEL[REG_18])		yCounter <= iDBUS[15:0];
			end
		end
		
	end
	
	//
	// Increment registers
	//
		
	// Determine which increment register to use. Easy for DEST, not so simple for SOURCE
	wire [15:1] dstIncr = !XC1 ? dstXincr : dstYincr;
	wire [23:1] extDstIncr = { {8{ dstIncr[15]}}, dstIncr[15:1]};
	
	logic isX;
	always_comb begin
		if( xtraSrcCycle)				isX = 1'b1;		// If on first of extra source cycle, it's X
		else if( XC1 | ( XC2 & Nfsr))	isX = 1'b0;		// Otherwise, if XC1, or XC2 and NFSR, it's last source cycle on line, then it is Y
		else							isX = 1'b1;		// Otherwise it's X
	end
	wire [15:1] srcIncr = isX ? srcXincr : srcYincr;
	wire [23:1] extSrcIncr = { {8{ srcIncr[15]}}, srcIncr[15:1]};
	
	// Optional pipeline!
	// extSrcIncr <= { {8{ srcIncr[15]}}, srcIncr[15:1]};
	
	assign Direction = srcXincr[15];				// Used for SKEW
	assign IncSign = dstYincr[15];					// Used for LINE up/down
			
	//
	// Address registers
	//

	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp) begin
			srcAddr <= '0;
			dstAddr <= '0;
		end
		else if( busOwned) begin
			if( updCycle) begin
				// This adder with the combinational incrementer mux, is the slowest path in the Blitter core!
				if( updSrc)				srcAddr <= srcAddr + extSrcIncr;
				if( updDst)				dstAddr <= dstAddr + extDstIncr;
			end
		end
		else if( Clks.enPhi1) begin		
			if( wrWordSel) begin		
				if( SEL[REG_04])		srcAddr[23:16] <= iDBUS[7:0];
				if( SEL[REG_06])		srcAddr[15:1] <= iDBUS[15:1];
				if( SEL[REG_12])		dstAddr[23:16] <= iDBUS[7:0];
				if( SEL[REG_14])		dstAddr[15:1] <= iDBUS[15:1];
			end
		end
	end
	
	assign oABUS = srcCycle ? srcAddr : dstAddr;
	
endmodule

// Blitter core operation
module bltScore( input blt_clks Clks, input [15:0] SEL, input [15:0] iDBUS,
				input rBltReset, updCycle, updDst, busOwned, enIas, XC1, XC2, wrWordSel, maskChanged,
				
				input ramSel, ramWrSel, input [3:0] ramSelIdx, input [3:0] ramIdx,
				output logic [15:0] ramOut,
				
				input [3:0] OP, input [1:0] HOP,
				input [15:0] destBuf, input [15:0] srcbuf,
				input [15:0] lEndMask, input [15:0] cEndMask, input [15:0] rEndMask,
				
				output logic forceDestRd,
				output logic [15:0] bltOut);

	
	// Endmasks mux
	logic [15:0] mask;
	
	// Mux current endmask. Might need to pipeline for higher performance!
	reg newLine;
	always_ff @(posedge Clks.clk) begin
		if( Clks.enPhi1 & rBltReset)		newLine <= 1'b1;
		else if( updCycle & updDst)			newLine <= XC1;
	end
	
	always_comb begin
		if( newLine)			mask = lEndMask;
		else if( XC1)			mask = rEndMask;
		else					mask = cEndMask;
	end
	
	// Force destination read according to relevant endmask
	// Updated at the write cycle. Required before the actual blit cycle by the control machine state.
	// So we predict the state at the previous write cycle.
	// And we do it at the middle of the write cycle because forceDestRd is pipelined
	
	// The endmask selection (right, center, or left) is performed at a specific single point.
	// But the actual content of the selected endmask can be modified anytime.
	//
	// Original logic is almost fully asynchronous
	
	reg [1:0] nxtMask;			// Holds the selected endmask for next blit cycle

	always_ff @(posedge Clks.clk) begin
		if( Clks.pwrUp) begin
			forceDestRd <= 1'b0;
			nxtMask <= '0;
		end
		
		else if( Clks.enPhi1 & maskChanged) begin
			case( nxtMask)
			2'b00:			forceDestRd <= !(& lEndMask);
			2'b01:			forceDestRd <= !(& rEndMask);
			2'b10:			forceDestRd <= !(& cEndMask);
			endcase
		end
		else if( Clks.enPhi1 & rBltReset) begin
			forceDestRd <= !(& lEndMask);
			nxtMask <= 2'b00;
		end
		else if( updDst & enIas) begin
			// This is the correct priority in case line lenght is one or two words!
			
			if( XC1) begin
				forceDestRd <= !(& lEndMask);		// If last cycle on line, next is new line (use left endmask)
				nxtMask <= 2'b00;
			end else if( XC2) begin
				forceDestRd <= !(& rEndMask);		// If next cycle would be last on line, use right endmask
				nxtMask <= 2'b01;
			end
			else begin
				forceDestRd <= !(& cEndMask);		// Otherwise it would be center
				nxtMask <= 2'b10;
			end
		end
	end
	

	//
	// Halftone RAM
	//
	reg [15:0] hRam[16];
	logic [15:0] rambuf;

`ifdef ORIG
	// synthesis translate off
	initial	for( int i = 0; i < 16; i++)	hRam[i] = 0;
	// synthesis translate on
	
	always_ff @(posedge Clks.clk) begin
		if( Clks.enPhi1 & ramWrSel)			hRam[ ramSelIdx] <= iDBUS;

        //TH if( busOwned & enIas)				rambuf <= hRam[ ramIdx];
	end
	assign rambuf = hRam[ ramIdx];			// Ascyn read. Will not infer RAM on FPGA	
	// Will infer dual port RAM.
	always_ff @(posedge Clks.clk)
		if( ramSel & Clks.enPhi2)			ramOut <= hRam[ ramSelIdx];	
`else
    logic [3:0] lRamIdx;
	always_comb lRamIdx = busOwned?ramIdx:ramSelIdx;
    assign ramOut = rambuf;

	always_ff @(posedge Clks.clk) begin
        if(!busOwned) begin
            // CPU hram write
            if( Clks.enPhi1 & ramWrSel)			hRam[ lRamIdx] <= iDBUS;
            // CPU hram read
            else if( ramSel & Clks.enPhi2)	    rambuf <= hRam[ lRamIdx];	
        end else
            // read during blitter operation
            if( enIas)				rambuf <= hRam[ lRamIdx];
	end
`endif
	
	// Blit OP: ~( (~S & ~D) | (~S & D) | (S & ~D) | (S & D) )
	//               OP[3]       OP[2]     OP[1]      OP[0]

	logic [15:0] nHop;
	logic [15:0] nQop;	
	always_comb begin
		for( int i = 0; i < 16; i++) begin
			nHop[i] = (~srcbuf[i] & HOP[1]) | (~rambuf[i] & HOP[0]);
			nQop[i] =		(!OP[3] &  nHop[i] & ~destBuf[i]) |
							(!OP[2] &  nHop[i] &  destBuf[i]) |
							(!OP[1] & ~nHop[i] & ~destBuf[i]) |
							(!OP[0] & ~nHop[i] &  destBuf[i]);
			bltOut[i] = mask[i] ?  ~nQop[i] : destBuf[i];
		end
	end

endmodule

//
// Test
//

`ifdef BLIT_TEST

module stBlitter_tst( input clk32, input reset_n,

	// Control signals from the CPU
	input ASn, RWn, LDSn, UDSn,
	input FC2,FC1,FC0,
	input DTACKn, BERRn,
	
	input BRn,			// Other bus master is requesting the bus
	input iBGACKn,		// Other bus master ack
	input BGn,			// CPU grants the bus
	
	output oBRn, blitBGACKn,	// We request/ack the bus
	output BGOn,				// Grant the bus to other bus master
	output [2:0] oFc,
	output INTn,

	// Separated DMA input might benefit some cores.
	// If using the same input data bus, then, assign dmaInput = iDBUS
	input [15:0] dmaInput,

	// Input/output address bus
	input [23:1] iABUS, output [23:1] oABUS,

	// Input/output data bus
	input [15:0] iDBUS, output [15:0] oDBUS);

	// Clock must be at least twice the desired frequency. A 32 MHz clock means a maximum 16 MHz effective frequency.
	// In this example we divide the clock by 4. Resulting on an 8 MHz effective frequency.
	
	reg [1:0] clkDivisor = '0;
	always @( posedge clk32) begin
		clkDivisor <= clkDivisor + 1'b1;
	end

	blt_clks Clks;
		
	/*
	These two signals must be a single cycle pulse. They don't need to be registered.
	Same signal can't be asserted twice in a row. Other than that there are no restrictions.
	There can be any number of cycles, or none, even variable non constant cycles, between each pulse.
	*/
	
	assign Clks.enPhi1 = (clkDivisor == 2'b11);
	assign Clks.enPhi2 = (clkDivisor == 2'b01);
	
	assign Clks.clk = clk32;
	assign Clks.aRESETn = reset_n;
	assign Clks.sReset = !reset_n;
	assign Clks.pwrUp = !reset_n;
	assign Clks.anyPhi = Clks.enPhi2 | Clks.enPhi1;
	assign { Clks.extReset, Clks.phi1, Clks.phi2} = '0;

	wire ctrlOe;		// Blitter is bus master and outputs below control signals
	wire oASn, oDSn, oRWn, oDTACKn;
	wire dataOe;		// Bliter output data bus is valid
	wire selected;		// Blitter internal chip select

	assign oFc = 3'b101;
	wire oBGACKn;
	assign blitBGACKn = oBGACKn & iBGACKn;		// This really happens inside Blitter

	stBlitter stBlitter( .Clks, .ASn, .RWn, .LDSn, .UDSn,
			.FC0,.FC1,.FC2, .BERRn, .iDTACKn( DTACKn),
			.ctrlOe, .dataOe, .oASn, .oDSn, .oRWn, .oDTACKn,
			.selected,
			.iBRn( BRn), .BGIn( BGn), .iBGACKn,
			.oBRn, .oBGACKn, .INTn, .BGOn,
			.dmaInput,
			.iABUS, .oABUS, .iDBUS, .oDBUS);

endmodule

`endif
