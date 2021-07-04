/*
UART simple con buffer de transmision

Hans Lehnert Merino
Universidad Técnica Federico Santa Maria

----------------------------------------------------------------------

Entradas
	clk:		Senal de reloj principal
	rst:		Reset general
	rx:			Linea de recepcion
	rx_read:	Indicar que se leyo el dato
	tx_data:	Dato a transmitir
	tx_send:	Agregar datos a cola de transmision

Salidas
	rx_data:	Dato recibido
	rx_ready:	Bandera de recepcion de dato
	tx:			Linea de transmision

Parametros
	BAUDRATE:		Baudrate...
	STOP_BIT:		Numero de bits de stop (0:1 bit, 1:2 bits)
	PARITY:			Paridad (0:sin paridad, 1:par, 2:impar)
	CLK_FREQ:		Frecuencia de la entrada 'clk'
	TX_BUFFER_SIZE:	Tamaño de la cola de transmisión
					(tamaño efectivo = 2 ^ TX_BUFFER_SIZE)

Uso
	Para recibir, cuando 'rx_ready' el valor recibido se puede leer en
	'rx_data'. Para recibir el siguiente dato, se debe poner en alto 'rx_read'
	por al menos un ciclo.

	Para transmitir, mientras 'tx_send' esta en alto, se agrega 'tx_data' a la
	cola de transmision cada ciclo.

Por implementar
	* Tamaño de frame variable
	* Buffer de recepcion
	* Salida de error de recepcion
	* Prevenir overflow de buffer (cuidado!)

*/

module uart(clk, rst, rx, rx_read, rx_data, rx_ready, tx, tx_send, tx_data);
	parameter BAUDRATE = 9600;
	parameter STOP_BIT = 0; //0:1bit 1:2bits
	parameter PARITY = 1; //1:par 2:impar 0:sin paridad
	parameter CLK_FREQ = 100000000;
	parameter TX_BUFFER_SIZE = 10;

	input clk;
	input rst;

	//Puerto RX
	input rx;
	input rx_read;
	output rx_ready;
	output [7:0] rx_data;

	//Puertos TX
	output tx;
	input tx_send;
	input [7:0]tx_data;

	wire clk_rx;
	wire clk_tx;

	wire tx_ready;
	wire rx_error;

	reg [TX_BUFFER_SIZE-1:0] tx_addr_front = ~0;
	reg [TX_BUFFER_SIZE-1:0] tx_addr_back = 0;
	wire [7:0] tx_buffer_data;
	wire tx_send_next;
	wire tx_end;

	assign tx_send_next = tx_addr_front != tx_addr_back;

	//Señales de reloj
	clk_gen clk_receive(.in_clk(clk),
	                 	.out_clk(clk_rx));
	defparam clk_receive.SOURCE_CLK = CLK_FREQ;
	defparam clk_receive.TARGET_CLK = BAUDRATE * 16;

	clk_gen clk_transmit(.in_clk(clk_rx),
	                 	 .out_clk(clk_tx));
	defparam clk_transmit.SOURCE_CLK = BAUDRATE * 16;
	defparam clk_transmit.TARGET_CLK = BAUDRATE;

	//Modulos de transmision y recepcion
	uart_tx uart_transmit(.clk(clk_tx),
	                      .rst(rst),
	                      .send(tx_send_next),
	                      .data(tx_buffer_data),
	                      .tx(tx),
	                      .ready(tx_ready));
	defparam uart_transmit.STOP_BIT = STOP_BIT;
	defparam uart_transmit.PARITY = PARITY;

	uart_rx uart_recieve(.clk(clk_rx),
	                     .rst(rx_read | rst),
	                     .rx(rx),
	                     .data(rx_data),
	                     .ready(rx_ready),
	                     .error(rx_error));
	defparam uart_recieve.STOP_BIT = STOP_BIT;
	defparam uart_recieve.PARITY = PARITY;

	//Buffer de transmision
	memory_block tx_queue(.clk(clk),
	                      .addr_r(tx_addr_front),
	                      .addr_w(tx_addr_back),
	                      .data_r(tx_buffer_data),
	                      .data_w(tx_data),
	                      .we(tx_send));
	defparam tx_queue.SIZE = 1 << TX_BUFFER_SIZE;

	edge_detector edge_tx(clk, tx_ready, tx_end);

	//Manejo de buffer de transmisión
	always @(posedge clk) begin
		if (rst) begin
			tx_addr_front <= 0;
			tx_addr_back <= 0;
		end
		else begin
			if (tx_send)
				tx_addr_back <= tx_addr_back + 1'b1;

			if (tx_end)
				tx_addr_front <= tx_addr_front + 1'b1;
		end
	end
endmodule