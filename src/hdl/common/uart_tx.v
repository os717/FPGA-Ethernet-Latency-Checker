/*
Modulo de transmision serial

Hans Lehnert Merino
Universidad Técnica Federico Santa Maria
*/

module uart_tx(clk, rst, send, data, tx, ready);
	parameter STOP_BIT = 0; //0:1bit 1:2bits
	parameter PARITY = 1; //1:par 2:impar 0:sin paridad

	localparam STATE_IDLE		= 3'd0;
	localparam STATE_STARTBIT	= 3'd1;
	localparam STATE_FRAME		= 3'd2;
	localparam STATE_PARITY		= 3'd3;
	localparam STATE_END		= 3'd4;

	input clk;
	input rst;
	input send;
	input [7:0] data;
	output reg tx;
	output ready;

	reg [2:0] state = 0;
	reg [2:0] next_state;
	reg [2:0] bit_count;
	wire parity_bit;

	assign ready = state == STATE_IDLE;
	assign parity_bit = ^data;

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state <= STATE_IDLE;
			bit_count <= 0;
		end
		else begin
			state <= next_state;

			if (state == STATE_FRAME)
				bit_count <= bit_count + 3'd1;
			else
				bit_count <= 0;
		end
	end

	always @(*) begin
		next_state = state;

		case(state)
		STATE_IDLE:
			if (send)
				next_state = STATE_STARTBIT;

		STATE_STARTBIT:
			next_state = STATE_FRAME;

		STATE_FRAME:
			if (bit_count == 3'd7)
				if (PARITY != 0)
					next_state = STATE_PARITY;
				else if (STOP_BIT)
					next_state = STATE_END;
				else
					next_state = STATE_IDLE;

		STATE_PARITY:
			if (STOP_BIT)
				next_state = STATE_END;
			else
				next_state = STATE_IDLE;

		STATE_END:
			next_state = STATE_IDLE;
		endcase
	end

	always @(*) begin
		case (state)
		STATE_STARTBIT:
			tx = 1'b0;
		STATE_FRAME:
			tx = data[bit_count];
		STATE_PARITY:
			tx = PARITY == 1 ? parity_bit : ~parity_bit;
		default:
			tx = 1'b1;
		endcase
	end

endmodule