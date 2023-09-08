module bus_controller (
  // Normal clk/reset, system clock rate
  input wire clk,
  input wire reset,

  // Address and data regs from cpu
  input wire [15:0] addr,
  input wire [7:0] data_in,
  output reg [7:0] data_out,

  // Bus controller control inputs
  //  - a rising edge of mreq initiates a bus transaction
  //  - mtype determines which type of transaction is occurring
  //  - mdone is raised once the transaction is complete, and reset on the
  //    falling edge of mreq
  input wire mreq,
  input wire[2:0] mtype,
  output reg mdone,

  // Handshaking pins
  //  - rdy is set when there is something on the bus for the slave to do
  //  - ack is sent by the slave when it has read from/written to the bus
  //  - bus_ctrl is used to indicate what the slave should do
  input wire ack,
  output reg rdy,
  output reg [1:0] bus_ctrl,

  // Hardware bus
  input  wire [7:0] bus_in,
  output reg  [7:0] bus_out
);

  `include "params.vh"

  localparam [1:0] // Bus control output values
    ADDR0 = 0,
    ADDR1 = 1,
    /* ADDR2 = 2, */
    DATA = 3;

  localparam [3:0] // Bus controller states
    IDLE        = 0,
    ADDR0_WRITE = 1,
    ADDR0_WAIT  = 2,
    ADDR1_WRITE = 3,
    ADDR1_WAIT  = 4,
    WDATA_DO    = 5,
    WDATA_WAIT  = 6,
    RDATA_DO    = 7,
    RDATA_WAIT  = 8;

  reg [3:0] controller_state;

  // Detect positive edge on mreq, used in starting state to kick off a bus
  // transaction.
  reg mreq_dly;
  reg mreq_dly2;
  wire mreq_posedge;
  wire mreq_negedge;
  assign mreq_posedge = mreq & ~mreq_dly2;
  assign mreq_negedge = ~mreq & mreq_dly2;
  always @(posedge clk) begin
    if (reset) begin
      mreq_dly <= 0;
      mreq_dly2 <= 0;
    end else begin
      mreq_dly <= mreq;
      mreq_dly2 <= mreq_dly;
    end
  end

  // Detect positive edge on ack, used to detect when slave is ready to
  // continue transaction.
  reg ack_dly;
  reg ack_dly2;
  wire ack_posedge;
  wire ack_negedge;
  assign ack_posedge = ack & ~ack_dly2;
  assign ack_negedge = ~ack & ack_dly2;
  always @(posedge clk) begin
    if (reset) begin
      ack_dly <= 0;
      ack_dly2 <= 0;
    end else begin
      ack_dly <= ack;
      ack_dly2 <= ack_dly;
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      mdone <= 0;
      controller_state <= IDLE;
      rdy <= 0;
      bus_ctrl <= 0;
    end else begin
      case(controller_state)
        // If we were IDLE and there's a new mreq, we need to begin
        // a transaction. Which state we transition to depends on what kind of
        // transaction we are doing.
        //  - R/W char
        IDLE: begin
          mdone <= 0;
          if (mreq_posedge) begin
            case (mtype)
              RDATA: controller_state <= ADDR0_WRITE;
              WDATA: controller_state <= ADDR0_WRITE;
              RCHAR: controller_state <= RDATA_DO;
              WCHAR: controller_state <= WDATA_DO;
              PROGN: controller_state <= RDATA_DO;
              PROGP: controller_state <= RDATA_DO;
            endcase
          end
        end

        ADDR0_WRITE: begin
          bus_out <= addr[7:0];
          bus_ctrl <= ADDR0;
          rdy <= 1;
          controller_state <= ADDR0_WAIT;
        end
        ADDR0_WAIT: begin
          if (ack_posedge) begin
            controller_state <= ADDR1_WRITE;
            rdy <= 0;
          end
        end

        ADDR1_WRITE: begin
          bus_out <= addr[15:8];
          bus_ctrl <= ADDR1;
          rdy <= 1;
          controller_state <= ADDR1_WAIT;
        end
        ADDR1_WAIT: begin
          if (ack_posedge) begin
            rdy <= 0;
            case (mtype)
              RDATA: controller_state <= RDATA_DO;
              WDATA: controller_state <= WDATA_DO;

              // Should be impossible to end up here with these mtypes...
              RCHAR: controller_state <= RDATA_DO;
              WCHAR: controller_state <= WDATA_DO;
              PROGN: controller_state <= RDATA_DO;
              PROGP: controller_state <= RDATA_DO;
            endcase
          end
        end

        WDATA_DO: begin
          bus_out <= data_in;
          bus_ctrl <= DATA;
          rdy <= 1;
          controller_state <= WDATA_WAIT;
        end
        WDATA_WAIT: begin
          if (ack_posedge) begin
            controller_state <= IDLE;
            rdy <= 0;
            mdone <= 1;
          end
        end

        RDATA_DO: begin
          bus_ctrl <= DATA;
          rdy <= 1;
          controller_state <= RDATA_WAIT;
        end
        RDATA_WAIT: begin
          if (ack_posedge) begin
            data_out <= bus_in;
            controller_state <= IDLE;
            rdy <= 0;
            mdone <= 1;
          end
        end
      endcase
    end
  end

endmodule

