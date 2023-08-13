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

    wire reset = ! rst_n;

    // use bidirectionals as outputs
    assign uio_oe = 8'b11111111;

    reg [15:0] ucode[0:63];
    wire [15:0] init[0:63];


    reg [5:0] counter;
		reg [7:0] uc_lsb;
	  reg [7:0] uc_msb;	
    assign uo_out = uc_lsb;
    assign uio_out = uc_msb;
    always @(posedge clk) begin
      // if reset, set counter to 0
      if (reset) begin
        counter <= 0;
      end else begin
        counter <= counter + 1;
        uc_lsb <= ucode[counter][7:0];
        uc_msb <= ucode[counter][15:8];
      end
    end

		genvar k;
		generate 
			for (k = 0; k < 64; k++) begin
        assign init[k] = k;
				always@(posedge clk) begin
					if (reset) begin
						ucode[k] <= init[k];
					end
				end
			end
		endgenerate

endmodule
