`default_nettype none

module tt_um_seven_segment_seconds #( parameter MAX_COUNT = 24'd10_000_000 ) (
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

    // XXX
    //wire [6:0] led_out;
    //assign uo_out[6:0] = led_out;
    //assign uo_out[6:0] = 7'b0000000;
    //assign uo_out[7] = 1'b0;

    // use bidirectionals as outputs
    assign uio_oe = 8'b11111111;

    // put bottom 8 bits of second counter out on the bidirectional gpio
    assign uio_out = second_counter[7:0];

    // external clock is 10MHz, so need 24 bit counter
    reg [23:0] second_counter;
    reg [3:0] digit;

    // if external inputs are set then use that as compare count
    // otherwise use the hard coded MAX_COUNT
    wire [23:0] compare = ui_in == 0 ? MAX_COUNT: {6'b0, ui_in[7:0], 10'b0};

    always @(posedge clk) begin
        // if reset, set counter to 0
        if (reset) begin
            second_counter <= 0;
            digit <= 0;
        end else begin
            // if up to 16e6
            if (second_counter == compare) begin
                // reset
                second_counter <= 0;

                // increment digit
                digit <= digit + 1'b1;

                // only count from 0 to 9
                if (digit == 9)
                    digit <= 0;

            end else
                // increment counter
                second_counter <= second_counter + 1'b1;
        end
    end

    // instantiate segment display
    //seg7 seg7(.counter(digit), .segments(led_out));

    // reg wb_cyc, wb_stb, cfg_stb, wb_we;
    // reg[24:0] wb_addr;
    // reg[8:0] wb_data;

		// wire			o_wb_stall;
		// wire			o_wb_ack;
		// wire	[8:0]	o_wb_data;
		// wire		o_qspi_sck;
		// wire		o_qspi_cs_n;
		// wire	[1:0]	o_qspi_mod;

		// wire	[3:0]	o_qspi_dat;
		// reg [3:0]	i_qspi_dat;


	parameter	AW = 24 - 2;
	parameter	DW = 32;

	reg		i_wb_cyc, i_wb_stb, i_wb_we;
	reg [AW-1:0]	i_wb_addr;
	reg [DW-1:0]	i_wb_data;
	reg [DW/8-1:0]	i_wb_sel;

	wire		o_wb_stall, o_wb_ack;
	wire [DW-1:0]	o_wb_data;
	//
	reg		i_cfg_cyc, i_cfg_stb, i_cfg_we;
	reg [DW-1:0]	i_cfg_data;
	reg [DW/8-1:0]	i_cfg_sel;
	wire		o_cfg_stall, o_cfg_ack;
	wire [DW-1:0]	o_cfg_data;

	//
	wire  o_spi_cs_n, o_spi_sck, o_spi_mosi;
  reg   i_spi_miso;

  always @(posedge clk) begin
      if (reset) begin
        i_wb_cyc <= 0;
        i_wb_stb <= 0;
        i_wb_we <= 0;
        i_wb_addr <= 0;
        i_wb_data <= 0;
        i_wb_sel <= 0;
        i_cfg_cyc <= 0;
        i_cfg_stb <= 0;
        i_cfg_we <= 0;
        i_cfg_data <= 0;
        i_cfg_sel <= 0;
        i_spi_miso <= 0;
      end
  end

  assign uo_out[0] = o_spi_cs_n;
  assign uo_out[1] = o_spi_sck;
  assign uo_out[2] = o_spi_mosi;
  assign uo_out[3] = 1'b0;
  assign uo_out[4] = 1'b0;
  assign uo_out[5] = 1'b0;
  assign uo_out[6] = 1'b0;
  assign uo_out[7] = 1'b0;

  spi flash(
.i_clk(clk),
.i_reset(reset),
.i_wb_cyc(i_wb_cyc),
.i_wb_stb(i_wb_stb),
.i_wb_we(i_wb_we),
.i_wb_addr(i_wb_addr),
.i_wb_data(i_wb_data),
.i_wb_sel(i_wb_sel),
.o_wb_stall(o_wb_stall),
.o_wb_ack(o_wb_ack),
.o_wb_data(o_wb_data),
.i_cfg_cyc(i_cfg_cyc),
.i_cfg_stb(i_cfg_stb),
.i_cfg_we(i_cfg_we),
.i_cfg_data(i_cfg_data),
.i_cfg_sel(i_cfg_sel),
.o_cfg_stall(o_cfg_stall),
.o_cfg_ack(o_cfg_ack),
.o_cfg_data(o_cfg_data),
.o_spi_cs_n(o_spi_cs_n),
.o_spi_sck(o_spi_sck),
.o_spi_mosi(o_spi_mosi),
.i_spi_miso(i_spi_miso)
  );

    // qflexpress flash(
    //   .i_clk(clk),
    //   .i_reset(reset),
    // .i_wb_cyc(wb_cyc),
    // .i_wb_stb(wb_stb),
    // .i_cfg_stb(cfg_stb),
    // .i_wb_we(wb_we),
    // .i_wb_addr(wb_addr),
    // .i_wb_data(wb_data),

		// .o_wb_stall(o_wb_stall),
		// .o_wb_ack(o_wb_ack),
		// .o_wb_data(o_wb_data),
		// 
		// .o_qspi_sck(o_qspi_sck),
		// .o_qspi_cs_n(o_qspi_cs_n),
		// .o_qspi_mod(o_qspi_mod),

		// .o_qspi_dat(o_qspi_dat),
		// .i_qspi_dat(i_qspi_dat)
    // );


endmodule
