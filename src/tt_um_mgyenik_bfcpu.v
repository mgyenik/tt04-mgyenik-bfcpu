`default_nettype none

module tt_um_mgyenik_bfcpu #( parameter MAX_COUNT = 24'd10_000_000 ) (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  `include "params.vh"

  localparam [5:0] // CPU states
    FETCH_REQ   = 0,
    FETCH_WAIT  = 1,
    FETCH_DONE  = 2,
    DECODE      = 3,
    DINC_LOAD   = 4,
    DINC_WAIT   = 5,
    DINC_DONE   = 6,
    DINC        = 7,
    DDEC_LOAD   = 8,
    DDEC_WAIT   = 9,
    DDEC_DONE   = 10,
    DDEC        = 11,
    PINC_WB     = 12,
    PINC_WAIT   = 13,
    PINC_DONE   = 14,
    PINC        = 15,
    PDEC_WB     = 16,
    PDEC_WAIT   = 17,
    PDEC_DONE   = 18,
    PDEC        = 19,
    HALT        = 20,
    SCAN_LD          = 21,
    SCAN_LD_WAIT     = 22,
    SCAN_LD_DONE     = 23,
    SCAN_START       = 24,
    SCAN_FETCH       = 25,
    SCAN_FETCH_WAIT  = 26,
    SCAN_FETCH_DONE  = 27,
    MEM_WAIT         = 28,
    RCHAR_READ       = 29,
    RCHAR_READ_DONE  = 30,
    RCHAR_WB         = 31,
    RCHAR_WB_DONE    = 32,
    WCHAR_LD         = 33,
    WCHAR_LD_DONE    = 34,
    WCHAR_WRITE      = 35,
    WCHAR_WRITE_DONE = 36,
    HALT_WB         = 37,
    HALT_WB_DONE    = 38;

  localparam [7:0] // Instructions, raw ascii
    I_DINC = 8'h2b,
    I_DDEC = 8'h2d,
    I_PINC = 8'h3e,
    I_PDEC = 8'h3c,
    I_COUT = 8'h2e,
    I_CIN  = 8'h2c,
    I_HALT = 8'h24,
    I_LOOP_START  = 8'h5b,
    I_LOOP_END    = 8'h5d;
    
    
  // Make positive reset signal for convenience
  wire reset = ! rst_n;

  // The first input is used as the bus_en input - when high the bus is
  // connected to the outputs, when low it's connected to the inputs.
  wire bus_en;
  assign bus_en = ui_in[0];
  assign uio_oe = bus_en ? 8'hff : 8'h00;

  // Assign handshaking signals for bus control.
  wire ack;
  wire rdy;
  wire [1:0] bus_ctrl;
  assign ack = ui_in[1];

  assign uo_out[0] = rdy;
  assign uo_out[2:1] = bus_ctrl;
  assign uo_out[5:3] = mtype;

  reg halted;
  assign uo_out[6] = halted;

  // Unused
  assign uo_out[7] = 0;

  // Classic BF pointer and data registers.
  reg [14:0] pointer;
  reg  [7:0] data;

  // True if the data register is dirty and needs to be written back, we avoid
  // writing it to memory until the pointer changes.
  reg dirty;

  // Scan logic for loops
  // TODO(mgyenik): document
  reg [15:0] scan_ctr;
  reg reverse_dir;
  wire [7:0] same_brace;
  wire [7:0] matching_brace;
  assign same_brace = reverse_dir ? I_LOOP_END : I_LOOP_START;
  assign matching_brace = reverse_dir ? I_LOOP_START : I_LOOP_END;

  // TODO(mgyenik): Condense MDR into one register with r/w gate
  reg [7:0] mdr_in;
  wire [7:0] mdr_out;
  reg [2:0] mtype;
  reg mreq;
  wire mdone;

  reg [5:0] state;
  reg [5:0] mem_wait_dst;

  wire [23:0] maddr;
  assign maddr[14:0] = pointer[14:0];
  assign maddr[23:15] = 9'b000000000;

  bus_controller bus_controller(
    .clk      (clk),
    .reset    (reset),
    .addr     (maddr),
    .data_in  (mdr_in),
    .data_out (mdr_out),
    .mreq     (mreq),
    .mtype    (mtype),
    .mdone    (mdone),
    .ack      (ack),
    .rdy      (rdy),
    .bus_ctrl (bus_ctrl),
    .bus_in   (uio_in),
    .bus_out  (uio_out)
  );

  always @(posedge clk) begin
    if (reset) begin
      pointer <= 0;
      data <= 0;
      dirty <= 0;
      scan_ctr <= 0;
      reverse_dir <= 0;
      mdr_in <= 0;
      mtype <= 0;
      mreq <= 0;
      state <= 0;
      mem_wait_dst <= 0;
      halted <= 0;
    end else begin
      case (state)
        FETCH_REQ: begin
          mtype <= PROGN;
          mreq <= 1;
          state <= FETCH_WAIT;
        end

        FETCH_WAIT: begin
          if (mdone)
            state <= FETCH_DONE;
          else
            state <= FETCH_WAIT;
        end

        FETCH_DONE: begin
          mreq <= 0;
          state <= DECODE;
        end

        // TODO(mgyenik): since we decode straight from MDR and don't need to
        // copy into IR, do we even need the DECODE state? Remove/merge with
        // FETCH_DONE if possible
        DECODE: begin
          case (mdr_out)
            default:
              state <= FETCH_REQ;
            I_HALT:
              if (dirty)
                state <= HALT_WB;
              else
                state <= HALT;
            I_DINC:
              if (dirty)
                state <= DINC;
              else
                state <= DINC_LOAD;
            I_DDEC:
              if (dirty)
                state <= DDEC;
              else
                state <= DDEC_LOAD;
            I_PINC:
              if (dirty)
                state <= PINC_WB;
              else
                state <= PINC;
            I_PDEC:
              if (dirty)
                state <= PDEC_WB;
              else
                state <= PDEC;
            I_COUT:
              if (dirty)
                state <= WCHAR_WRITE;
              else
                state <= WCHAR_LD;
            I_CIN:
              state <= RCHAR_READ;
            I_LOOP_START: begin
              reverse_dir <= 0;
              if (dirty)
                state <= SCAN_START;
              else
                state <= SCAN_LD;
            end
            I_LOOP_END: begin
              reverse_dir <= 1;
              if (dirty)
                state <= SCAN_START;
              else
                state <= SCAN_LD;
            end
          endcase
        end

        DINC_LOAD: begin
          mtype <= RDATA;
          mreq <= 1;
          state <= DINC_WAIT;
        end

        DINC_WAIT: begin
          if (mdone)
            state <= DINC_DONE;
          else
            state <= DINC_WAIT;
        end

        DINC_DONE: begin
          dirty <= 1;
          data <= mdr_out;
          mreq <= 0;
          state <= DINC;
        end

        DINC: begin
          data <= data + 1;
          state <= FETCH_REQ;
        end

        DDEC_LOAD: begin
          mtype <= RDATA;
          mreq <= 1;
          state <= DDEC_WAIT;
        end

        DDEC_WAIT: begin
          if (mdone)
            state <= DDEC_DONE;
          else
            state <= DDEC_WAIT;
        end

        DDEC_DONE: begin
          dirty <= 1;
          data <= mdr_out;
          mreq <= 0;
          state <= DDEC;
        end

        DDEC: begin
          data <= data - 1;
          state <= FETCH_REQ;
        end

        PINC_WB: begin
          mdr_in <= data;
          mtype <= WDATA;
          mreq <= 1;
          state <= PINC_WAIT;
        end

        PINC_WAIT: begin
          if (mdone)
            state <= PINC_DONE;
          else
            state <= PINC_WAIT;
        end

        PINC_DONE: begin
          dirty <= 0;
          mreq <= 0;
          state <= PINC;
        end

        PINC: begin
          pointer <= pointer + 1;
          state <= FETCH_REQ;
        end

        PDEC_WB: begin
          mdr_in <= data;
          mtype <= WDATA;
          mreq <= 1;
          state <= PDEC_WAIT;
        end

        PDEC_WAIT: begin
          if (mdone)
            state <= PDEC_DONE;
          else
            state <= PDEC_WAIT;
        end

        PDEC_DONE: begin
          dirty <= 0;
          mreq <= 0;
          state <= PDEC;
        end

        PDEC: begin
          pointer <= pointer - 1;
          state <= FETCH_REQ;
        end

        HALT: begin
          state <= HALT;
          halted <= 1;
        end

        SCAN_LD: begin
          mtype <= RDATA;
          mreq <= 1;
          state <= SCAN_LD_WAIT;
        end

        SCAN_LD_WAIT: begin
          if (mdone)
            state <= SCAN_LD_DONE;
          else
            state <= SCAN_LD_WAIT;
        end

        SCAN_LD_DONE: begin
          dirty <= 1;
          data <= mdr_out;
          mreq <= 0;
          state <= SCAN_START;
        end

        // To scan, we see if the data byte is non-zero, if it is we need to
        // find the matching brace. We set up a PROGx fetch and keep fetching
        // until we find the matching brace. We skip nested loops using
        // a counter, incrementing it whenever we encounter a same brace and
        // decrementing it when we find the matching one we are looking for,
        // and only temrinate the scan when the matching brace is found and
        // the counter is zero.
        SCAN_START: begin
          if (reverse_dir)
            if (data == 0) begin
              state <= FETCH_REQ;
            end
            else begin
              mtype <= PROGP;
              scan_ctr <= 16'hffff;
              state <= SCAN_FETCH;
            end
          else
            if (data == 0) begin
              mtype <= PROGN;
              scan_ctr <= 0;
              state <= SCAN_FETCH;
            end
            else begin
              state <= FETCH_REQ;
            end
        end

        SCAN_FETCH: begin
          mreq <= 1;
          state <= SCAN_FETCH_WAIT;
        end

        SCAN_FETCH_WAIT: begin
          if (mdone)
            state <= SCAN_FETCH_DONE;
          else
            state <= SCAN_FETCH_WAIT;
        end

        SCAN_FETCH_DONE: begin
          mreq <= 0;
          if (mdr_out == matching_brace) begin
            if (scan_ctr == 0) begin
              state <= FETCH_REQ;
            end
            else begin
              scan_ctr <= scan_ctr - 1;
              state <= SCAN_FETCH;
            end
          end
          else if (mdr_out == same_brace) begin
            scan_ctr <= scan_ctr + 1;
            state <= SCAN_FETCH;
          end
          else begin
            state <= SCAN_FETCH;
          end
        end

        MEM_WAIT: begin
          if (mdone)
            state <= mem_wait_dst;
          else
            state <= MEM_WAIT;
        end

        RCHAR_READ: begin
          mtype <= RCHAR;
          mreq <= 1;
          mem_wait_dst <= RCHAR_READ_DONE;
          state <= MEM_WAIT;
        end

        RCHAR_READ_DONE: begin
          mreq <= 0;
          state <= FETCH_REQ;
          dirty <= 1;
          data <= mdr_out;
        end

        /* RCHAR_WB: begin */
        /*   mtype <= WCHAR; */
        /*   mreq <= 1; */
        /*   mem_wait_dst <= RCHAR_WB_DONE; */
        /*   state <= MEM_WAIT; */
        /* end */

        /* RCHAR_WB_DONE: begin */
        /*   mreq <= 0; */
        /*   state <= RCHAR_WB; */
        /* end */
        /* end */

        WCHAR_LD: begin
          mtype <= RDATA;
          mreq <= 1;
          mem_wait_dst <= WCHAR_LD_DONE;
          state <= MEM_WAIT;
        end

        WCHAR_LD_DONE: begin
          dirty <= 1;
          data <= mdr_out;
          mreq <= 0;
          state <= WCHAR_WRITE;
        end

        WCHAR_WRITE: begin
          mdr_in <= data;
          mtype <= WCHAR;
          mreq <= 1;
          mem_wait_dst <= WCHAR_WRITE_DONE;
          state <= MEM_WAIT;
        end

        WCHAR_WRITE_DONE: begin
          mreq <= 0;
          state <= FETCH_REQ;
        end

        HALT_WB: begin
          mdr_in <= data;
          mtype <= WDATA;
          mreq <= 1;
          mem_wait_dst <= HALT_WB_DONE;
          state <= MEM_WAIT;
        end

        HALT_WB_DONE: begin
          dirty <= 0;
          mreq <= 0;
          state <= HALT;
        end
      endcase
    end
  end

  // genvar k;
  // generate 
  // 	for (k = 0; k < 64; k++) begin
  //     assign init[k] = k;
  // 		always@(posedge clk) begin
  // 			if (reset) begin
  // 				ucode[k] <= init[k];
  // 			end
  // 		end
  // 	end
  // endgenerate
endmodule
