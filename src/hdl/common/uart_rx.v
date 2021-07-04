/*
Modulo de recepcion serial

Hans Lehnert Merino
Universidad Técnica Federico Santa Maria
*/

module uart_rx(clk, rst, rx, data, ready, error);
	parameter STOP_BIT = 0; //0:1bit 1:2bits
	parameter PARITY = 1; //1:par 2:impar 0:sin paridad

	localparam STATE_IDLE		= 3'd0;
	localparam STATE_STARTBIT	= 3'd1;
	localparam STATE_FRAME		= 3'd2;
	localparam STATE_PARITY		= 3'd3;
	localparam STATE_STOP		= 3'd4;
	localparam STATE_END        = 3'd5;
	localparam STATE_ERROR      = 3'd6;

	input clk; //Debe ser 16 veces el baudrate
	input rst;
	input rx;

	output reg [7:0] data;
	output ready;
	output error;

	reg [2:0] state = 0;
	reg [2:0] next_state;
	reg [2:0] bit_count;
	reg [3:0] frame_count;
	wire parity_bit;

	wire frame_mid;
	wire frame_end;

	assign ready = state == STATE_END || state == STATE_ERROR;
	assign error = state == STATE_ERROR;
	assign parity_bit = ^data;
	assign frame_mid = frame_count == 4'd7;
	assign frame_end = frame_count == 4'd15;

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state <= STATE_IDLE;
			bit_count <= 0;
			frame_count <= 0;
			data <= 0;
		end
		else begin
			state <= next_state;

			if (state != STATE_IDLE)
				frame_count <= frame_count + 4'd1;
			else
				frame_count <= 0;

			//Cuenta de bits recibidos y de stop
			if (state == STATE_FRAME || state == STATE_STOP) begin
				if (frame_end)
					bit_count <= bit_count + 3'd1;
			end
			else begin
				bit_count <= 0;
			end

			//Lectura de dato a mitad del bit
			if (frame_mid && state == STATE_FRAME)
				data[bit_count] <= rx;
		end
	end

	always @(*) begin
		next_state = state;

		//Comienzo de frame serial
		if (state == STATE_IDLE && rx == 0) begin
			next_state = STATE_STARTBIT;
		end

		//Revisar que la entrada sea correcta en la mitad del bit transmitido
		//para compensar retardos de transmisión
		else if (frame_mid) begin
			case(state)
			STATE_STARTBIT:
				if (rx != 0)
					next_state = STATE_ERROR;
			STATE_PARITY:
				if (rx != (PARITY == 1 ? parity_bit : ~parity_bit))
					next_state = STATE_ERROR;
			STATE_STOP:
				if (rx != 1'b1)
					next_state = STATE_ERROR;
				else if (STOP_BIT == 0 || bit_count == 1)
					next_state = STATE_END;
			endcase
		end

		//Transiciones de estado
		else if (frame_end) begin
			case(state)
			STATE_STARTBIT:
				next_state = STATE_FRAME;
			STATE_FRAME:
				if (bit_count == 3'd7) begin
					if (PARITY != 0)
						next_state = STATE_PARITY;
					else
						next_state = STATE_STOP;
				end
			STATE_PARITY:
				next_state = STATE_STOP;
			endcase
		end
	end
endmodule