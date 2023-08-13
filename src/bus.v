module bus_controller (
  // Normal clk/reset, system clock rate
  input wire clk,
  input wire reset,

  // Address and data regs from cpu
  input wire [23:0] addr,
  input wire [7:0] data,

  // Bus controller control inputs
  //  - a rising edge of mreq initiates a bus transaction
  //  - mtype determines which type of transaction is occurring
  //  - mdone is raised once the transaction is complete, and reset on the
  //    falling edge of mreq
  input wire mreq,
  input wire mytpe,
  output reg mdone,

  // Handshaking pins
  //  - rdy is set when there is something on the bus for the slave to do
  //  - ack is sent by the slave when it has read from/written to the bus
  //  - bus_ctrl is used to indicate what the slave should do
  input wire ack,
  output wire rdy,
  output wire [2:0] bus_ctrl;
);

  `include "params.vh"

  localparam [1:0] // Bus controller states
    ADDR0 = 0,
    ADDR1 = 1,
    ADDR2 = 2,
    DATA = 3,
    IDLE = 4;

  reg waiting;
  reg [2:0] controller_state;

  // Detect positive edge on mreq, used in starting state to kick off a bus
  // transaction.
  reg mreq_dly;
  wire mreq_edge;
  assign mreq_posedge = mreq & ~mreq_dly;
  assign mreq_negedge = ~mreq & mreq_dly;
  always @(posedge clk) begin
    if (reset) begin
      mreq_dly <= 0;
    end else begin
      mreq_dly <= mreq;
    end
  end

  always @(posedge clk) begin
    if (reset) begin
    end else begin
      case(bus_state) begin
        IDLE: begin
          if (mreq_edge) begin
            if ((mtype == RCHAR) || (mtype == WCHAR))
              controller_state <= DATA;
          end
        end

        ADDR0: begin
          if (waiting && ack) begin
            waiting <= 0;
            controller_state <= ADDR1;
          end else begin
            if (mreq_edge) begin
              data <= addr[7:0];
              waiting <= 1;
            end
          end
        end

        ADDR1: begin
          if (waiting && ack) begin
            waiting <= 0;
            controller_state <= ADDR2;
          end else begin
            data <= addr[15:8];
            waiting <= 1;
          end
        end

        ADDR2: begin
          if (waiting && ack) begin
            waiting <= 0;
            if (mtype == )
              controller_state <= RDATA;
            else if (!mc && rw)
              controller_state <= WDATA;
            else if (mc && !rw)
              controller_state <= RCHAR;
            else if (mc && rw)
              controller_state <= WCHAR;
          end else begin
            data <= addr[23:16];
            waiting <= 1;
          end
        end

        RDATA: begin
          if (waiting && ack) begin
            waiting <= 0;
            controller_state <= ADDR2;
          end else begin
            data <= addr[15:8];
            waiting <= 1;
          end
        end

      endcase
    end
  end

endmodule

