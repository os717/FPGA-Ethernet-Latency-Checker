///////////////////////////////////////////////////////////////////////////////
//Modulo adapatdor de interfaz GMII a RGMII
//
//Hans Lehnert
//Universidad Tecnica Federico Santa Maria
///////////////////////////////////////////////////////////////////////////////

module gmii_to_rgmii(
	// Clocks
	input tx_clk,
	input rx_clk,

	// GMII
	input gmii_tx_en,
	input gmii_tx_er,
	input [7:0] gmii_tx_data,

	output gmii_rx_dv,
	output gmii_rx_er,
	output [7:0] gmii_rx_data,

	// RGMII
	output rgmii_tx_ctl,
	output [3:0] rgmii_tx_data,

	input rgmii_rx_ctl,
	input [3:0] rgmii_rx_data,

	// In-band Status
	// Bit [0]   Link status:   1 up, 0 down
	// Bit [2:1] Link speed:    00 10Mbps, 01 100Mbps, 10 1000Mbps
	// Bit [3]   Duplex status: 0 half-duplex, 1 full-duplex
	output reg [3:0] status
	);
	

	//El error en RGMII es inverso a GMII
	wire rx_error;
	assign gmii_rx_er = rx_error ^ gmii_rx_dv;

	///////////////////////////////////////////////////////////////////////////
	//Señales de transmisión
	///////////////////////////////////////////////////////////////////////////

	//Señales de control
	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE")
	) oddr_tx_ctl (
		.Q(rgmii_tx_ctl),
		.D1(gmii_tx_en),
		.D2(gmii_tx_en ^ gmii_tx_er),
		.C(tx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	//Datos
	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE")
	) oddr_tx_data_0 (
		.Q(rgmii_tx_data[0]),
		.D1(gmii_tx_data[0]),
		.D2(gmii_tx_data[4]),
		.C(tx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE")
	) oddr_tx_data_1 (
		.Q(rgmii_tx_data[1]),
		.D1(gmii_tx_data[1]),
		.D2(gmii_tx_data[5]),
		.C(tx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE")
	) oddr_tx_data_2 (
		.Q(rgmii_tx_data[2]),
		.D1(gmii_tx_data[2]),
		.D2(gmii_tx_data[6]),
		.C(tx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE")
	) oddr_tx_data_3 (
		.Q(rgmii_tx_data[3]),
		.D1(gmii_tx_data[3]),
		.D2(gmii_tx_data[7]),
		.C(tx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	///////////////////////////////////////////////////////////////////////////
	//Señales de recepción
	///////////////////////////////////////////////////////////////////////////

	//Señales de control

	IDDR #(
		.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
	) iddr_rx_ctl (
		.Q1(gmii_rx_dv),
		.Q2(rx_error),
		.D(rgmii_rx_ctl),
		.C(rx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	//Datos

	IDDR #(
		.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
	) iddr_rx_data_0 (
		.Q1(gmii_rx_data[0]),
		.Q2(gmii_rx_data[4]),
		.D(rgmii_rx_data[0]),
		.C(rx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	IDDR #(
		.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
	) iddr_rx_data_1 (
		.Q1(gmii_rx_data[1]),
		.Q2(gmii_rx_data[5]),
		.D(rgmii_rx_data[1]),
		.C(rx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	IDDR #(
		.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
	) iddr_rx_data_2 (
		.Q1(gmii_rx_data[2]),
		.Q2(gmii_rx_data[6]),
		.D(rgmii_rx_data[2]),
		.C(rx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	IDDR #(
		.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
	) iddr_rx_data_3 (
		.Q1(gmii_rx_data[3]),
		.Q2(gmii_rx_data[7]),
		.D(rgmii_rx_data[3]),
		.C(rx_clk),
		.CE(1),
		.R(0),
		.S(0)
	);

	// Obtener estado del enlace
	// RGMII reporta el estado del enlace mientras no se reciben datos

	always @(posedge rx_clk) begin
		if (!gmii_rx_dv && !gmii_rx_er) begin
			status <= rgmii_rx_data;
		end
	end

endmodule
