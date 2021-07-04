/*
Retransmisor de paquetes Ethernet

Hans Lehnert
Universidad Tecnica Federico Santa Maria
IPD432: Diseño Avanzado de Sistemas Digitales

-------------------------------------------------------------------------------

Entradas
	clk:                    Reloj principal
	rst:                    Reset general
	config_broadcast_reply: Señal de configuracion que habilita que las
	                        respuestas sean enviadas por broadcast, a
	                        diferencia de ser retransmitidas solo a la
	                        direccion de origen
	config_check_type:      Señal de configuracion que permite la retransmision
	                        solo si el campo "Ethertype" corresponde al tipo
	                        utilizado para las mediciones
	config_id:              Configura el indice del nodo, utilizado en la
	                        direccion MAC fuente de los paquetes retransmitidos
	rx_data:                Dato en cola de recepcion (Interfaz con memoria
	                        FIFO)
	rx_empty:               Indica que la cola de recepcion esta vacia
	                        (Interfaz con memoria FIFO)
	rx_last:                Indica que el dato actual es el ultimo en cola
	                        (Interfaz con mamoria FIFO)

Salidas
	rx_read:                Indica que se ha leido el dato actual de la cola
	                        (Interfaz con memoria FIFO)
	tx_data:                Dato a transmitir por interfaz Ethernet
	tx_write:               Indica que el dato en 'tx_data' debe ser
	                        transmitido

Funcionamiento

	La funcion del modulo es la retransmision de datos recibidos mediante una
	interfaz 'Ethernet', ademas de asistir en la medicion de la latencia
	retransmitiendo los paquetes del nodo medidor.

	Durante la retransmision, se revisan que el destino ("dst") y el campo	
	("Ethertype") correspondan a la direccion propia y al tipo utilizado para
	medicion. Ademas se intercambian las direcciones fuente y destino de los
	paquetes.
*/

`include "node_def.vh"

module retransmitter(
	input clk, //125 Mhz para Gigabit Ethernet
	input rst,

	input config_broadcast_reply,
	input config_check_type,
	input [3:0] config_id,

	input [7:0] rx_data,
	input rx_empty,
	output rx_read,
	input rx_last,

	output reg [7:0] tx_data,
	output tx_write,

	output abort
	);

	localparam STATE_IDLE         = 0;
	localparam STATE_READ_DST     = 1;
	localparam STATE_READ_SRC     = 2;
	localparam STATE_READ_TYPE    = 3;
	localparam STATE_SEND_DST     = 4;
	localparam STATE_SEND_SRC     = 5;
	localparam STATE_SEND_TYPE    = 6;
	localparam STATE_SEND_DATA    = 7;
	localparam STATE_ERROR        = 8;

	///////////////////////////////////////////////////////////////////////////
	//Senales
	///////////////////////////////////////////////////////////////////////////

	reg [3:0] state;
	reg [3:0] next_state;

	reg [5:0] counter;
	reg [5:0] next_counter;

	wire [47:0] mac_address = 48'h02_00_00_00_00_00 | config_id;

	reg [47:0] eth_frame_dst;
	reg [47:0] eth_frame_src;
	reg [15:0] eth_frame_type;

	///////////////////////////////////////////////////////////////////////////
	//Logica combinacional
	///////////////////////////////////////////////////////////////////////////

	assign tx_write = state == STATE_SEND_DST ||
	                  state == STATE_SEND_SRC ||
	                  state == STATE_SEND_TYPE ||
	                  state == STATE_SEND_DATA;


	assign rx_read = state == STATE_READ_DST ||
	                 state == STATE_READ_SRC ||
	                 state == STATE_READ_TYPE ||
	                 state == STATE_SEND_DATA ||
	                 state == STATE_ERROR;

	assign abort = state == STATE_ERROR;

	//Envío de datos
	always @(*) begin
		if (state == STATE_SEND_DATA) begin
			tx_data = rx_data;
		end
		else begin
			case (counter)
				//Destination Address
				5'd14: tx_data = config_broadcast_reply ? 8'hFF : eth_frame_src[47:40];
				5'd15: tx_data = config_broadcast_reply ? 8'hFF : eth_frame_src[39:32];
				5'd16: tx_data = config_broadcast_reply ? 8'hFF : eth_frame_src[31:24];
				5'd17: tx_data = config_broadcast_reply ? 8'hFF : eth_frame_src[23:16];
				5'd18: tx_data = config_broadcast_reply ? 8'hFF : eth_frame_src[15:8];
				5'd19: tx_data = config_broadcast_reply ? 8'hFF : eth_frame_src[7:0];

				//Source Address
				5'd20: tx_data = mac_address[47:40];
				5'd21: tx_data = mac_address[39:32];
				5'd22: tx_data = mac_address[31:24];
				5'd23: tx_data = mac_address[23:16];
				5'd24: tx_data = mac_address[15:8];
				5'd25: tx_data = mac_address[7:0];

				//Ethertype
				5'd26: tx_data = (`ETHERNET_TYPE_REPLY >> 8) & 8'hFF;
				5'd27: tx_data = (`ETHERNET_TYPE_REPLY) & 8'hFF;

				//Data
				default: tx_data = 0;
			endcase
		end
	end

	///////////////////////////////////////////////////////////////////////////
	//Maquina de estados
	///////////////////////////////////////////////////////////////////////////
	
	always @(*) begin
		next_state = state;

		case (state)
			STATE_IDLE: begin
				if (!rx_empty)
					next_state = STATE_READ_DST;
			end

			STATE_READ_DST: begin
				if (counter == 5'd5)
					next_state = STATE_READ_SRC;
			end

			STATE_READ_SRC: begin
				if (eth_frame_dst != 48'hFF_FF_FF_FF_FF_FF && eth_frame_dst != mac_address)
					next_state = STATE_ERROR;
				if (counter == 5'd11)
					next_state = STATE_READ_TYPE;
			end

			STATE_READ_TYPE: begin
				if (counter == 5'd13)
					next_state = STATE_SEND_DST;
			end

			STATE_SEND_DST: begin
				if (config_check_type && eth_frame_type != `ETHERNET_TYPE_REQUEST)
					next_state = STATE_ERROR;
				if (counter == 5'd19)
					next_state = STATE_SEND_SRC;
			end

			STATE_SEND_SRC: begin
				if (counter == 5'd25)
					next_state = STATE_SEND_TYPE;
			end

			STATE_SEND_TYPE: begin
				if (counter == 5'd27)
					next_state = STATE_SEND_DATA;
			end

			STATE_SEND_DATA: begin
				if (rx_last)
					next_state = STATE_IDLE;
			end

			STATE_ERROR: begin
				if (rx_last)
					next_state = STATE_IDLE;
			end
		endcase

		if (state != STATE_IDLE) begin
			next_counter = counter + 1'b1;
		end
		else begin
			next_counter = 0;
		end
	end

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state <= STATE_IDLE;
			counter <= 0;

			eth_frame_dst <= 0;
			eth_frame_src <= 0;
			eth_frame_type <= 0;
		end
		else begin
			state <= next_state;
			counter <= next_counter;

			if (state == STATE_READ_DST)
				eth_frame_dst <= {eth_frame_dst[39:0], rx_data};
			if (state == STATE_READ_SRC)
				eth_frame_src <= {eth_frame_src[39:0], rx_data};
			if (state == STATE_READ_TYPE)
				eth_frame_type <= {eth_frame_type[7:0], rx_data};
		end
	end
endmodule