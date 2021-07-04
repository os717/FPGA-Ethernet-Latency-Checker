/*
Nodo de medición de latencia mediante interfaz Ethernet

Hans Lehnert
Universidad Tecnica Federico Santa Maria
IPD432: Diseño Avanzado de Sistemas Digitales
*/

module measurer_node(
	//Main clk
	input clk,

	//Buttons
	input btn,

	//Switches
	input [7:0] sw,

	//LEDs
	output [7:0] led,

	//Ethernet PHY
	output phy_rst,
	output phy_tx_clk,
	output phy_tx_ctl,
	output [3:0] phy_tx_data,

	input phy_rx_clk,
	input phy_rx_ctl,
	input [3:0] phy_rx_data,

	//input phy_col,
	//input phy_crs,

	//UART
	input uart_rx,
	output uart_tx
	);

	///////////////////////////////////////////////////////////////////////////
	//Señales
	///////////////////////////////////////////////////////////////////////////
	
	//Relojes
	wire pll_clk_0;
	wire pll_clk_1;
	wire clk_sel;
	wire clk_sel_inv;

	//Reset general
	wire rst = ~btn;

	assign phy_rst = ~rst;

	//Timer global
	//para mediciones de tiempo
	reg [31:0] global_timer = 0;

	//Direccion MAC del dispositivo, configurable por switch
	//Primer byte 02 para indicar direccion administrada localmente
	wire [47:0] mac_address = 48'h02_00_00_00_01_00 | sw;

	//Señales para interfaz de transmisión
	reg [7:0] mac_tx_data;
	reg mac_tx_dvld;
	wire mac_tx_ack;
	wire mac_tx_underrun = 0;

	//Señales para interfaz de recepción
	wire [7:0] mac_rx_data;
	wire mac_rx_dvld;
	wire mac_rx_goodframe;
	wire mac_rx_badframe;

	//Señales para interfaz GMII (salida de módulo MAC)
	wire gmii_tx_en;
	wire gmii_tx_er;
	wire [7:0] gmii_tx_data;

	wire gmii_rxdv;
	wire gmii_rxer;
	wire [7:0] gmii_rx_data;

	//Señales FIFO rx
	wire [7:0] fifo_rx_data_wr;
	wire [7:0] fifo_rx_data_rd;
	wire fifo_rx_write;
	wire fifo_rx_read;
	wire fifo_rx_empty;
	wire fifo_rx_last;

	assign fifo_rx_data_wr = mac_rx_data;
	assign fifo_rx_write = mac_rx_dvld;

	//Señales FIFO tx
	wire [7:0] fifo_tx_data_wr;
	wire [7:0] fifo_tx_data_rd;
	wire fifo_tx_write;
	reg fifo_tx_read;
	wire fifo_tx_empty;
	wire fifo_tx_last;

	//Señales memoria de paquete definido por usuario
	wire [10:0] mem_pkt_addr_r;
	wire [10:0] mem_pkt_addr_w;
	wire [7:0] mem_pkt_data_r;
	wire [7:0] mem_pkt_data_w;
	wire mem_pkt_we;

	//Señales UART serial
	wire [7:0] uart_tx_data;
	wire uart_tx_send;

	wire [7:0] uart_rx_data;
	wire uart_rx_ready;
	wire uart_rx_read;

	//Señales de configuracion
	wire [10:0] config_packet_size;
	wire [15:0] config_packet_interval;
	wire [7:0] config_packet_dst;
	wire config_custom;

	//Direccion destino
	//En el caso en que el destino es 8'hFF se escoje la direccion de
	//broadcast, en otro caso se utiliza la direccion localmente administrada
	//de los nodos retransmisores
	wire [47:0] packet_dst = config_packet_dst == 8'hFF ?
	                         48'hFF_FF_FF_FF_FF_FF :
	                         (48'h02_00_00_00_00_00 | config_packet_dst);

	//Señales de datos de medicion de latencia
	wire [7:0] measurement_data;
	wire measurement_send;

	//Señales de medicion de bytes
	wire [63:0] bytes_in;
	wire [63:0] bytes_out;

	//Estado
	reg [1:0] tx_state = 0;
	reg [1:0] next_tx_state;

	assign led = sw;

	assign phy_tx_clk = pll_clk_1;
	
	///////////////////////////////////////////////////////////////////////////
	//Modulos
	///////////////////////////////////////////////////////////////////////////

	//Generación de relojes para transmisión
	IBUFG pll_in_ibufg(.I(clk), .O(pll_in_clk));

	PLL_BASE #(
        .CLKIN_PERIOD   (10),
        .CLKFBOUT_MULT  (10),
        .CLKOUT0_DIVIDE (8),
        .CLKOUT1_DIVIDE (8),
        .CLKOUT1_PHASE  (90),
        .COMPENSATION("INTERNAL")
    )
    pll_clocks_gen (
        .CLKIN    (pll_in_clk),
        .CLKFBIN  (pll_feedback),
        .CLKFBOUT (pll_feedback),
        .RST      (1'b0),
        // Outputs
        .CLKOUT0  (pll_clk_0),
        .CLKOUT1  (pll_clk_1),
        // Status
        .LOCKED   (pll_locked)
    );

    //BUFGMUX clk_mux(.I0(pll_clk_0), .I1(pll_clk_1), .O(clk_sel), .S(sw[7]));
    BUFG clk_bufg_0 (.I(pll_clk_0), .O(clk_sel));
    //INV clk_inv_1 (.I(clk_sel), .O(clk_sel_inv));

    /*ODDR2 clk_oddr_tx ( //Necesario para sacar reloj por pin de salida
    	.Q(eth_tx_clk),
    	.C0(clk_sel),
    	.C1(clk_sel_inv),
    	.CE(1'b1),
    	.D0(1'b0),
    	.D1(1'b1),
    	.R(1'b0),
    	.S(1'b0)
    );*/

    //Ethernet MAC
	gig_eth_mac mac(
		.reset(rst),
		.tx_clk(clk_sel),
		.rx_clk(phy_rx_clk),

		//Config
		.conf_tx_en(1'b1),
		.conf_tx_no_gen_crc(1'b0),
		.conf_tx_jumbo_en(1'b1),

		.conf_rx_en(1'b1),
		.conf_rx_no_chk_crc(1'b0),
		.conf_rx_jumbo_en(1'b1),

		//TX interface
		.mac_tx_data(mac_tx_data),
		.mac_tx_dvld(mac_tx_dvld),
		.mac_tx_ack(mac_tx_ack),
		.mac_tx_underrun(mac_tx_underrun),

		//RX interface
		.mac_rx_data(mac_rx_data),
		.mac_rx_dvld(mac_rx_dvld),
		.mac_rx_goodframe(mac_rx_goodframe),
		.mac_rx_badframe(mac_rx_badframe),

		//GMII
		.gmii_txd(gmii_tx_data),
		.gmii_txen(gmii_tx_en),
		.gmii_txer(gmii_tx_er),

		.gmii_rxd(gmii_rx_data),
		.gmii_rxdv(gmii_rx_dv),
		.gmii_rxer(gmii_rx_er)
	);

	gmii_to_rgmii mii_converter(
		.tx_clk(clk_sel),
		.rx_clk(phy_rx_clk),

		//GMII
		.gmii_tx_en(gmii_tx_en),
		.gmii_tx_er(gmii_tx_er),
		.gmii_tx_data(gmii_tx_data),

		.gmii_rx_dv(gmii_rx_dv),
		.gmii_rx_er(gmii_rx_er),
		.gmii_rx_data(gmii_rx_data),

		//RGMII
		.rgmii_tx_ctl(phy_tx_ctl),
		.rgmii_tx_data(phy_tx_data),

		.rgmii_rx_ctl(phy_rx_ctl),
		.rgmii_rx_data(phy_rx_data)
	);

	//Memoria FIFO
	fifo rx_queue(
		.wr_clk(phy_rx_clk),
		.rd_clk(clk_sel),
		.rst(rst),
		.din(fifo_rx_data_wr),
		.dout(fifo_rx_data_rd),
		.wr_en(fifo_rx_write),
		.rd_en(fifo_rx_read),
		.empty(fifo_rx_empty),
		.almost_empty(fifo_rx_last)
	);

	fifo tx_queue(
		.wr_clk(clk_sel),
		.rd_clk(clk_sel),
		.rst(rst),
		.din(fifo_tx_data_wr),
		.dout(fifo_tx_data_rd),
		.wr_en(fifo_tx_write),
		.rd_en(fifo_tx_read),
		.empty(fifo_tx_empty),
		.almost_empty(fifo_tx_last)
	);

	//Memoria para almacenar contenido de paquetes definido por el usuario
	memory_block packet_mem(
		.clk(clk_sel),
		.addr_r(mem_pkt_addr_r),
		.addr_w(mem_pkt_addr_w),
		.data_r(mem_pkt_data_r),
		.data_w(mem_pkt_data_w),
		.we(mem_pkt_we));
	defparam packet_mem.SIZE = 2048;

	//Interfaz serial
	uart serial_uart(
		.clk(clk_sel),
		.rst(rst),

		.rx(uart_rx),
		.rx_data(uart_rx_data),
		.rx_ready(uart_rx_ready),
		.rx_read(uart_rx_read),

		.tx(uart_tx),
		.tx_data(uart_tx_data),
		.tx_send(uart_tx_send)
	);
	defparam serial_uart.CLK_FREQ = 125000000;
	defparam serial_uart.BAUDRATE = 115200;

	//Modulo de control
	control_unit cu(
		.clk(clk_sel),
		.rst(rst),

		.config_packet_size(config_packet_size),
		.config_packet_interval(config_packet_interval),
		.config_packet_dst(config_packet_dst),
		.config_custom(config_custom),

		.mac_address(mac_address),

		.rx_data(uart_rx_data),
		.rx_ready(uart_rx_ready),
		.rx_read(uart_rx_read),

		.tx_data(uart_tx_data),
		.tx_send(uart_tx_send),

		.pkt_addr(mem_pkt_addr_w),
		.pkt_data(mem_pkt_data_w),
		.pkt_we(mem_pkt_we),

		.measurement_data(measurement_data),
		.measurement_send(measurement_send),

		.bytes_in(bytes_in),
		.bytes_out(bytes_out)
	);

	//Generador y analizador de tráfico
	packet_generator mac_traffic_gen(
		.clk(clk_sel),
		.rst(rst),

		.global_timer(global_timer),
		.mac_address(mac_address),

		.packet_size(config_packet_size),
		.packet_interval(config_packet_interval),
		.packet_dst(packet_dst),
		.packet_custom(config_custom),

		.pkt_addr(mem_pkt_addr_r),
		.pkt_data(mem_pkt_data_r),

		.tx_data(fifo_tx_data_wr),
		.tx_write(fifo_tx_write)
	);

	packet_analyzer mac_traffic_analysis(
		.clk(clk_sel),
		.rst(rst),

		.global_timer(global_timer),
		.mac_address(mac_address),

		.rx_data(fifo_rx_data_rd),
		.rx_empty(fifo_rx_empty),
		.rx_read(fifo_rx_read),

		.tx_data(measurement_data),
		.tx_send(measurement_send)
	);

	//Medicion de tasa de transferencia
	counter counter_in(
		.clk(phy_rx_clk),
		.rst(rst),
		.enable(gmii_rx_dv),
		.count(bytes_in)
	);
	defparam counter_in.WIDTH = 64;

	counter counter_out(
		.clk(clk_sel),
		.rst(rst),
		.enable(gmii_tx_en),
		.count(bytes_out)
	);
	defparam counter_out.WIDTH = 64;


	///////////////////////////////////////////////////////////////////////////
	//Maquina de estados
	///////////////////////////////////////////////////////////////////////////

	//Envío de datos en cola por modulo MAC

	localparam TX_STATE_IDLE  = 0;
	localparam TX_STATE_BEGIN = 1;
	localparam TX_STATE_SEND  = 2;

	always @(*) begin
		mac_tx_dvld = tx_state != TX_STATE_IDLE;
		fifo_tx_read = (tx_state == TX_STATE_BEGIN && mac_tx_ack) ||
		               tx_state == TX_STATE_SEND;
		mac_tx_data = fifo_tx_data_rd;

		next_tx_state = tx_state;
		case (tx_state)
			TX_STATE_IDLE: begin
				if (!fifo_tx_empty) begin
					next_tx_state = TX_STATE_BEGIN;
				end
			end
			TX_STATE_BEGIN: begin
				if (mac_tx_ack) begin
					next_tx_state = TX_STATE_SEND;
				end
			end
			TX_STATE_SEND:
				if (fifo_tx_last) begin
					next_tx_state = TX_STATE_IDLE;
				end
		endcase
	end

	always @(posedge clk_sel or posedge rst) begin
		if (rst) begin
			tx_state <= TX_STATE_IDLE;
			global_timer <= 0;
		end
		else begin
			tx_state <= next_tx_state;
			global_timer <= global_timer + 31'b1;
		end
	end

endmodule