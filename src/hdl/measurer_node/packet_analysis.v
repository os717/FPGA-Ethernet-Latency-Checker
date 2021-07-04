/*
Analizador de paquetes Ethernet

Hans Lehnert
Universidad Tecnica Federico Santa Maria
IPD432: Diseño Avanzado de Sistemas Digitales

-------------------------------------------------------------------------------

Entradas
	clk:          Reloj principal
	rst:          Reset general
	global_timer: Reloj global (contador) utilizado para mediciones de tiempo
	mac_address:  Direccion MAC del dispositivo
	rx_data:      Dato en cola de recepcion (Interfaz con memoria FIFO)
	rx_empty:     Indica si la cola de recepcion esta vacia (Interfaz con
	              memoria FIFO)

Salidas
	rx_read:      Indica que ya se leyo el dato de la cola (Interfaz con
	              memoria FIFO)
	tx_data:      Dato a enviar (Interfaz con UART serial)
	tx_send:      Indica que el dato a enviar es valido (Interfaz con UART
	              serial)

Funcionamiento
	El modulo analiza los paquetes recibidos por la interfaz Ethernet y envia
	mediciones de latencia mediante la interfaz uart.

	El analisis consiste en revisar el campo "dst", que el paquete esté
	dirigido al nodo, y el campo "Ethertype" para verificar que es un paquete
	de medicion. Ademas se extraen otros datos de interes que son la direccion
	fiente ("src"), marca de tiempo y numero de secuencia.

	Las mediciones son enviadas como 9 bytes:
		* la medicion de tiempo, correspondiente a la diferencia entre la marca
		  de tiempo y el contador global (4 bytes)
		* el numero de secuencia (4 bytes)
		* el indice del nodo (1 byte)
*/

`include "node_def.vh"

module packet_analyzer(
	input clk,
	input rst,

	input [31:0] global_timer,
	input [47:0] mac_address,

	input [7:0] rx_data,
	input rx_empty,
	output rx_read,

	output reg [7:0] tx_data,
	output tx_send
	);

	localparam STATE_IDLE         = 0;
	localparam STATE_DST          = 1;
	localparam STATE_SRC          = 2;
	localparam STATE_TYPE         = 3;
	localparam STATE_TIMESTAMP    = 4;
	localparam STATE_SEQUENCE     = 5;
	localparam STATE_EMPTY_BUFFER = 6;
	localparam STATE_SEND_DATA    = 7;

	///////////////////////////////////////////////////////////////////////////
	//Senales
	///////////////////////////////////////////////////////////////////////////

	reg [2:0] state;
	reg [2:0] next_state;

	reg [3:0] counter;
	reg [3:0] next_counter;

	reg [47:0] eth_frame_dst;
	reg [7:0] eth_frame_src; //Solo interesa el último byte
	reg [15:0] eth_frame_type;
	reg [31:0] packet_timestamp;
	reg [31:0] packet_sequence;

	reg [31:0] arrival_timestamp;

	reg [7:0] error_code;
	reg [7:0] next_error_code;

	wire [31:0] latency;

	///////////////////////////////////////////////////////////////////////////
	//Logica combinacional
	///////////////////////////////////////////////////////////////////////////
	assign tx_send = state == STATE_SEND_DATA;

	assign rx_read = state != STATE_IDLE && !rx_empty;
	assign latency = arrival_timestamp - packet_timestamp;

	always @(*) begin
		case (counter)
			4'h0:    tx_data = latency[31:24];
			4'h1:    tx_data = latency[23:16];
			4'h2:    tx_data = latency[15:8];
			4'h3:    tx_data = latency[7:0];

			4'h4:    tx_data = packet_sequence[31:24];
			4'h5:    tx_data = packet_sequence[23:16];
			4'h6:    tx_data = packet_sequence[15:8];
			4'h7:    tx_data = packet_sequence[7:0];

			default: tx_data = eth_frame_src;
		endcase
	end

	///////////////////////////////////////////////////////////////////////////
	//Maquina de estados
	///////////////////////////////////////////////////////////////////////////

	always @(*) begin
		next_state = state;
		next_counter = counter;

		case (state)
			STATE_IDLE: begin
				if (!rx_empty)
					next_state = STATE_DST;
			end

			STATE_DST: begin
				if (counter == 10'd5) begin
					next_state = STATE_SRC;
				end
			end

			STATE_SRC: begin
				if (eth_frame_dst != 48'hFF_FF_FF_FF_FF_FF &&
					eth_frame_dst != mac_address) begin
					next_state = STATE_EMPTY_BUFFER;
				end
				if (counter == 10'd5) begin
					next_state = STATE_TYPE;
				end
			end

			STATE_TYPE: begin
				if (counter == 10'd1) begin
					next_state = STATE_TIMESTAMP;
				end
			end

			STATE_TIMESTAMP: begin
				if (eth_frame_type != `ETHERNET_TYPE_REPLY) begin
					next_state = STATE_EMPTY_BUFFER;
				end
				else if (counter == 10'd3) begin
					next_state = STATE_SEQUENCE;
				end
			end

			STATE_SEQUENCE: begin
				if (counter == 10'd3) begin
					next_state = STATE_SEND_DATA;
				end
			end

			STATE_SEND_DATA: begin
				if (counter == 10'd8) begin
					next_state = STATE_EMPTY_BUFFER;
				end
			end

			STATE_EMPTY_BUFFER: begin
				if (rx_empty) begin
					next_state = STATE_IDLE;
				end
			end
		endcase

		if (next_state != state)
			next_counter = 0;
		else
			next_counter = counter + 1'b1;
	end

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state <= STATE_IDLE;
			counter <= 0;

			arrival_timestamp <= 0;
			eth_frame_dst <= 0;
			eth_frame_src <= 0;
			eth_frame_type <= 0;
			packet_sequence <= 0;
		end
		else begin
			state <= next_state;
			counter <= next_counter;

			if (state == STATE_IDLE)
				arrival_timestamp <= global_timer;

			if (state == STATE_DST)
				eth_frame_dst <= {eth_frame_dst, rx_data};
			if (state == STATE_SRC)
				eth_frame_src <= rx_data;
			if (state == STATE_TYPE)
				eth_frame_type <= {eth_frame_type, rx_data};
			if (state == STATE_TIMESTAMP)
				packet_timestamp <= {packet_timestamp, rx_data};
			if (state == STATE_SEQUENCE)
				packet_sequence <= {packet_sequence, rx_data};
		end
	end
endmodule