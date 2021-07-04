/*
Modulo de unidad de control, para nodos de medicion de latencia

Hans Lehnert
Universidad Tecnica Federico Santa Maria
IPD432: Diseño Avanzado de Sistemas Digitales

-------------------------------------------------------------------------------

Entradas
	clk:                    Reloj principal
	rst:                    Señal de reset
	mac_address:            Direccion MAC del dispositivo
	rx_data:                Datos recibidos (interfaz para modulo UART)
	rx_ready:               Indica que el dato recibido es valido
	                        (interfaz para modulo UART)
	measurement_data:       Dato de medicion
	measurement_send:       Indica que el dato de medicion esta listo para ser 
	                        enviado
	bytes_in:               Reporte de bytes recibidos
	bytes_out:              Reporte de bytes enviados

Salidas:
	config_packet_size:     Registro de configuracion para el tamaño de paquete
	config_packet_interval: Registro de configuracion para el intervalo entre
	                        envios de paquetes
	config_packet_dst:      Registro de configuracion para el nodo destino de
	                        los paquetes de medicion
	config_custom:          Registro para habilitar paquetes con contenido
	                        definido por el usuario
	tx_data:                Dato a enviar (interfaz para modulo UART)
	tx_send:                Indica que el dato a enviar esta listo para ser
	                        enviado (interfaz para modulo UART)
	rx_read:                Indica que el dato recibido a sido leido (interfaz
	                        para modulo UART)
	pkt_addr:               Direccion de memoria a escribir para memoria de
	                        contenido de paquetes
	pkt_data:               Dato a escribir en memoria para contenido de
	                        paquetes
	pkt_we:                 Habilitacion de escritura para memoria de contenido
	                        de paquetes

Funcionamiento
	La funcion del modulo es controlar la configuracion del modulo generador de
	paquetes y enviar las mediciones a un dispositivo externo. Para esto, el
	modulo posee 4 registros que pueden ser leidos y escritos mediante interfaz
	serial por un sistema de comandos.

	El modulo actua como un dispositivo esclavo. Para enviar una respuesta
	requiere primero haber recibido una pregunta (comando). Por tanto, para el
	envío de mediciones, se requiere que estas sean almacenadas, de manera de
	no perder datos en caso en que las preguntas no sean lo suficientemente
	frecuentes.

*/

`include "measurer_def.vh"

module control_unit(
	input clk,
	input rst,

	//Registros de configuracion
	output reg [10:0] config_packet_size = 10'd512,
	output reg [15:0] config_packet_interval = 15'd1000,
	output reg [7:0] config_packet_dst = 8'hFF,
	output reg config_custom = 0,

	//Direccion MAC del nodo
	input [47:0] mac_address,

	//Salida de datos (UART serial)
	output reg [7:0] tx_data,
	output tx_send,

	//Recepcion de datos (UART serial)
	input [7:0] rx_data,
	input rx_ready,
	output reg rx_read,

	//Memoria de paquete definido por usuario
	output [10:0] pkt_addr,
	output [7:0] pkt_data,
	output pkt_we,

	//Datos a retransmitir
	input [7:0] measurement_data,
	input measurement_send,

	//Mediciones de tasas de transferencia
	input [63:0] bytes_in,
	input [63:0] bytes_out
	);

	localparam STATE_IDLE               = 0;
	localparam STATE_DECODE_CMD         = 1;
	localparam STATE_GET                = 2;
	localparam STATE_SET                = 3;
	localparam STATE_LOAD_LENGTH        = 4;
	localparam STATE_LOAD_DATA          = 5;
	localparam STATE_MEASUREMENT_LENGTH = 6;
	localparam STATE_MEASUREMENT_DATA   = 7;

	///////////////////////////////////////////////////////////////////////////
	//Senales
	///////////////////////////////////////////////////////////////////////////

	reg [2:0] state;
	reg [2:0] next_state;

	reg [11:0] counter;
	reg [11:0] next_counter;

	reg [7:0] command;
	reg [3:0] message_length;

	//Buffers de contadores de bytes enviados/recibidos
	reg [63:0] bytes_in_buffer;
	reg [63:0] bytes_out_buffer;

	//Memoria FIFO
	wire [11:0] fifo_rd_data_count;
	wire [11:0] fifo_wr_data_count;
	wire [7:0] fifo_dout;
	wire fifo_rd;
	wire fifo_wr;
	wire fifo_full;
	wire fifo_empty;

	reg [11:0] fifo_ack_data_count;

	///////////////////////////////////////////////////////////////////////////
	//Modulos
	///////////////////////////////////////////////////////////////////////////

	//Memoria FIFO para almacenar mediciones
	fifo measurement_fifo(
		.wr_clk(clk),
		.rd_clk(clk),
		.rst(rst),
		.din(measurement_data),
		.dout(fifo_dout),
		.wr_en(fifo_wr),
		.rd_en(fifo_rd),
		.full(fifo_full),
		.empty(fifo_empty),
		.wr_data_count(fifo_wr_data_count),
		.rd_data_count(fifo_rd_data_count)
	);

	///////////////////////////////////////////////////////////////////////////
	//Logica combinacional
	///////////////////////////////////////////////////////////////////////////
	assign tx_send = state == STATE_GET ||
	                 state == STATE_MEASUREMENT_LENGTH ||
	                 state == STATE_MEASUREMENT_DATA;

	assign fifo_rd = state == STATE_MEASUREMENT_DATA;
	assign fifo_wr = measurement_send && !fifo_full;

	assign pkt_data = rx_data;
	assign pkt_addr = counter[10:0];
	assign pkt_we = rx_ready && state == STATE_LOAD_DATA;

	always @(*) begin
		//Dato de respuesta para comandos GET
		if (state == STATE_GET) begin
			case (command)
				`CMD_GET_ID:
					tx_data = `NODE_ID;

				`CMD_GET_VERSION:
					tx_data = counter == 0 ? `NODE_VERSION_MAJOR
					                       : `NODE_VERSION_MINOR;

				`CMD_GET_PRECISION:
					tx_data = (`PRECISION >> {12'd3 - counter, 3'b0}) & 8'hFF;

				`CMD_GET_MAC_ADDRESS:
					tx_data = (mac_address >> {12'd5 - counter, 3'b0}) & 8'hFF;

				`CMD_GET_PACKET_SIZE:
					tx_data = counter == 0 ? config_packet_size[10:8]
					                       : config_packet_size[7:0];

				`CMD_GET_PACKET_INTERVAL:
					tx_data = counter == 0 ? config_packet_interval[15:8]
					                       : config_packet_interval[7:0];

				`CMD_GET_PACKET_DST:
					tx_data = config_packet_dst;

				`CMD_GET_CUSTOM_PACKET:
					tx_data = config_custom;

				`CMD_GET_BYTES_IN:
					tx_data = (bytes_in_buffer >> {12'd7 - counter, 3'b0}) & 8'hFF;

				`CMD_GET_BYTES_OUT:
					tx_data = (bytes_out_buffer >> {12'd7 - counter, 3'b0}) & 8'hFF;

				default:
					tx_data = 0;
			endcase
		end
		//Envio de cantidad de datos de mediciones
		else if (state == STATE_MEASUREMENT_LENGTH) begin 
			tx_data = counter == 0 ? fifo_ack_data_count[11:8]
					               : fifo_ack_data_count[7:0];
		end
		//Envio de mediciones
		else if (state == STATE_MEASUREMENT_DATA) begin
			tx_data = fifo_dout;
		end
		else begin
			tx_data = 0;
		end

		//Largo de respuesta de comandos GET y SET
		case (command)
			`CMD_GET_ID:
				message_length = 4'h1;
			`CMD_GET_VERSION:
				message_length = 4'h2;
			`CMD_GET_PRECISION:
				message_length = 4'h4;
			`CMD_GET_MAC_ADDRESS:
				message_length = 4'h6;
			`CMD_GET_PACKET_SIZE,
			`CMD_SET_PACKET_SIZE:
				message_length = 4'h2;
			`CMD_GET_PACKET_INTERVAL,
			`CMD_SET_PACKET_INTERVAL:
				message_length = 4'h2;
			`CMD_GET_PACKET_DST,
			`CMD_SET_PACKET_DST:
				message_length = 4'h1;
			`CMD_GET_CUSTOM_PACKET,
			`CMD_SET_CUSTOM_PACKET:
				message_length = 4'h1;
			`CMD_GET_BYTES_IN,
			`CMD_GET_BYTES_OUT:
				message_length = 4'h8;
			`CMD_LOAD_CUSTOM_DATA:
				message_length = 4'h2;
			`CMD_MEASUREMENTS:
				message_length = 4'h2; //Largo de el dato de cantidad de datos
			default:
				message_length = 0;
		endcase
		
		//Valor siguiente del contador
		next_counter = counter;

		if (state != next_state)
			next_counter = 0;
		else if ((state != STATE_SET &&
			      state != STATE_LOAD_LENGTH &&
			      state != STATE_LOAD_DATA) || 
		         ((state == STATE_SET || 
		           state == STATE_LOAD_LENGTH ||
		           state == STATE_LOAD_DATA) && rx_ready))
			next_counter = counter + 1'b1;
	end

	///////////////////////////////////////////////////////////////////////////
	//Lógica secuencial
	///////////////////////////////////////////////////////////////////////////

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			counter <= 0;
			command <= 0;
			config_packet_size <= 10'd512;
			config_packet_interval <= 15'd1000;
			config_packet_dst <= 8'hFF;
			config_custom <= 0;
			fifo_ack_data_count <= 0;
			bytes_in_buffer <= 0;
			bytes_out_buffer <= 0;
		end
		else begin
			counter <= next_counter;

			//Recepcion de comando
			if (state == STATE_IDLE && rx_ready)
				command <= rx_data;

			//Escritura de registros
			if (state == STATE_SET && rx_ready) begin
				case (command)
					`CMD_SET_PACKET_SIZE:
						config_packet_size <= {config_packet_size, rx_data};
					`CMD_SET_PACKET_INTERVAL:
						config_packet_interval <= {config_packet_interval, rx_data};
					`CMD_SET_PACKET_DST:
						config_packet_dst <= rx_data;
					`CMD_SET_CUSTOM_PACKET:
						config_custom <= rx_data[0];
				endcase
			end

			//Carga de contenido de paquetes definido por usuario
			if (state == STATE_LOAD_LENGTH && rx_ready)
				config_packet_size <= {config_packet_size, rx_data};

			//Se lleva la cuenta de cuantas mediciones completas se encuentran
			//en la memoria fifo, pare evitar enviar mediciones parcialmente
			//incompletas
			if (state == STATE_IDLE &&
				(fifo_rd_data_count - fifo_ack_data_count) >= `MEASUREMENT_SIZE)
				fifo_ack_data_count <= fifo_ack_data_count + `MEASUREMENT_SIZE;
			else if (state == STATE_MEASUREMENT_DATA && next_state == STATE_IDLE)
				fifo_ack_data_count <= 0;


			//Almacenar los contadores de bytes enviados/recibidos para evitar
			//problemas en caso que aumente durante la transmisión
			if (state == STATE_IDLE) begin
				bytes_in_buffer <= bytes_in;
				bytes_out_buffer <= bytes_out;
			end

			//Se almacena la cantidad de datos en la memoria FIFO, para evitar
			//problemas en caso de que se escriban nuevos datos tras haber
			//enviado ya la cantidad de datos en el buffer
			//if (state == STATE_IDLE)
			//	fifo_ack_data_count_buffer <= fifo_empty ?
			//	                              12'b0 : fifo_ack_data_count;

			//Bandera de lecura de dato por interfaz serial,
			//el valor es usado en el ciclo en que llega
			if (rx_ready)
				rx_read <= 1;
			else
				rx_read <= 0;
		end
	end

	///////////////////////////////////////////////////////////////////////////
	//Maquina de estados
	///////////////////////////////////////////////////////////////////////////
	always @(*) begin
		next_state = state;

		case (state)
			STATE_IDLE: begin
				if (rx_ready) begin
					next_state = STATE_DECODE_CMD;
				end
			end

			STATE_DECODE_CMD: begin
				case (command)
					`CMD_GET_ID,
					`CMD_GET_VERSION,
					`CMD_GET_PRECISION,
					`CMD_GET_MAC_ADDRESS,
					`CMD_GET_PACKET_SIZE,
					`CMD_GET_PACKET_INTERVAL,
					`CMD_GET_PACKET_DST,
					`CMD_GET_CUSTOM_PACKET,
					`CMD_GET_BYTES_IN,
					`CMD_GET_BYTES_OUT:
						next_state = STATE_GET;
					`CMD_SET_PACKET_SIZE,
					`CMD_SET_PACKET_INTERVAL,
					`CMD_SET_PACKET_DST,
					`CMD_SET_CUSTOM_PACKET:
						next_state = STATE_SET;
					`CMD_LOAD_CUSTOM_DATA:
						next_state = STATE_LOAD_LENGTH;
					`CMD_MEASUREMENTS:
						next_state = STATE_MEASUREMENT_LENGTH;
					default:
						next_state = STATE_IDLE;
				endcase
			end

			STATE_GET: begin
				if (counter == message_length - 1'b1)
					next_state = STATE_IDLE;
			end

			STATE_SET: begin
				if (counter == message_length)
					next_state = STATE_IDLE;
			end

			STATE_LOAD_LENGTH: begin
				if (counter == message_length)
					next_state = STATE_LOAD_DATA;
			end

			STATE_LOAD_DATA: begin
				if (counter == config_packet_size)
					next_state = STATE_IDLE;
			end

			STATE_MEASUREMENT_LENGTH: begin
				if (counter == message_length - 1'b1) begin
					if (fifo_ack_data_count == 0) begin
						next_state = STATE_IDLE;
					end
					else begin
						next_state = STATE_MEASUREMENT_DATA;
					end
				end
			end

			STATE_MEASUREMENT_DATA: begin
				if (counter == fifo_ack_data_count - 1'b1) begin
					next_state = STATE_IDLE;
				end
			end
		endcase
	end

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state <= STATE_IDLE;
		end
		else begin
			state <= next_state;
		end
	end

endmodule