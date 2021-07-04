/*
Nodo de retransmision de datos mediante interfaz Ethernet

Hans Lehnert
Universidad Tecnica Federico Santa Maria

-------------------------------------------------------------------------------

Entradas
	clk:             Reloj principal
	rst:             Reset general
	global_timer:    Contador global, para generar marcas de tiempo en
	                 paquetes enviados
	mac_address:     Direccion MAC del dispositivo a enviar como fuente de los
	                 paquetes
	packet_size:     Tamano de contenido de paquetes, sin incluir cabecera
	                 Ethernet, pero incluyendo marca de tiempo
	packet_interval: Tiempo entre envios de paquetes en milisegundos
	                 (sin considerar tiempos de transmision)
	packet_dst:      Direccion MAC destino de los paquetes
	packet_custom:   Poner en alto para utilizar contenido de paquete definido
	                 por el usuario
	pkt_data:        Dato de paquete definido por usuario

Salidas
	tx_data:         Dato a enviar
	tx_write:        Bandera de dato listo para enviar
	pkt_addr:        Indice del dato definido por usuario


Funcionamiento
	Para uso con interfaz MAC, conectar las salidas a memoria FIFO, para su
	transmision.

	Los paquetes generados consisten del encabezado Ethernet (destino, fuente y
	tipo), seguido por 4 bytes correspondientes a una marca de tiempo
	referenciada a un reloj global y un numero de secuencia que identifica al
	paquete. Finalmente se rellena con datos hasta completar el valor indicado
	por 'packet_length' (sin incluir el encabezdao Ethernet).

	En el caso de paquetes definidos por el usuario, se leen 'packet_length'
	datos de 'pkt_data', con 'pkt_addr' indicando la cuenta de datos ya
	transmitidos.

*/

`include "node_def.vh"

module packet_generator(
	input clk,
	input rst,

	input [31:0] global_timer,

	input [47:0] mac_address,

	input [10:0] packet_size,
	input [15:0] packet_interval,
	input [47:0] packet_dst,
	input packet_custom,

	output [10:0] pkt_addr,
	input [7:0] pkt_data,

	output reg [7:0] tx_data,
	output tx_write
	);

	localparam STATE_WAIT           = 0;
	localparam STATE_SEND_DST       = 1;
	localparam STATE_SEND_SRC       = 2;
	localparam STATE_SEND_TYPE      = 3;
	localparam STATE_SEND_TIMESTAMP = 4;
	localparam STATE_SEND_SEQUENCE  = 5;
	localparam STATE_SEND_DATA      = 6;
	localparam STATE_SEND_CUSTOM    = 7;

	///////////////////////////////////////////////////////////////////////////
	//Señales
	///////////////////////////////////////////////////////////////////////////

	reg [2:0] state;
	reg [2:0] next_state;

	reg [10:0] counter;
	reg [10:0] next_counter;

	reg [31:0] timer = 0; //Resolución de ms, para generación de paquetes
	wire clk_timer;

	reg [31:0] timestamp;
	reg [31:0] next_timestamp;

	reg [31:0] sequence;
	reg [31:0] next_sequence;

	///////////////////////////////////////////////////////////////////////////
	//Modulos
	///////////////////////////////////////////////////////////////////////////

	//Timer para la medicion de intervalos de tiempo entre envios de paquetes
	clk_gen clk_ms(
		.in_clk(clk),
		.out_clk(clk_timer)
	);
	defparam clk_ms.SOURCE_CLK = 125000000;
	defparam clk_ms.TARGET_CLK = 1000;

	///////////////////////////////////////////////////////////////////////////
	//Logica combinacional
	///////////////////////////////////////////////////////////////////////////

	assign tx_write = state == STATE_SEND_DST ||
	                  state == STATE_SEND_SRC ||
	                  state == STATE_SEND_TYPE ||
	                  state == STATE_SEND_TIMESTAMP ||
	                  state == STATE_SEND_SEQUENCE ||
	                  state == STATE_SEND_DATA ||
	                  (state == STATE_SEND_CUSTOM && counter != 0);
	//Para el caso del dato definido por usuario se debe esperar un ciclo
	//para que la direccion sea actualizada por la memoria sincronica

	assign pkt_addr = counter;

	//Determinacion de valor de dato a enviar
	always @(*) begin
		case (state)
			STATE_SEND_DST:
				tx_data = (packet_dst >> {11'd5 - counter, 3'b0}) & 8'hFF;
			STATE_SEND_SRC:
				tx_data = (mac_address >> {11'd5 - counter, 3'b0}) & 8'hFF;
			STATE_SEND_TYPE:
				tx_data = (`ETHERNET_TYPE_REQUEST >> {11'd1 - counter, 3'b0}) & 8'hFF;
			STATE_SEND_TIMESTAMP:
				tx_data = (timestamp >> {11'd3 - counter, 3'b0}) & 8'hFF;
			STATE_SEND_SEQUENCE:
				tx_data = (sequence >> {11'd3 - counter, 3'b0}) & 8'hFF;
			STATE_SEND_CUSTOM:
				tx_data = pkt_data;
			default:
				tx_data = 0;
		endcase
	end

	///////////////////////////////////////////////////////////////////////////
	//Maquina de estados
	///////////////////////////////////////////////////////////////////////////

	always @(*) begin
		next_state = state;
		next_timestamp = timestamp;
		next_sequence = sequence;

		case (state)
			STATE_WAIT: begin
				if (timer == 0 && clk_timer) begin
					if (packet_custom)
						next_state = STATE_SEND_CUSTOM;
					else
						next_state = STATE_SEND_DST;
					next_timestamp = global_timer;
				end
			end

			STATE_SEND_DST: begin
				if (counter == 11'd5)
					next_state = STATE_SEND_SRC;
			end

			STATE_SEND_SRC: begin
				if (counter == 11'd5)
					next_state = STATE_SEND_TYPE;
			end

			STATE_SEND_TYPE: begin
				if (counter == 11'd1)
					next_state = STATE_SEND_TIMESTAMP;
			end

			STATE_SEND_TIMESTAMP: begin
				if (counter == 11'd3)
					next_state = STATE_SEND_SEQUENCE;
			end

			STATE_SEND_SEQUENCE: begin
				if (counter == 11'd3)
					next_state = STATE_SEND_DATA;
			end

			STATE_SEND_DATA: begin
				if (counter >= packet_size - 11'd9) begin
				//packet_size - 9 para incluir marca de tiempo, numero de
				//secuencia y compenzar comienzo en 0 de la cuenta
					next_state = STATE_WAIT;
					next_sequence = next_sequence + 1'b1;
				end
			end

			STATE_SEND_CUSTOM: begin
				if (counter >= packet_size) begin
					next_state = STATE_WAIT;
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
			state <= STATE_WAIT;
			counter <= 0;
			timer <= 0;
			timestamp <= 0;
			sequence <= 0;
		end
		else begin
			state <= next_state;
			counter <= next_counter;
			timestamp <= next_timestamp;
			sequence <= next_sequence;

			if (clk_timer) begin
				if (timer < packet_interval - 1) begin
					timer <= timer + 1;
				end
				else begin
					timer <= 0;
				end
			end
		end
	end
endmodule