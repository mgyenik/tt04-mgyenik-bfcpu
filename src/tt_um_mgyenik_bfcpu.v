`default_nettype none

module tt_um_mgyenik_bfcpu #(
  parameter DCACHE_BYTES_BITS = 3
) (
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

  localparam STATE_BITS = 5;
  localparam [STATE_BITS-1:0] // CPU states
    FETCH            = 0,
    DECODE           = 1,
    DINC             = 2,
    DDEC             = 3,
    PINC             = 4,
    PDEC             = 5,
    HALT             = 6,
    SCAN_START       = 7,
    SCAN_FETCH       = 8,
    SCAN_FETCH_DONE  = 9,
    MEM_WAIT         = 10,
    RCHAR_READ       = 11,
    RCHAR_READ_DONE  = 12,
    WCHAR_WRITE      = 13,
    WCHAR_WRITE_DONE = 14,
    FLUSH            = 15,
    FLUSH_DONE       = 16,
    WB               = 17,
    WB_DONE          = 18,
    LD               = 19,
    LD_DONE          = 20;

  localparam [7:0] // Instructions, raw ascii
    I_DINC = 8'h2b,
    I_DDEC = 8'h2d,
    I_PINC = 8'h3e,
    I_PDEC = 8'h3c,
    I_COUT = 8'h2e,
    I_CIN  = 8'h2c,
    I_FLUSH = 8'h23,
    I_HALT = 8'h24,
    I_LOOP_START  = 8'h5b,
    I_LOOP_END    = 8'h5d,
    I_LOWER_A = 8'h61,
    I_LOWER_M = 8'h6d,
    I_LOWER_N = 8'h6e,
    I_LOWER_Z = 8'h7a,
    I_UPPER_A = 8'h41,
    I_UPPER_M = 8'h4d,
    I_UPPER_N = 8'h4e,
    I_UPPER_Z = 8'h5a;
    
    
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

  // Classic BF pointer register.
  reg [14:0] pointer;

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

  reg [STATE_BITS-1:0] state;
  reg [STATE_BITS-1:0] mem_wait_dst;
  reg [STATE_BITS-1:0] ld_dst;
  reg [STATE_BITS-1:0] wb_dst;

  reg [7:0] amount;
  reg [15:0] maddr;

  localparam DCACHE_BYTES = 2**DCACHE_BYTES_BITS;

  reg [7:0] dcache[0:DCACHE_BYTES - 1];
  reg       valid[0:DCACHE_BYTES - 1];
  reg [14-DCACHE_BYTES_BITS:0] tag[0:DCACHE_BYTES - 1];

  wire [14-DCACHE_BYTES_BITS:0] curr_tag;
  assign curr_tag = pointer[14:DCACHE_BYTES_BITS];

  wire [DCACHE_BYTES_BITS-1:0] curr_idx;
  assign curr_idx = pointer[DCACHE_BYTES_BITS-1:0];

	reg [DCACHE_BYTES_BITS - 1:0] flush_ctr;

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

  integer i;
  always @(posedge clk) begin
    if (reset) begin
      for (i=0; i<DCACHE_BYTES; i=i+1) dcache[i] <= 0;
      for (i=0; i<DCACHE_BYTES; i=i+1) valid[i] <= 0;
      for (i=0; i<DCACHE_BYTES; i=i+1) tag[i] <= 0;

      pointer <= 0;
      scan_ctr <= 0;
      reverse_dir <= 0;
      mdr_in <= 0;
      mtype <= 0;
      mreq <= 0;
      state <= 0;
      mem_wait_dst <= 0;
      halted <= 0;
      flush_ctr <= 0;
      maddr <= 0;
      amount <= 0;
    end else begin
      case (state)
        FETCH: begin
          mtype <= PROGN;
          mreq <= 1;
          mem_wait_dst <= DECODE;
          state <= MEM_WAIT;
        end

        // TODO(mgyenik): since we decode straight from MDR and don't need to
        // copy into IR, do we even need the DECODE state? Remove/merge with
        // FETCH_DONE if possible
        DECODE: begin
          mreq <= 0;

          if ((mdr_out >= I_LOWER_A) && (mdr_out <= I_LOWER_M)) begin
            amount <= mdr_out - I_LOWER_A + 2;
            if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
              state <= DINC;
            end else begin
              state <= LD;
              ld_dst <= DINC;
            end
          end else if ((mdr_out >= I_LOWER_N) && (mdr_out <= I_LOWER_Z)) begin
            amount <= mdr_out - I_LOWER_N + 2;
            if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
              state <= DDEC;
            end else begin
              state <= LD;
              ld_dst <= DDEC;
            end
          end else if ((mdr_out >= I_UPPER_A) && (mdr_out <= I_UPPER_M)) begin
            amount <= mdr_out - I_UPPER_A + 2;
            if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
              state <= PINC;
            end else begin
              state <= LD;
              ld_dst <= PINC;
            end
          end else if ((mdr_out >= I_UPPER_N) && (mdr_out <= I_UPPER_Z)) begin
            amount <= mdr_out - I_UPPER_N + 2;
            if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
              state <= PDEC;
            end else begin
              state <= LD;
              ld_dst <= PDEC;
            end
          end else begin
            case (mdr_out)
              default:
                state <= FETCH;
              I_FLUSH:
                state <= FLUSH;
              I_HALT:
                state <= HALT;
              I_DINC: begin
                amount <= 1;
                if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
                  state <= DINC;
                end else begin
                  state <= LD;
                  ld_dst <= DINC;
                end
              end
              I_DDEC: begin
                amount <= 1;
                if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
                  state <= DDEC;
                end else begin
                  state <= LD;
                  ld_dst <= DDEC;
                end
              end
              I_PINC: begin
                state <= PINC;
                amount <= 1;
              end
              I_PDEC: begin
                state <= PDEC;
                amount <= 1;
              end
              I_COUT:
                if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
                  state <= WCHAR_WRITE;
                end else begin
                  state <= LD;
                  ld_dst <= WCHAR_WRITE;
                end
              I_CIN:
                if (tag[curr_idx] == curr_tag) begin
                  state <= RCHAR_READ;
                end else begin
                  if (valid[curr_idx]) begin
                    state <= WB;
                    state <= RCHAR_READ;
                  end else begin
                    state <= RCHAR_READ;
                  end
                end
              I_LOOP_START: begin
                reverse_dir <= 0;
                if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
                  state <= SCAN_START;
                end else begin
                  state <= LD;
                  ld_dst <= SCAN_START;
                end
              end
              I_LOOP_END: begin
                reverse_dir <= 1;
                if (valid[curr_idx] && tag[curr_idx] == curr_tag) begin
                  state <= SCAN_START;
                end else begin
                  state <= LD;
                  ld_dst <= SCAN_START;
                end
              end
            endcase
          end
        end

        LD: begin
          if (valid[curr_idx] && tag[curr_idx] != curr_tag) begin
            state <= WB;
            wb_dst <= LD;
          end else begin
            maddr <= {1'b0, pointer};
            mtype <= RDATA;
            mreq <= 1;
            mem_wait_dst <= LD_DONE;
            state <= MEM_WAIT;
          end
        end

        LD_DONE: begin
          valid[curr_idx] <= 1;
          dcache[curr_idx] <= mdr_out;
          tag[curr_idx] <= curr_tag;
          mreq <= 0;
          state <= ld_dst;
        end

        WB: begin
          maddr <= {1'b0, tag[curr_idx], curr_idx};
          mdr_in <= dcache[curr_idx];
          mtype <= WDATA;
          mreq <= 1;
          mem_wait_dst <= WB_DONE;
          state <= MEM_WAIT;
        end

        WB_DONE: begin
          valid[curr_idx] <= 0;
          mreq <= 0;
          state <= wb_dst;
        end

        DINC: begin
          dcache[curr_idx] <= dcache[curr_idx] + amount;
          state <= FETCH;
        end

        DDEC: begin
          dcache[curr_idx] <= dcache[curr_idx] - amount;
          state <= FETCH;
        end

        PINC: begin
          pointer <= pointer + amount;
          state <= FETCH;
        end

        PDEC: begin
          pointer <= pointer - amount;
          state <= FETCH;
        end

        HALT: begin
          state <= HALT;
          halted <= 1;
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
            if (dcache[curr_idx] == 0) begin
              state <= FETCH;
            end
            else begin
              mtype <= PROGP;
              scan_ctr <= 16'hffff;
              state <= SCAN_FETCH;
            end
          else
            if (dcache[curr_idx] == 0) begin
              mtype <= PROGN;
              scan_ctr <= 0;
              state <= SCAN_FETCH;
            end
            else begin
              state <= FETCH;
            end
        end

        SCAN_FETCH: begin
          mreq <= 1;
          mem_wait_dst <= SCAN_FETCH_DONE;
          state <= MEM_WAIT;
        end

        SCAN_FETCH_DONE: begin
          mreq <= 0;
          if (mdr_out == matching_brace) begin
            if (scan_ctr == 0) begin
              state <= FETCH;
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
          state <= FETCH;
          valid[curr_idx] <= 1;
          dcache[curr_idx] <= mdr_out;
          tag[curr_idx] <= curr_tag;
        end

        WCHAR_WRITE: begin
          mdr_in <= dcache[curr_idx];
          mtype <= WCHAR;
          mreq <= 1;
          mem_wait_dst <= WCHAR_WRITE_DONE;
          state <= MEM_WAIT;
        end

        WCHAR_WRITE_DONE: begin
          mreq <= 0;
          state <= FETCH;
        end

        FLUSH: begin
          if (valid[flush_ctr]) begin
            maddr <= {1'b0, tag[flush_ctr], flush_ctr};
            mdr_in <= dcache[flush_ctr];
            mtype <= WDATA;
            mreq <= 1;
            mem_wait_dst <= FLUSH_DONE;
            state <= MEM_WAIT;
          end else begin
            if (&flush_ctr == 1) begin
              state <= FETCH;
            end else begin
              flush_ctr <= flush_ctr + 1;
              state <= FLUSH;
            end
          end
        end

        FLUSH_DONE: begin
          mreq <= 0;
          if (&flush_ctr == 1) begin
            state <= FETCH;
          end else begin
            flush_ctr <= flush_ctr + 1;
            state <= FLUSH;
          end
        end
      endcase
    end
  end

  // Uncomment to make dcache debuggable, but it renames the dumpfile from
  // what cocotb expects.
  //
	// integer idx;
  // initial begin
  //   for (idx = 0; idx < DCACHE_BYTES; idx = idx + 1) $dumpvars(0, dcache[idx]);
  // end
endmodule
