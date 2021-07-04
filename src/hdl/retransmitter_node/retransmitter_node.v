///////////////////////////////////////////////////////////////////////////////
//Nodo de retransmision de datos mediante interfaz Ethernet
//
//Hans Lehnert
//Universidad Tecnica Federico Santa Maria
//IPD432: Diseño Avanzado de Sistemas Digitales
///////////////////////////////////////////////////////////////////////////////

module retransmitter_node(
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
	input [3:0] phy_rx_data

	//input phy_col,
	//input phy_crs
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

	//Señales para interfaz de transmisión
	reg [7:0] mac_tx_data;
	reg mac_tx_dvld;
	wire mac_tx_ack;
	wire mac_tx_underrun;

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

	wire [3:0] rgmii_status;

	//Señales FIFO rx
	wire [7:0] fifo_rx_data_wr;
	wire [7:0] fifo_rx_data_rd;
	wire fifo_rx_rst;
	wire fifo_rx_write;
	wire fifo_rx_read;
	wire fifo_rx_empty;
	wire fifo_rx_last;

	//Señales FIFO tx
	wire [7:0] fifo_tx_data_wr;
	wire [7:0] fifo_tx_data_rd;
	wire fifo_tx_write;
	reg fifo_tx_read;
	wire fifo_tx_empty;
	wire fifo_tx_last;

	wire data_ready;

	//Estado
	reg [1:0] tx_state = 0;
	reg [1:0] next_tx_state;

	assign fifo_rx_rst = rst | mac_rx_badframe;
	assign fifo_rx_data_wr = mac_rx_data;
	assign fifo_rx_write = mac_rx_dvld;

	assign led = {4'b0, rgmii_status};
	
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
        .RST      (rst),
        // Outputs
        .CLKOUT0  (pll_clk_0),
        .CLKOUT1  (pll_clk_1),
        // Status
        .LOCKED   (pll_locked)
    );

    //BUFGMUX clk_mux(.I0(pll_clk_0), .I1(pll_clk_1), .O(clk_sel), .S(sw[7]));
    BUFG clk_bufg_0 (.I(pll_clk_0), .O(clk_sel));
    BUFG clk_bufg_1 (.I(phy_rx_clk), .O(rx_clk));
    //INV clk_inv_1 (.I(clk_sel), .O(clk_sel_inv));

    /*ODDR2 clk_oddr_tx ( //Necesario para sacar reloj por pin de salida
    	.Q(phy_gtx_clk),
    	.C0(clk_sel),
    	.C1(clk_sel_inv),
    	.CE(1'b1),
    	.D0(1'b0),
    	.D1(1'b1),
    	.R(1'b0),
    	.S(1'b0)
    );*/

    //Modulo MAC
	gig_eth_mac mac(
		.reset(rst),
		.tx_clk(clk_sel),
		.rx_clk(rx_clk),

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
		.rx_clk(rx_clk),

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
		.rgmii_rx_data(phy_rx_data),

		.status(rgmii_status)
	);

	//Memoria FIFO
	fifo rx_queue(
		.wr_clk(phy_rx_clk),
		.rd_clk(clk_sel),
		.rst(fifo_rx_rst),
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
		.rst(rst | mac_tx_underrun),
		.din(fifo_tx_data_wr),
		.dout(fifo_tx_data_rd),
		.wr_en(fifo_tx_write),
		.rd_en(fifo_tx_read),
		.empty(fifo_tx_empty),
		.almost_empty(fifo_tx_last)
	);

	retransmitter mac_retransmitter(
		.clk(clk_sel),
		.rst(rst),

		.config_check_type(sw[7]),
		.config_broadcast_reply(sw[6]),
		.config_id(sw[3:0]),

		.rx_data(fifo_rx_data_rd),
		.rx_read(fifo_rx_read),
		.rx_empty(fifo_rx_empty),
		.rx_last(fifo_rx_last),

		.tx_data(fifo_tx_data_wr),
		.tx_write(fifo_tx_write),

		.abort(mac_tx_underrun)
	);

	///////////////////////////////////////////////////////////////////////////
	//Logica principal
	///////////////////////////////////////////////////////////////////////////

	//Envío de paquetes en cola de transmision

	localparam TX_STATE_IDLE  = 0;
	localparam TX_STATE_BEGIN = 1;
	localparam TX_STATE_SEND  = 2;

	always @(*) begin
		mac_tx_dvld = tx_state != TX_STATE_IDLE || mac_tx_underrun;
		fifo_tx_read = (tx_state == TX_STATE_BEGIN && mac_tx_ack) || tx_state == TX_STATE_SEND;
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

	always @(posedge clk_sel or posedge mac_tx_underrun) begin
		if (mac_tx_underrun) begin
			tx_state <= TX_STATE_IDLE;
		end
		else begin
			tx_state <= next_tx_state;
		end
	end

endmodule